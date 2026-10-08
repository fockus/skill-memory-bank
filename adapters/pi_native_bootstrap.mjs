// Optional composition of the existing public Pi SDK/runtime/TUI. No executor.
import { readFile, mkdir, mkdtemp, rm, realpath } from "node:fs/promises";
import { existsSync, mkdirSync, readFileSync, rmdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { createRequire } from "node:module";
import { createHostAuthority } from "./pi_native_host.mjs";
import { rpc } from "./pi_native_subagents.mjs";
import { tintinRpc } from "./pi_native_tintin.mjs";
import { activateBackend } from "./pi_native_component.mjs";

async function jsonFile(path) {
  try { return JSON.parse(await readFile(path, "utf8")); }
  catch (error) { if (error.code === "ENOENT") return {}; throw error; }
}

// Resolve only manifest-declared public ESM exports in the installed SDK tree.
async function publicEntry(specifier, sdkRoot) {
  const parts = specifier.split("/");
  const nameParts = specifier.startsWith("@") ? 2 : 1;
  const name = parts.slice(0, nameParts).join("/");
  const subpath = parts.slice(nameParts).join("/");
  let cursor = sdkRoot;
  while (true) {
    for (const folder of [cursor, join(cursor, "node_modules", name)]) {
      const manifest = await jsonFile(join(folder, "package.json"));
      if (manifest.name !== name) continue;
      const key = subpath ? `./${subpath}` : ".";
      let exported = manifest.exports?.[key], wildcard;
      if (!exported) {
        for (const [pattern, value] of Object.entries(manifest.exports || {})) {
          const [prefix, suffix] = pattern.split("*");
          if (suffix !== undefined && key.startsWith(prefix) && key.endsWith(suffix)) {
            exported = value; wildcard = key.slice(prefix.length, suffix ? -suffix.length : undefined); break;
          }
        }
      }
      let entry = typeof exported === "string" ? exported : exported?.import || exported?.default || (!manifest.exports && !subpath ? manifest.main : undefined);
      if (wildcard !== undefined && typeof entry === "string") entry = entry.replaceAll("*", wildcard);
      if (typeof entry !== "string") throw new Error(`No public ESM export for ${specifier}`);
      return resolve(folder, entry);
    }
    const parent = dirname(cursor);
    if (parent === cursor) throw new Error(`Installed SDK dependency unavailable: ${specifier}`);
    cursor = parent;
  }
}

// Uses the installed SDK's existing public jiti dependency, not a private SDK loader.
export async function loadBackendFactory(packageRoot, sdkRoot) {
  const manifest = await jsonFile(join(packageRoot, "package.json"));
  const name = manifest.name === "pi-subagents" ? "nico" :
    manifest.name === "@tintinweb/pi-subagents" ? "tintin" : undefined;
  if (!name || manifest.pi?.extensions?.length !== 1) throw new Error("Unsupported native backend package entrypoint");
  if (name === "tintin" && manifest.version !== "0.19.0") throw new Error("Tintin requires verified version 0.19.0");
  const require = createRequire(join(sdkRoot, "package.json"));
  const { createJiti } = require("jiti");
  const alias = {};
  for (const specifier of ["@earendil-works/pi-coding-agent", "@earendil-works/pi-agent-core", "@earendil-works/pi-tui", "@earendil-works/pi-ai/compat", "@earendil-works/pi-ai/oauth", "@earendil-works/pi-ai/providers/all"]) {
    alias[specifier] = await publicEntry(specifier, sdkRoot);
  }
  alias["@earendil-works/pi-ai"] = alias["@earendil-works/pi-ai/compat"];
  const source = await realpath(resolve(packageRoot, manifest.pi.extensions[0]));
  const factory = await createJiti(import.meta.url, { alias, interopDefault: true }).import(source, { default: true });
  if (typeof factory !== "function") throw new Error("Native package has no public extension factory");
  const publicExport = async (subpath, symbol) => {
    const declared = manifest.exports?.[subpath];
    const entry = typeof declared === "string" ? declared : declared?.import || declared?.default;
    if (!entry) throw new Error(`Nico public ${subpath.slice(2)} export unavailable`);
    return (await createJiti(import.meta.url, { alias }).import(resolve(packageRoot, entry)))[symbol];
  };
  let resolveLaunch, registerCapabilityCeiling;
  if (name === "nico") {
    resolveLaunch = await publicExport("./preflight", "resolveSubagentLaunchContract");
    registerCapabilityCeiling = await publicExport("./capability-ceiling", "registerSubagentCapabilityCeiling");
  }
  return { name, source, version: manifest.version, packageName: manifest.name, factory, resolveLaunch, registerCapabilityCeiling };
}

// Public SettingsStorage over the user's own settings files. The managed runtime
// reads a view in which configured native backend packages contribute no
// extension (their skills/prompts stay) and the owned MB extension is not
// discovered a second time: the managed factories load each of them once, and
// an unselected backend's raw delegation tools never appear. Writes are merged
// onto the real file content, never onto the view. The lock is the
// `<file>.lock` directory Pi's FileSettingsStorage takes, so concurrent
// ordinary Pi writers are serialized.
export const nativeBackendPackages = ["pi-subagents", "@tintinweb/pi-subagents"];
const isNativePackage = item => {
  const source = typeof item === "string" ? item : item?.source;
  return typeof source === "string" && nativeBackendPackages.some(name => source === `npm:${name}` || source.startsWith(`npm:${name}@`));
};

export function managedSettingsStorage(cwd, agentDir, { excludeExtensions = [] } = {}) {
  const paths = { global: join(agentDir, "settings.json"), project: join(cwd, ".pi", "settings.json") };
  const view = (scope, text) => {
    let settings;
    try { settings = text ? JSON.parse(text) : {}; }
    catch (error) { throw new Error(`Invalid ${scope} Pi settings: ${error.message}`, { cause: error }); }
    if (Array.isArray(settings.packages)) {
      settings.packages = settings.packages.map(item => isNativePackage(item)
        ? { ...(typeof item === "string" ? { source: item } : item), extensions: [] } : item);
    }
    if (scope === "global" && excludeExtensions.length) {
      settings.extensions = [...(settings.extensions || []), ...excludeExtensions.map(path => `-${path}`)];
    }
    return text || scope === "global" ? JSON.stringify(settings) : text;
  };
  const lock = path => {
    for (let attempt = 0; ; attempt++) {
      try { mkdirSync(`${path}.lock`); return () => rmdirSync(`${path}.lock`); }
      catch (error) {
        if (error.code !== "EEXIST" || attempt === 50) throw error;
        Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 20);
      }
    }
  };
  return {
    withLock(scope, fn) {
      const path = paths[scope];
      const exists = existsSync(path);
      let release = exists ? lock(path) : undefined;
      try {
        const current = exists ? readFileSync(path, "utf8") : undefined;
        if (fn(view(scope, current)) === undefined) return;
        const next = fn(current);
        const written = JSON.parse(next), real = current ? JSON.parse(current) : {};
        for (const field of ["packages", "extensions"]) {
          if (JSON.stringify(written[field]) !== JSON.stringify(real[field])) {
            throw new Error(`Managed runtime refuses to persist ${field}; change them from ordinary pi`);
          }
        }
        mkdirSync(dirname(path), { recursive: true });
        release ||= lock(path);
        writeFileSync(path, next, "utf8");
      } finally { release?.(); }
    },
  };
}

// Trusted startup inputs only: factories are actual public package factories or
// explicitly labeled contract doubles. No tool/command JSON can call this root.
export async function createManagedPi({ sdk, cwd, agentDir, components, memoryBankFactory, memoryBankSource,
  sessionManager, model, thinkingLevel, servicesOptions = {}, resourceLoaderOptions = {} }) {
  if (!memoryBankFactory) throw new Error("Managed startup requires the owned Memory Bank factory");
  if (process.env.PI_SUBAGENT_CHILD === "1" || process.env.PI_SUBAGENTS_HERDR_BRIDGE === "1") throw new Error("Managed operator startup is unavailable in a native child/bridge context");
  if (resourceLoaderOptions.noExtensions || resourceLoaderOptions.extensionsOverride) {
    throw new Error("Cannot safely compose disabled/replaced extension discovery");
  }
  let runtime, records = [], disposed = false;
  const authority = createHostAuthority(() => runtime?.session, () => ({ cwd: runtime?.cwd, agentDir: runtime?.services.agentDir }));
  const eventBus = sdk.createEventBus();
  const cleanups = new Set();
  const overlay = await mkdtemp(join(tmpdir(), "mb-pi-runtime-"));
  const foreignSettings = await jsonFile(join(cwd, ".pi", "subagents.json"));
  await mkdir(join(overlay, ".pi"), { recursive: true });
  await import("node:fs/promises").then(fs => fs.writeFile(join(overlay, ".pi", "subagents.json"),
    JSON.stringify({ ...foreignSettings, agentMentions: false }), { mode: 0o600 }));
  const componentNames = components.map(component => component.name);
  if (new Set(componentNames).size !== componentNames.length) {
    await rm(overlay, { recursive: true, force: true });
    throw new Error("Duplicate native backend service");
  }
  const factories = components.map(component => ({ name: `mb-managed-${component.name}`,
    factory(pi) {
      authority.invalidate("factory/runtime refresh");
      const previous = records.find(record => record.name === component.name);
      previous?.dispose();
      const record = activateBackend(component, pi, { overlay,
        runtimePath: `<inline:mb-managed-${component.name}>`,
        invalidate: reason => authority.invalidate(reason), isDisposed: () => disposed });
      cleanups.add(record.dispose);
      records = records.filter(item => item.name !== component.name).concat(record);
    },
  }));
  factories.push({ name: "mb-managed-mb", async factory(pi) {
    authority.attach(pi);
    records = records.filter(item => item.name !== "mb").concat({ name: "mb", source: memoryBankSource || "explicit injected MB contract factory", version: "1", runtimePath: "<inline:mb-managed-mb>" });
    pi.on("session_shutdown", () => authority.invalidate("session shutdown"));
    pi.on("session_start", async () => {
      if (disposed) return;
      const session = runtime.session;
      for (const component of components) {
        if (component.name === "nico") {
          const ping = await rpc(eventBus, "ping");
          if (typeof (ping.events?.asyncComplete || ping.capabilities?.events?.asyncComplete) !== "string") throw new Error("Loaded Nico service lacks public completion readiness");
        } else if (component.name === "tintin" && (await tintinRpc(eventBus, "ping"))?.version !== 2) throw new Error("Loaded Tintin service lacks public v2 readiness");
      }
      if (disposed || runtime.session !== session) return;
      authority.publish(records, runtime.services.resourceLoader.getExtensions().extensions);
    });
    pi.on("tool_call", event => {
      const loaded = runtime?.services.resourceLoader.getExtensions().extensions || [];
      const nativeTool = loaded.some(extension => components.some(component => extension.path === `<inline:mb-managed-${component.name}>`) && extension.tools.has(event.toolName));
      if (nativeTool) return { block: true, reason: "Raw native delegation bypasses Memory Bank ownership/gates; use the selected MB dispatcher" };
    });
    await memoryBankFactory(pi);
  } });
  const createRuntime = async target => {
    authority.invalidate("session/runtime replacement");
    const settingsManager = servicesOptions.settingsManager || sdk.SettingsManager.fromStorage(
      managedSettingsStorage(target.cwd, target.agentDir, { excludeExtensions: memoryBankSource ? [memoryBankSource] : [] }),
      { projectTrusted: false });
    if (!servicesOptions.resourceLoaderReloadOptions?.resolveProjectTrust) {
      const requiresTrust = sdk.hasTrustRequiringProjectResources(target.cwd);
      const stored = new sdk.ProjectTrustStore(target.agentDir).get(target.cwd);
      const policy = settingsManager.getDefaultProjectTrust();
      const trusted = !requiresTrust || stored === true || (stored === null && policy === "always");
      if (!trusted) throw new Error("Managed startup needs an existing project trust decision or public SDK trust resolver; no implicit trust bypass");
      settingsManager.setProjectTrusted(true);
      await settingsManager.reload();
    }
    // Backend packages are recomposed by managedSettingsStorage (applyOverrides
    // does not reach SDK 1.0.2 package resolution). Unknown duplicates refuse below.
    const services = await sdk.createAgentSessionServices({ ...servicesOptions, ...target, settingsManager,
      resourceLoaderOptions: { ...resourceLoaderOptions, eventBus,
        extensionFactories: [
          { name: "codemode", builtin: true, replaceable: true, factory: sdk.createCodemodeExtension() },
          { name: "tool_search", builtin: true, replaceable: true, factory: sdk.createToolSearchExtension() },
          { name: "mcp", builtin: true, replaceable: true, factory: sdk.createMcpExtension() },
          ...(resourceLoaderOptions.extensionFactories || []), ...factories,
        ],
        extensionsOverride(base) {
          if (base.errors.length) throw new Error(`Managed factory failure: ${base.errors.map(item => item.error).join("; ")}`);
          const servicesSeen = new Set();
          for (const extension of base.extensions) {
            for (const component of components) {
              if (extension.path === component.source) throw new Error(`Duplicate ${component.name} service in normal discovery`);
            }
            for (const name of [...extension.tools.keys()].map(name => `tool:${name}`).concat([...extension.commands.keys()].map(name => `command:${name}`))) {
              if (servicesSeen.has(name)) throw new Error(`Duplicate service registration: ${name}`);
              servicesSeen.add(name);
            }
          }
          return base;
        },
      } });
    if (services.diagnostics.some(diagnostic => diagnostic.type === "error")) throw new Error("Managed SDK services reported startup errors");
    return { ...await sdk.createAgentSessionFromServices({ services, sessionManager: target.sessionManager,
      sessionStartEvent: target.sessionStartEvent, model, thinkingLevel }), services, diagnostics: services.diagnostics };
  };
  const dispose = async () => {
    disposed = true; authority.invalidate("disposed");
    for (const cleanup of cleanups) cleanup();
    await runtime?.dispose(); eventBus.clear();
    await rm(overlay, { recursive: true, force: true });
  };
  try {
    runtime = await sdk.createAgentSessionRuntime(createRuntime, { cwd, agentDir,
      sessionManager: sessionManager || sdk.SessionManager.create(cwd, join(agentDir, "sessions")) });
    runtime.setBeforeSessionInvalidate(() => authority.invalidate("SDK runtime invalidation"));
    runtime.setRebindSession(async session => { await session.bindExtensions({}); });
    await runtime.session.bindExtensions({});
    if (!authority.inspect()) throw new Error("Managed startup did not produce a ready binding");
    return { runtime, authority, eventBus, dispose,
      async runInteractive(options = {}) { return new sdk.InteractiveMode(runtime, options).run(); } };
  } catch (error) { await dispose(); throw error; }
}
