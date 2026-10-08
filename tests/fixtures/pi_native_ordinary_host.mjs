// Real public SDK and pinned Tintin; no model or child requests in startup tests.
import { cp, mkdir, readFile, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const input = JSON.parse(await new Promise(done => {
  let text = "";
  process.stdin.on("data", chunk => { text += chunk; });
  process.stdin.on("end", () => done(text));
}));
const root = resolve(new URL("../../", import.meta.url).pathname);
const agentDir = join(input.home, ".pi", "agent");
await mkdir(agentDir, { recursive: true });
process.env.HOME = input.home;
process.env.PI_CODING_AGENT_DIR = agentDir;
process.env.MB_PI_TINTIN_ROOT = input.tintinRoot;
process.env.PI_OFFLINE = "1";
delete process.env.PI_SUBAGENT_CHILD;
delete process.env.PI_SUBAGENTS_HERDR_BRIDGE;
if (input.scenario === "child") process.env.PI_SUBAGENT_CHILD = "1";
process.chdir(input.cwd);
const sdkRoot = process.env.PI_SDK_ROOT;
const manifest = JSON.parse(await readFile(join(sdkRoot, "package.json"), "utf8"));
const sdk = await import(pathToFileURL(join(sdkRoot, manifest.exports["."].import)).href);
const compiled = join(input.home, "owned-adapters");
await cp(join(root, "adapters"), compiled, { recursive: true });
const source = join(compiled, "pi_subagent_extension.ts");
await writeFile(source, (await readFile(source, "utf8")).replaceAll("__MB_SKILL_DIR_JSON__", JSON.stringify(root)));
const require = createRequire(join(sdkRoot, "package.json"));
const compiler = require("jiti").createJiti(import.meta.url, { alias: { typebox: require.resolve("typebox"),
  "@earendil-works/pi-coding-agent": join(sdkRoot, manifest.exports["."].import) } });
const memoryBank = await compiler.import(source, { default: true });
const { requireHostBinding, requireHostService } = await import(pathToFileURL(join(compiled, "pi_native_host.mjs")).href);
const apis = [], contexts = [], errors = [];
let modelCalls = 0, childCalls = 0;
const foreign = join(input.cwd, ".pi", "subagents.json");
await mkdir(join(input.cwd, ".pi"), { recursive: true });
const settings = JSON.stringify({ agentMentions: true, maxConcurrent: 3 });
await writeFile(foreign, settings);
if (input.scenario === "untrusted") await writeFile(join(input.cwd, ".pi", "APPEND_SYSTEM.md"), "Untrusted fixture instructions");
const result = { ready: false };
let session, transport, modelRuntime, model;
if (input.scenario === "leaf") {
  const { createReadService } = await import("./pi_native_read_service.mjs");
  const path = join(input.cwd, "read-proof.txt"), marker = "ORDINARY_PI_NATIVE_READ";
  await writeFile(path, marker);
  transport = await createReadService(path, marker);
  await writeFile(join(agentDir, "auth.json"), "{}");
  await writeFile(join(agentDir, "models.json"), JSON.stringify({ providers: { openai: {
    api: "openai-responses", baseUrl: transport.endpoint, apiKey: "mb-local-read-synthetic",
    models: [{ id: "gpt-4.1", name: "Read transport fixture", api: "openai-responses", reasoning: false,
      input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 128000, maxTokens: 32768 }],
  } } }));
  modelRuntime = await sdk.ModelRuntime.create({ authPath: join(agentDir, "auth.json"),
    modelsPath: join(agentDir, "models.json"), modelsStorePath: join(agentDir, "catalog"),
    allowModelNetwork: false, refreshOnCreate: false });
  await modelRuntime.refresh({ allowNetwork: false });
  model = new sdk.ModelRegistry(modelRuntime).find("openai", "gpt-4.1");
  if (model?.baseUrl !== transport.endpoint) throw new Error("Unsafe test model route");
  await mkdir(join(agentDir, "agents"));
  await mkdir(join(input.cwd, ".memory-bank"));
  await writeFile(join(agentDir, "agents", "read-probe.md"),
    "---\nname: read-probe\nmodel: inherit\ntools: read\n---\nRead the requested file and report its content.\n");
}
const inspect = () => requireHostBinding(apis.at(-1), contexts.at(-1));
const refused = fn => { try { fn(); return false; } catch { return true; } };
try {
  const factories = [];
  if (input.scenario === "duplicate") {
    const { loadBackendFactory } = await import(pathToFileURL(join(compiled, "pi_native_bootstrap.mjs")).href);
    const component = await loadBackendFactory(input.tintinRoot, sdkRoot);
    factories.push({ name: "existing-tintin", factory: component.factory });
  }
  factories.push({ name: "ordinary-mb", async factory(pi) {
    apis.push(pi);
    pi.on("before_provider_request", () => { modelCalls++; });
    pi.events.on("subagents:rpc:spawn", () => { childCalls++; });
    await memoryBank(pi);
    pi.on("session_start", (_event, ctx) => contexts.push(ctx));
  } });
  const settingsManager = sdk.SettingsManager.inMemory({});
  settingsManager.setProjectTrusted(input.scenario !== "untrusted");
  const services = await sdk.createAgentSessionServices({ cwd: input.cwd, agentDir, modelRuntime,
    settingsManager,
    resourceLoaderOptions: { noSkills: true, noPromptTemplates: true, extensionFactories: factories } });
  errors.push(...services.resourceLoader.getExtensions().errors.map(error => error.error));
  ({ session } = await sdk.createAgentSessionFromServices({ services, model,
    sessionManager: sdk.SessionManager.inMemory(input.cwd) }));
  await session.bindExtensions({ onError: error => errors.push(String(error.error || error.message || error)) });
  result.binding = inspect();
  result.ready = true;
  result.sessionId = session.sessionManager.getSessionId();
  result.tools = session.getAllTools().map(tool => tool.name);
  result.registryReady = typeof requireHostService(apis.at(-1), contexts.at(-1), "tintin").registry?.getRecord === "function";
  if (input.scenario === "leaf") {
    const deadline = setTimeout(() => session.abort(), 20000);
    try {
      await session.prompt(`Use mb_dispatch_subagent to run read-probe on ${join(input.cwd, "read-proof.txt")}.`);
      const answer = session.messages.find(message => message.role === "toolResult" && message.toolName === "mb_dispatch_subagent");
      if (!answer || answer.isError) throw new Error(JSON.stringify(answer?.content || session.messages));
      result.answer = answer.content;
      const id = answer.details.receipt.runId;
      const registry = requireHostService(apis.at(-1), contexts.at(-1), "tintin").registry;
      const record = registry.getRecord(id), leaf = record.session;
      result.childId = id;
      result.childSessionId = leaf.sessionManager.getSessionId();
      result.childModel = `${leaf.model.provider}/${leaf.model.id}`;
      result.parentModel = `${session.model.provider}/${session.model.id}`;
      result.childTools = leaf.getAllTools().map(tool => tool.name);
      result.childExtensions = leaf.resourceLoader.getExtensions().extensions.map(extension => extension.path);
      result.toolResults = leaf.messages.filter(message => message.role === "toolResult");
      result.consumed = record.resultConsumed;
      result.running = registry.hasRunning();
      result.requests = transport.requests.length;
      result.transportError = transport.error;
    } finally { clearTimeout(deadline); }
  }
  if (input.scenario === "settings-changed") {
    apis.at(-1).events.emit("subagents:settings_changed", { settings: { agentMentions: "model" } });
    result.refused = refused(inspect);
    await session.bindExtensions({});
    result.rebindRefused = refused(inspect);
  }
  if (input.scenario === "reload") {
    const oldApi = apis.at(-1), oldCtx = contexts.at(-1), oldBinding = result.binding;
    await session.reload();
    result.oldRefused = refused(() => requireHostBinding(oldApi, oldCtx));
    result.newBinding = inspect();
    result.generationChanged = result.newBinding.generation !== oldBinding.generation;
  }
  if (input.scenario === "session-mismatch") {
    result.refused = refused(() => requireHostBinding(apis.at(-1), { ...contexts.at(-1), sessionManager: { getSessionId: () => "foreign" } }));
  }
  if (input.scenario === "cwd-mismatch") result.refused = refused(() => requireHostBinding(apis.at(-1), { ...contexts.at(-1), cwd: input.home }));
  if (input.scenario === "forged") result.refused = refused(() => requireHostBinding({ binding: result.binding }, contexts.at(-1)));
  if (input.scenario === "shutdown") {
    await session.extensionRunner.emit({ type: "session_shutdown" });
    result.refused = refused(inspect);
  }
} catch (error) {
  result.error = error.message;
} finally {
  await session?.extensionRunner?.emit({ type: "session_shutdown" });
  session?.dispose();
  await transport?.close();
}
result.foreignUnchanged = await readFile(foreign, "utf8") === settings;
result.cwdUnchanged = process.cwd() === input.cwd;
result.modelCalls = modelCalls;
result.childCalls = childCalls;
result.errors = errors;
console.log(JSON.stringify(result));
