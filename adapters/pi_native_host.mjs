// Host authority is process-local capability data, never model/tool JSON.
import { randomUUID } from "node:crypto";

const owners = new WeakMap();
const prerequisite = "Memory Bank dispatch requires a ready native extension or mb-pi runtime";

export function requireHostBinding(pi, ctx) {
  const owner = owners.get(pi);
  if (!owner) throw new Error(prerequisite);
  return owner.read(pi, ctx);
}

export function requireHostService(pi, ctx, name) {
  const owner = owners.get(pi);
  if (!owner) throw new Error(prerequisite);
  owner.read(pi, ctx);
  const service = owner.service(name);
  if (!service) throw new Error(`Selected ${name} backend is unavailable in the owned runtime`);
  return service;
}

export const hasHostAuthority = pi => owners.has(pi);

// Four-method authority contract. Only the trusted SDK/extension root holds the producer.
export function createHostAuthority(getSession, getScope = () => ({})) {
  let activeApi, binding, boundSession, services = {}, reason = "startup not ready";
  const read = (pi, ctx) => {
    const session = getSession();
    if (!binding || pi !== activeApi || !session || session !== boundSession ||
        ctx?.sessionManager?.getSessionId() !== binding.sessionId ||
        session.sessionManager.getSessionId() !== binding.sessionId ||
        binding.cwd && ctx?.cwd !== binding.cwd) {
      throw new Error(`${prerequisite}: ${reason || "stale session/runtime binding"}`);
    }
    return binding;
  };
  return {
    attach(pi) {
      activeApi = pi;
      owners.set(pi, { read, service: name => services[name] });
    },
    publish(components, loadedExtensions) {
      const session = getSession();
      if (!session) throw new Error("Cannot bind a missing live SDK session");
      const inventory = {};
      for (const component of components) {
        const count = loadedExtensions.filter(ext => ext.path === component.runtimePath).length;
        if (count !== 1 || inventory[component.name]) throw new Error(`Duplicate/missing ${component.name} service`);
        if (component.name === "tintin" && component.settings?.agentMentions !== "off") {
          throw new Error("Tintin factory did not honor runtime-local agentMentions=false overlay");
        }
        inventory[component.name] = Object.freeze({
          source: component.source, version: component.version,
          runtimePath: component.runtimePath,
          ...(component.name === "tintin" ? { agentMentions: component.settings.agentMentions } : {}),
        });
      }
      if (!inventory.mb) throw new Error("Missing managed MB factory");
      services = Object.fromEntries(components.map(component => [component.name, component]));
      boundSession = session;
      binding = Object.freeze({ ...getScope(), sessionId: session.sessionManager.getSessionId(),
        generation: randomUUID(), components: Object.freeze(inventory),
        inventory: Object.freeze(loadedExtensions.map(ext => ext.path)) });
      reason = "";
      return binding;
    },
    invalidate(message) { binding = undefined; boundSession = undefined; services = {}; reason = message; },
    inspect() { return binding; },
  };
}
