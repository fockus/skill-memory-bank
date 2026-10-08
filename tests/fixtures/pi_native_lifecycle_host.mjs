// Installed extension with the real public SDK; no model requests or forced exit.
import { watch } from "node:fs";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const input = JSON.parse(await new Promise(done => {
  let text = "";
  process.stdin.on("data", chunk => { text += chunk; });
  process.stdin.on("end", () => done(text));
}));
process.env.HOME = input.home;
process.env.PI_CODING_AGENT_DIR = join(input.home, ".pi", "agent");
process.env.PI_OFFLINE = "1";
process.env.MB_AUTOLOAD_CONTEXT = "off";
if (input.tintinRoot) process.env.MB_PI_TINTIN_ROOT = input.tintinRoot;
await mkdir(process.env.PI_CODING_AGENT_DIR, { recursive: true });
process.chdir(input.cwd);
const sdkRoot = process.env.PI_SDK_ROOT;
const manifest = JSON.parse(await readFile(join(sdkRoot, "package.json"), "utf8"));
const entry = join(sdkRoot, manifest.exports["."].import);
const sdk = await import(pathToFileURL(entry).href);
const require = createRequire(join(sdkRoot, "package.json"));
const compiler = require("jiti").createJiti(import.meta.url, {
  alias: { "@earendil-works/pi-coding-agent": entry }
});
const fileMode = input.scenario === "mb-file-reload";
const states = [], handlerErrors = [];
let modelCalls = 0;
const extension = fileMode ? undefined : await compiler.import(input.extension, { default: true });
const observer = pi => {
  pi.on("session_start", () => states.push({
    tools: pi.getAllTools().map(tool => tool.name), active: pi.getActiveTools(),
    nativeMB: pi.getCommands().some(command => command.name === "mb" && command.source === "extension")
  }));
  pi.on("before_provider_request", () => { modelCalls++; });
};
const factory = async target => {
  const services = await sdk.createAgentSessionServices({ ...target,
    settingsManager: sdk.SettingsManager.inMemory({}),
    resourceLoaderOptions: { noExtensions: true, noSkills: true, noPromptTemplates: true,
      additionalExtensionPaths: fileMode ? [input.extension] : [],
      extensionFactories: [{ name: "lifecycle-probe", factory: fileMode ? observer : extension }] } });
  const errors = services.resourceLoader.getExtensions().errors;
  if (errors.length) throw new Error(errors.map(error => error.error).join("; "));
  return { ...await sdk.createAgentSessionFromServices({ services,
    sessionManager: target.sessionManager }), services, diagnostics: services.diagnostics };
};
const countWatchers = () => process.getActiveResourcesInfo().filter(type => type === "FSEventWrap").length;
const before = countWatchers();
const timersBefore = process.getActiveResourcesInfo().filter(type => type === "Timeout").length;
const runtime = await sdk.createAgentSessionRuntime(factory, { cwd: input.cwd,
  agentDir: process.env.PI_CODING_AGENT_DIR, sessionManager: sdk.SessionManager.inMemory(input.cwd) });
const bindings = { onError: error => handlerErrors.push(String(error.error || error.message || error)) };
runtime.setRebindSession(async session => { await session.bindExtensions(bindings); });
await runtime.session.bindExtensions(bindings);
const started = countWatchers();
let reloaded;
if (input.scenario === "reload" || fileMode) {
  await runtime.session.reload();
  await new Promise(done => setImmediate(done));
  await new Promise(done => setImmediate(done));
  reloaded = countWatchers();
}
if (input.scenario === "request-shutdown") {
  const folder = join(input.home, ".pi", "agent", "inspect", "requests");
  await writeFile(join(folder, "invalid.tmp"), "{broken");
  await new Promise((done, reject) => {
    const observer = watch(folder, (_event, name) => {
      if (String(name) === "invalid.json.err.json") { clearTimeout(deadline); observer.close(); done(); }
    });
    const deadline = setTimeout(() => { observer.close(); reject(new Error("Request event unavailable")); }, 4000);
    rename(join(folder, "invalid.tmp"), join(folder, "invalid.json")).catch(error => {
      clearTimeout(deadline); observer.close(); reject(error);
    });
  });
}
const reloadDetails = {
  reloadErrors: runtime.services.resourceLoader.getExtensions().errors,
  afterTools: runtime.session.getAllTools().map(tool => tool.name),
  extensions: runtime.services.resourceLoader.getExtensions().extensions.map(extension => extension.path)
};
await runtime.dispose();
// The first check phase precedes close callbacks; observe after another turn.
await new Promise(done => setImmediate(done));
await new Promise(done => setImmediate(done));
console.log(JSON.stringify({ before, started, reloaded, after: countWatchers(), timersBefore,
  timersAfter: process.getActiveResourcesInfo().filter(type => type === "Timeout").length, states, modelCalls,
  handlerErrors, ...reloadDetails }));
