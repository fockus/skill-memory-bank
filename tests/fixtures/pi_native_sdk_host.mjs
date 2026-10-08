// Public SDK host contract fixture. No model prompts or child execution.
import { readFile, mkdir, access, cp } from "node:fs/promises";
import { createRequire } from "node:module";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const input = JSON.parse(await new Promise(resolveInput => {
  let data = ""; process.stdin.on("data", chunk => { data += chunk; });
  process.stdin.on("end", () => resolveInput(data));
}));
// This isolated fixture models operator startup, not the retained writer's child mode.
delete process.env.PI_SUBAGENT_CHILD;
delete process.env.PI_SUBAGENTS_HERDR_BRIDGE;
if (input.scenario === "child-context") process.env.PI_SUBAGENT_CHILD = "1";
const root = resolve(new URL("../../", import.meta.url).pathname);
const sdkRoot = process.env.PI_SDK_ROOT || join(execFileSync("npm", ["root", "-g"], { encoding: "utf8" }).trim(), "@earendil-works/pi-coding-agent");
const manifest = JSON.parse(await readFile(join(sdkRoot, "package.json"), "utf8"));
const sdk = await import(pathToFileURL(join(sdkRoot, manifest.exports["."].import)).href);
const agentDir = join(input.home, ".pi", "agent");
await mkdir(agentDir, { recursive: true });
process.env.PI_CODING_AGENT_DIR = agentDir;
process.chdir(input.cwd);
const product = join(root, "adapters/pi_native_bootstrap.mjs");
let available = true;
try { await access(product); } catch { available = false; }
const result = { sdkVersion: manifest.version, ready: false, modelCalls: 0, childCalls: 0 };
if (!available) {
  // RED control: an actual ordinary SDK session has no authoritative MB host binding.
  const { session } = await sdk.createAgentSession({ cwd: input.cwd, agentDir, sessionManager: sdk.SessionManager.inMemory(input.cwd) });
  result.sessionId = session.sessionManager.getSessionId();
  session.dispose();
} else {
  let { createManagedPi, loadBackendFactory } = await import(pathToFileURL(product).href);
  let { requireHostBinding } = await import(pathToFileURL(join(root, "adapters/pi_native_host.mjs")).href);
  const { writeFile } = await import("node:fs/promises");
  const scenario = input.scenario;
  const foreignPath = join(input.cwd, ".pi", "subagents.json");
  await mkdir(join(input.cwd, ".pi"), { recursive: true });
  const foreign = JSON.stringify({ agentMentions: true, maxConcurrent: 7 });
  await writeFile(foreignPath, foreign);
  const originalCwd = process.cwd();
  const apis = [], contexts = [];
  let emitLate, changeSettings;
  if (scenario === "untrusted") {
    await mkdir(join(input.cwd, ".pi", "extensions"));
    await writeFile(join(input.cwd, ".pi", "extensions", "foreign.mjs"), "export default function(pi) { pi.registerCommand('foreign', {description:'foreign',handler: async()=>{}}); }");
  }
  const components = [{ name: "tintin", source: "explicit contract double", version: "fixture", factory(pi) {
    if (scenario === "factory-failure") throw new Error("factory failed");
    pi.on("session_start", () => pi.events.on("subagents:rpc:ping", request => {
      pi.events.emit(`subagents:rpc:ping:reply:${request.requestId}`, { success: true, data: { version: 2 } });
    }));
    const settings = JSON.parse(readFileSync(".pi/subagents.json", "utf8"));
    pi.events.emit("subagents:settings_loaded", { settings: { agentMentions: scenario === "ignored-overlay" ? "model" : settings.agentMentions === false ? "off" : "model" } });
    emitLate = () => pi.events.emit("subagents:settings_loaded", { settings: { agentMentions: "model" } });
    changeSettings = () => pi.events.emit("subagents:settings_changed", { settings: { agentMentions: "off" } });
  } }];
  if (scenario === "real-tintin") {
    if (!process.env.PI_TINTIN_ROOT) throw new Error("PI_TINTIN_ROOT must identify the isolated pinned package");
    components[0] = await loadBackendFactory(process.env.PI_TINTIN_ROOT, sdkRoot);
    if (process.env.PI_NICO_ROOT) components.push(await loadBackendFactory(process.env.PI_NICO_ROOT, sdkRoot));
  }
  if (scenario === "duplicate") components.push(components[0]);
  let ownedFactory, memoryBankSource, nativeCreateBackend;
  if (scenario === "real-tintin") {
    const compiled = join(input.home, "owned-native");
    await cp(join(root, "adapters"), compiled, { recursive: true });
    memoryBankSource = join(compiled, "pi_subagent_extension.ts");
    await writeFile(memoryBankSource, (await readFile(memoryBankSource, "utf8")).replaceAll("__MB_SKILL_DIR_JSON__", JSON.stringify(root)));
    const require = createRequire(join(sdkRoot, "package.json"));
    const compiler = require("jiti").createJiti(import.meta.url, { alias: { typebox: require.resolve("typebox"),
      "@earendil-works/pi-coding-agent": join(sdkRoot, manifest.exports["."].import) } });
    ownedFactory = await compiler.import(memoryBankSource, { default: true });
    nativeCreateBackend = (await compiler.import(join(compiled, "pi_native_backend.mjs"))).createBackend;
    ({ createManagedPi } = await import(pathToFileURL(join(compiled, "pi_native_bootstrap.mjs")).href));
    ({ requireHostBinding } = await import(pathToFileURL(join(compiled, "pi_native_host.mjs")).href));
  }
  let managed;
  const refused = callback => { try { callback(); return false; } catch { return true; } };
  try {
    managed = await createManagedPi({ sdk, cwd: input.cwd, agentDir, components,
      sessionManager: sdk.SessionManager.inMemory(input.cwd), memoryBankSource,
      async memoryBankFactory(pi) {
        apis.push(pi);
        pi.on("before_provider_request", () => { result.modelCalls++; });
        pi.events.on("subagents:rpc:spawn", () => { result.childCalls++; });
        pi.events.on("subagents:rpc:v1:request", request => { if (request.method === "spawn") result.childCalls++; });
        if (scenario === "early") result.refused = refused(() => requireHostBinding(pi, {}));
        pi.on("session_start", (_event, ctx) => contexts.push(ctx));
        if (ownedFactory) await ownedFactory(pi);
      } });
    const current = () => requireHostBinding(apis.at(-1), contexts.at(-1));
    result.binding = current();
    result.sessionId = managed.runtime.session.sessionManager.getSessionId();
    result.ready = true;
    const mb = managed.runtime.services.resourceLoader.getExtensions().extensions.find(extension => extension.path === "<inline:mb-managed-mb>");
    result.mbCommands = [...mb.commands.keys()]; result.mbTools = [...mb.tools.keys()];
    if (nativeCreateBackend) {
      const selected = components.some(component => component.name === "nico") ? "nico" : "tintin";
      const backend = await nativeCreateBackend({ name: selected, pi: apis.at(-1), ctx: contexts.at(-1), runId: "model-free-smoke", decoder: () => { throw new Error("No role preflight in model-free host smoke"); } });
      result.consumerReady = !!backend.binding;
    }
    if (scenario === "unknown") result.refused = refused(() => requireHostBinding({}, contexts.at(-1)));
    if (scenario === "forged") result.refused = refused(() => requireHostBinding({ binding: result.binding }, contexts.at(-1)));
    if (scenario === "session-mismatch") result.refused = refused(() => requireHostBinding(apis.at(-1), { sessionManager: { getSessionId: () => "another" } }));
    if (scenario === "disposed") { await managed.dispose(); result.refused = refused(current); }
    if (scenario === "late") { emitLate(); result.refused = refused(current); }
    if (scenario === "settings-changed" || scenario === "settings-rebind") {
      changeSettings();
      if (scenario === "settings-rebind") await managed.runtime.session.bindExtensions({});
      result.refused = refused(current);
    }
    if (scenario === "real-tintin") {
      result.mentionChecks = [];
      const inspectMentions = async label => {
        const response = await managed.runtime.session.extensionRunner.emitInput("@main KEEP_PROJECT_CONTEXT", undefined, "interactive");
        const before = await managed.runtime.session.extensionRunner.emitBeforeAgentStart("Plain model-free hook probe", undefined, { cwd: input.cwd });
        result.mentionChecks.push({ label, action: response.action, text: response.text,
          reminder: JSON.stringify(before.messages || []).includes("agent_mention"),
          cwd: contexts.at(-1).cwd, mentions: current().components.tintin.agentMentions });
      };
      await managed.runtime.session.bindExtensions({ mode: "tui", onError: error => { result.lifecycleError = error.message; } });
      await inspectMentions("after-tui-context-binding");
      const oldApi = apis.at(-1), oldCtx = contexts.at(-1);
      await managed.runtime.session.reload();
      result.reloadOldRefused = refused(() => requireHostBinding(oldApi, oldCtx));
      await inspectMentions("after-sdk-settings-resource-reload");
      result.reloadInventory = current().inventory;
      result.binding = current();
    }
    if (scenario === "replacement" || scenario === "real-tintin") {
      const old = { api: apis[0], ctx: contexts[0], binding: result.binding, emit: emitLate };
      await managed.runtime.newSession();
      result.binding = current();
      result.previousSessionId = result.sessionId;
      result.sessionId = managed.runtime.session.sessionManager.getSessionId();
      result.sessionChanged = old.binding.sessionId !== result.binding.sessionId;
      result.generationChanged = old.binding.generation !== result.binding.generation;
      result.oldRefused = refused(() => requireHostBinding(old.api, old.ctx));
      old.emit?.(); result.lateIgnored = current() === result.binding;
    }
    result.foreignUnchanged = await readFile(foreignPath, "utf8") === foreign;
    result.cwdUnchanged = process.cwd() === originalCwd;
    await managed.dispose();
    result.disposedRefuses = refused(current);
  } catch (error) {
    result.refused = true; result.error = error.message; result.errorStack = error.stack;
    await managed?.dispose();
  }
}
console.log(JSON.stringify(result));
