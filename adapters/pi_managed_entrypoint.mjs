#!/usr/bin/env node
// Memory Bank managed Pi entrypoint (AGR-058), installed by adapters/pi.sh as the owned
// <agentDir>/bin/mb-pi. It composes the installed public Pi SDK through the sibling
// extensions/pi_native_bootstrap.mjs and starts the existing InteractiveMode; ordinary
// `pi`, PATH and foreign settings are left alone.
import { realpathSync, readFileSync, existsSync } from "node:fs";
import { createRequire } from "node:module";
import { delimiter, dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const USAGE = "Usage: mb-pi [--with-nico] [--check] [--] [message ...]";
const agentDir = dirname(dirname(realpathSync(fileURLToPath(import.meta.url))));
const extensions = join(agentDir, "extensions");

function parse(argv) {
  const options = { withNico: false, check: false, messages: [] };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--") { options.messages.push(...argv.slice(i + 1)); break; }
    if (arg === "--with-nico") options.withNico = true;
    else if (arg === "--check") options.check = true;
    else if (arg === "--help" || arg === "-h") { console.log(USAGE); process.exit(0); }
    else if (arg.startsWith("-")) throw new Error(`unknown option ${arg}\n${USAGE}`);
    else options.messages.push(arg);
  }
  return options;
}

function readManifest(path) {
  try { return JSON.parse(readFileSync(path, "utf8")); }
  catch (error) { throw new Error(`Invalid Pi package manifest ${path}: ${error.message}`, { cause: error }); }
}

// Installed Pi: MB_PI_SDK_ROOT, else this agentDir's managed install (Pi >= 1.1:
// install/current-version names releases/<v>), else the package behind `pi` on PATH.
function sdkRoot() {
  if (process.env.MB_PI_SDK_ROOT) return process.env.MB_PI_SDK_ROOT;
  const versionFile = join(agentDir, "install", "current-version");
  if (existsSync(versionFile)) {
    const version = readFileSync(versionFile, "utf8").trim();
    if (!/^[0-9A-Za-z._+-]+$/.test(version) || version === "." || version === "..") {
      throw new Error(`managed Pi version file is invalid: ${versionFile}`);
    }
    const managed = join(agentDir, "install", "releases", version, "node_modules", "@earendil-works", "pi-coding-agent");
    if (existsSync(join(managed, "package.json"))) return managed;
  }
  for (const folder of (process.env.PATH || "").split(delimiter)) {
    const bin = join(folder, "pi");
    if (!folder || !existsSync(bin)) continue;
    for (let cursor = dirname(realpathSync(bin)); dirname(cursor) !== cursor; cursor = dirname(cursor)) {
      const manifest = join(cursor, "package.json");
      if (existsSync(manifest) && readManifest(manifest).name === "@earendil-works/pi-coding-agent") return cursor;
    }
  }
  throw new Error("installed Pi SDK not found: set MB_PI_SDK_ROOT or put `pi` on PATH");
}

function packageRoot(env, name) {
  const root = process.env[env] || join(agentDir, "npm", "node_modules", name);
  if (!existsSync(join(root, "package.json"))) {
    throw new Error(`${name} is not installed at ${root}; start ordinary pi once (Pi installs configured packages) or set ${env}`);
  }
  return root;
}

async function main() {
  const options = parse(process.argv.slice(2));
  if (process.env.PI_CODING_AGENT_DIR && realpathSync(process.env.PI_CODING_AGENT_DIR) !== agentDir) {
    throw new Error(`mb-pi belongs to ${agentDir}, but PI_CODING_AGENT_DIR is ${process.env.PI_CODING_AGENT_DIR}`);
  }
  process.env.PI_CODING_AGENT_DIR = agentDir;
  const root = sdkRoot();
  const manifest = readManifest(join(root, "package.json"));
  const sdk = await import(pathToFileURL(join(root, manifest.exports["."].import)).href);
  const { createManagedPi, loadBackendFactory } = await import(pathToFileURL(join(extensions, "pi_native_bootstrap.mjs")).href);
  const components = [await loadBackendFactory(packageRoot("MB_PI_TINTIN_ROOT", "@tintinweb/pi-subagents"), root)];
  if (options.withNico) components.push(await loadBackendFactory(packageRoot("MB_PI_NICO_ROOT", "pi-subagents"), root));
  const memoryBankSource = join(extensions, "memory-bank-subagent.ts");
  const require = createRequire(join(root, "package.json"));
  const compiler = require("jiti").createJiti(import.meta.url, { alias: { typebox: require.resolve("typebox"),
    "@earendil-works/pi-coding-agent": join(root, manifest.exports["."].import) } });
  const memoryBank = await compiler.import(memoryBankSource, { default: true });
  const cwd = process.cwd();
  const managed = await createManagedPi({ sdk, cwd, agentDir, components, memoryBankSource,
    memoryBankFactory: pi => memoryBank(pi) });
  if (!options.check) {
    const [initialMessage, ...initialMessages] = options.messages;
    return managed.runInteractive({ initialMessage, initialMessages });
  }
  const { session } = managed.runtime;
  const report = { ready: true, sdkVersion: manifest.version, cwd, agentDir, messages: options.messages,
    binding: managed.authority.inspect(), tools: session.getAllTools().map(tool => tool.name),
    extensions: managed.runtime.services.resourceLoader.getExtensions().extensions.map(extension => extension.path) };
  await managed.dispose();
  console.log(JSON.stringify(report));
}

main().catch(error => { console.error(`mb-pi: ${error.message}`); process.exit(1); });
