// Ordinary Pi's opted-in MB extension owns the pinned public Tintin factory.
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { activateBackend } from "./pi_native_component.mjs";
import { loadBackendFactory } from "./pi_native_bootstrap.mjs";
import { createHostAuthority, hasHostAuthority } from "./pi_native_host.mjs";
import { tintinRpc } from "./pi_native_tintin.mjs";

export async function registerOrdinaryHost(pi, { agentDir, sdkRoot, source, requiresProjectTrust }) {
  // The managed composition already attached its producer; never load a second engine.
  if (hasHostAuthority(pi) || process.env.PI_SUBAGENT_CHILD === "1" ||
      process.env.PI_SUBAGENTS_HERDR_BRIDGE === "1") return;
  const registryKey = Symbol.for("pi-subagents:manager");
  if (globalThis[registryKey]) throw new Error("Duplicate Tintin service; disable its standalone extension before loading MB");
  const component = await loadBackendFactory(process.env.MB_PI_TINTIN_ROOT ||
    join(agentDir, "npm", "node_modules", "@tintinweb/pi-subagents"), sdkRoot);
  if (component.name !== "tintin") throw new Error("Ordinary MB requires the pinned Tintin package");
  let anchor, context, disposed = false, invalidated = false;
  const authority = createHostAuthority(() => anchor,
    () => ({ cwd: context?.cwd, agentDir, inventoryScope: "owned-factories" }));
  const invalidate = reason => { invalidated = true; authority.invalidate(reason); };
  const overlay = await mkdtemp(join(tmpdir(), "mb-pi-extension-"));
  let record;
  try {
    let settings = {};
    try { settings = JSON.parse(await readFile(join(process.cwd(), ".pi", "subagents.json"), "utf8")); }
    catch (error) { if (error.code !== "ENOENT") throw error; }
    await mkdir(join(overlay, ".pi"));
    await writeFile(join(overlay, ".pi", "subagents.json"),
      JSON.stringify({ ...settings, agentMentions: false }), { mode: 0o600 });
    record = activateBackend(component, pi, { overlay, runtimePath: component.source,
      invalidate, isDisposed: () => disposed, hideTools: true });
  } finally { await rm(overlay, { recursive: true, force: true }); }
  authority.attach(pi);
  const offSettings = pi.events.on("subagents:settings_changed", () => invalidate("Tintin effective settings changed"));
  pi.on("session_start", async (_event, ctx) => {
    if (disposed || invalidated) return;
    authority.invalidate("ordinary session rebinding");
    if (requiresProjectTrust(ctx.cwd) && !ctx.isProjectTrusted()) throw new Error("MB dispatch requires the project trust decision");
    if (globalThis[registryKey] !== record.registry) throw new Error("Tintin service ownership changed");
    if ((await tintinRpc(pi.events, "ping"))?.version !== 2) throw new Error("Tintin public v2 readiness unavailable");
    if (disposed || invalidated) return;
    context = ctx;
    // Public session identity is the anchor; no private AgentSession access is needed.
    anchor = { sessionManager: ctx.sessionManager };
    const mb = { name: "mb", source, version: "1", runtimePath: source };
    authority.publish([record, mb], [{ path: record.runtimePath }, { path: source }]);
  });
  pi.on("tool_call", event => {
    if (record.tools.has(event.toolName)) return { block: true,
      reason: "Raw native delegation bypasses MB ownership/gates; use mb_dispatch_subagent" };
  });
  pi.on("session_before_switch", () => { anchor = undefined; authority.invalidate("session replacement"); });
  pi.on("session_shutdown", () => {
    disposed = true; invalidate("extension shutdown"); anchor = undefined;
    record.dispose(); offSettings();
  });
}
