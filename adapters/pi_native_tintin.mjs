// Thin public Tintin RPC bridge. No executor, singleton dispatch or tool fallback.
import { randomUUID } from "node:crypto";
import { writeFile } from "node:fs/promises";

export function tintinRpc(events, method, payload = {}, { timeoutMs = 5000, signal } = {}) {
  return new Promise((resolve, reject) => {
    const requestId = randomUUID();
    let timer;
    const finish = (error, value) => { clearTimeout(timer); off(); signal?.removeEventListener("abort", abort); error ? reject(error) : resolve(value); };
    const abort = () => finish(new Error(`Tintin ${method} cancelled`));
    const off = events.on(`subagents:rpc:${method}:reply:${requestId}`, reply => {
      if (reply?.success === false) finish(new Error(`Tintin ${method}: ${reply.error}`));
      else if (reply?.success === true) finish(null, reply.data);
    });
    timer = setTimeout(() => finish(new Error(`Selected Tintin ${method} unavailable or timed out`)), timeoutMs);
    signal?.addEventListener("abort", abort, { once: true });
    if (signal?.aborted) return abort();
    events.emit(`subagents:rpc:${method}`, { requestId, ...payload });
  });
}

export async function dispatchTintin(events, service, child, { signal, timeoutMs = 1800000, onLaunch, guard } = {}) {
  let id, settled, resolveTerminal, rejectTerminal, consumption;
  const early = new Map();
  const terminal = new Promise((resolve, reject) => { resolveTerminal = resolve; rejectTerminal = reject; });
  const accept = data => {
    if (data?.id !== id) return;
    try {
      guard();
      // Dispatch identity comes from our spawn, provenance from our bound factory.
      const record = service.registry?.getRecord(id);
      if (!record || record.type !== child.contract.runtimeAgent || record.parentAgentId || record.workflowId) throw new Error("Tintin wrong-owner terminal record");
      settled = data;
      // Emit consume synchronously before the factory schedules a follow-up turn.
      consumption = tintinRpc(events, "consume", { agentId: id });
      consumption.catch(() => {});
      resolveTerminal(data);
    } catch (error) { rejectTerminal(error); }
  };
  const listen = data => {
    if (!data?.id) return;
    if (!id) { if (early.size < 64) early.set(data.id, data); return; }
    accept(data);
  };
  const subscriptions = [events.on("subagents:completed", listen), events.on("subagents:failed", listen)];
  let timer;
  const abort = () => rejectTerminal(new Error("Tintin owned child cancelled"));
  try {
    guard();
    if (signal?.aborted) throw new Error("Tintin cancelled before spawn");
    const response = await tintinRpc(events, "spawn", { type: child.contract.runtimeAgent, prompt: child.task,
      options: { description: child.key, model: child.contract.model, cwd: child.cwd, inheritContext: false,
        isBackground: true, signal, onSpawned: childId => { id = childId; if (early.has(id)) accept(early.get(id)); } } });
    if (!response?.id || id && response.id !== id) throw new Error("Tintin spawn omitted/conflicted native child identity");
    id = response.id;
    await onLaunch?.({ runId: id, response });
    signal?.addEventListener("abort", abort, { once: true });
    timer = setTimeout(() => rejectTerminal(new Error("Tintin child timed out")), timeoutMs);
    if (signal?.aborted) abort();
    if (early.has(id) && !settled) accept(early.get(id));
    const result = await terminal;
    await consumption;
    const record = service.registry.getRecord(id);
    const actualModel = record.session?.model;
    const actualTools = record.session?.getActiveToolNames?.();
    if (result.status !== "completed" || result.error || typeof result.result !== "string") throw new Error(`Tintin child failed: ${result.status}`);
    if (`${actualModel?.provider}/${actualModel?.id}` !== child.contract.model) throw new Error("Tintin effective provider/model drift");
    if (!Array.isArray(actualTools) || JSON.stringify([...actualTools].sort()) !== JSON.stringify([...child.contract.tools].sort())) throw new Error("Tintin effective child tool scope drift");
    guard();
    await writeFile(child.output, result.result, { mode: 0o600 });
    return { runId: id, state: "complete", success: true, exitCode: 0, backend: "tintin", results: [{ success: true, agent: child.contract.runtimeAgent, model: child.contract.model, usage: result.usage }] };
  } catch (error) {
    if (id && !settled) {
      try { await tintinRpc(events, "stop", { agentId: id }); }
      catch (stopError) { throw new Error(`${error.message}; owned stop unconfirmed ${id}: ${stopError.message}`); }
    }
    throw error;
  } finally { subscriptions.forEach(off => off()); clearTimeout(timer); signal?.removeEventListener("abort", abort); }
}
