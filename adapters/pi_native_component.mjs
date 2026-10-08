// Attribute one public backend factory and its events without changing its executor.
export function activateBackend(component, pi, { overlay, runtimePath, invalidate,
  isDisposed = () => false, hideTools = false }) {
  const record = { ...component, runtimePath, settings: undefined, tools: new Set() };
  const subscriptions = [];
  record.dispose = () => { record.stale = true; for (const off of subscriptions.splice(0)) off(); };
  const queued = [];
  let inFactory = true;
  const api = Object.create(pi);
  api.registerTool = tool => {
    record.tools.add(tool.name);
    pi.registerTool(hideTools ? { ...tool, exposure: "hidden" } : tool);
  };
  api.events = {
    on(channel, callback) {
      const off = pi.events.on(channel, data => {
        if (!isDisposed() && !record.stale) return callback(data);
      });
      subscriptions.push(off); return off;
    },
    emit(channel, data) {
      if (isDisposed() || record.stale) return;
      if (channel === "subagents:settings_loaded") {
        if (!inFactory) { record.settings = undefined; invalidate("Tintin settings reloaded"); return; }
        record.settings = structuredClone(data?.settings);
      }
      if (channel === "subagents:settings_changed") {
        record.settings = undefined; invalidate("Tintin effective settings changed");
      }
      if (inFactory) queued.push([channel, data]); else pi.events.emit(channel, data);
    },
  };
  const oldCwd = process.cwd();
  let returned;
  try {
    // No event-loop yield while the synchronous pinned factory sees the owned sidecar.
    if (component.name === "tintin") process.chdir(overlay);
    returned = component.factory(api);
  } catch (error) {
    record.dispose(); throw error;
  } finally { process.chdir(oldCwd); inFactory = false; }
  if (returned?.then) {
    record.dispose();
    throw new Error("Cannot safely overlay an asynchronous native factory");
  }
  if (component.name === "tintin") record.registry = globalThis[Symbol.for("pi-subagents:manager")];
  for (const [channel, data] of queued) pi.events.emit(channel, data);
  return record;
}
