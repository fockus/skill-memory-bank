// Common backend contract: preflight(role,...), dispatch(key,child,...), guard().
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { requireHostBinding, requireHostService } from "./pi_native_host.mjs";
import { rpc, preflightRole, dispatchNative } from "./pi_native_subagents.mjs";
import { tintinRpc, dispatchTintin } from "./pi_native_tintin.mjs";
import { roleModel, composeLeaf, discoverTintinRole, nativeDelegationTools } from "./pi_native_roles.mjs";

// Nico 0.76 exposes no public child-session inventory; only launch intent and digest are checked.
export const nicoRuntimeInventory = Object.freeze({ status: "UNVERIFIED",
  reason: "Nico exposes no public child-session tool/resource inventory; launch contract digest and model were checked" });

export async function selectBackend(flag, bank) {
  let configured;
  try { configured = (await readFile(join(bank, ".mb-config"), "utf8")).match(/^\s*pi_subagent_backend\s*=\s*["']?([a-z]+)["']?\s*$/m)?.[1]; }
  catch (error) { if (error.code !== "ENOENT") throw error; }
  const name = flag || configured || "tintin";
  if (!["nico", "tintin"].includes(name)) throw new Error(`Unknown selected native backend: ${name}`);
  return name;
}

export async function createBackend({ name, pi, ctx, decoder, runId, resolveLaunch = undefined, authorization = undefined }) {
  const binding = requireHostBinding(pi, ctx);
  const service = requireHostService(pi, ctx, name);
  const guard = () => {
    const current = requireHostBinding(pi, ctx);
    if (current.generation !== binding.generation) throw new Error("Native session/runtime generation changed");
    if (current.components.tintin && current.components.tintin.agentMentions !== "off") throw new Error("Unsafe Tintin automatic mentions");
    return current;
  };
  guard();
  if (name === "nico") {
    const ping = await rpc(pi.events, "ping");
    if (typeof (ping.events?.asyncComplete || ping.capabilities?.events?.asyncComplete) !== "string") throw new Error("Selected Nico lacks mandatory completion capability");
    resolveLaunch = service.resolveLaunch || resolveLaunch;
    if (typeof resolveLaunch !== "function") throw new Error("Selected Nico public preflight unavailable");
    if (typeof service.registerCapabilityCeiling !== "function") throw new Error("Selected Nico public capability ceiling unavailable; refusing launch");
  } else {
    if ((await tintinRpc(pi.events, "ping"))?.version !== 2) throw new Error("Selected Tintin public protocol v2 unavailable");
    if (typeof service.registry?.getRecord !== "function") throw new Error("Selected Tintin bound public record capability unavailable");
  }
  return {
    name, binding,
    runtimeInventory: name === "nico" ? nicoRuntimeInventory : undefined,
    guard,
    async preflight(role, task, output) {
      guard();
      if (name === "tintin" && role?.agent === "codex-cli") throw new Error("Tintin cannot execute configured external runner codex-cli");
      if (name === "nico" && role.agent === "codex-cli") {
        const launch = await preflightRole(resolveLaunch, ctx, role, task, output, runId, authorization);
        return { launch, task, output, contract: { agent: role.agent, runtimeAgent: role.agent, external: true, externalModel: role.model, externalThinking: role.thinking, tools: [] } };
      }
      const model = roleModel(ctx, role, runId, authorization);
      let parsed, source, tools;
      if (name === "nico") {
        const original = await resolveLaunch({ agent: role.agent, task, output, cwd: ctx.cwd, context: "fresh",
          parentModel: ctx.model, availableModels: ctx.modelRegistry.getAvailable(), runtimeSnapshotHost: pi });
        if (!original.ok) throw new Error(`Preflight ${role.agent}: ${original.message}`);
        source = original.contract.agent.filePath;
        parsed = await decoder("agent", source, ctx.cwd);
        tools = original.contract.tools?.effectiveAllowlist;
      } else {
        parsed = await discoverTintinRole(role.agent, ctx.cwd, binding.agentDir, decoder);
        source = parsed.source;
      }
      const contract = await composeLeaf({ backend: name, role, model, runId, cwd: ctx.cwd, source, parsed, tools });
      let launch;
      if (name === "nico") {
        let resolved;
        launch = await preflightRole(async params => { resolved = await resolveLaunch(params); return resolved; }, ctx,
          { ...role, agent: contract.runtimeAgent }, task, output, runId, authorization);
        if (!resolved.contract.tools || resolved.contract.tools.fanoutAuthorized ||
            resolved.contract.tools.effectiveAllowlist.some(tool => nativeDelegationTools.has(tool))) throw new Error("Nico leaf exposes unapproved delegation tools");
        if (contract.tools.some(tool => !resolved.contract.tools.effectiveAllowlist.includes(tool))) throw new Error("Nico leaf dropped required tools");
        contract.launchContractDigest = resolved.contract.launchContractDigest;
        if (!contract.launchContractDigest) throw new Error("Nico launch contract digest unavailable");
      }
      return { launch, task, output, cwd: ctx.cwd, contract };
    },
    async dispatch(key, child, options) {
      guard();
      if (name === "tintin") return dispatchTintin(pi.events, service, { ...child, key }, { ...options, guard });
      let ceiling;
      try {
        ceiling = service.registerCapabilityCeiling({ sessionId: ctx.sessionManager.getSessionId(), source: "memory-bank-native",
          ceiling: { allowedTools: child.contract.tools, allowedAgents: [], denyExtensions: true } });
      } catch (error) { throw new Error(`Nico capability ceiling registration failed; refusing launch: ${error.message}`); }
      let terminal;
      try { terminal = await dispatchNative(pi.events, { key, child: child.launch, cwd: ctx.cwd }, options); }
      finally { ceiling.dispose(); }
      guard();
      if (!child.contract.external && terminal.results.some(result =>
        result.launchContractDigest !== child.contract.launchContractDigest ||
        result.model?.replace(/:(off|minimal|low|medium|high|xhigh|max)$/, "") !== child.contract.model)) throw new Error("Nico effective launch/tool/model contract drift");
      return { ...terminal, backend: name, runtimeInventory: nicoRuntimeInventory };
    },
  };
}
