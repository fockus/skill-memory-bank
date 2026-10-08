// Public pi-subagents RPC only. No subprocess/inline execution of roles.
import { randomUUID } from 'node:crypto';

export function rpc(events, method, params = {}, { timeoutMs = 5000, signal } = {}) {
  return new Promise((resolve, reject) => {
    const requestId = randomUUID();
    let timer;
    const finish = (error, value) => {
      clearTimeout(timer); off(); signal?.removeEventListener('abort', abort);
      error ? reject(error) : resolve(value);
    };
    const abort = () => finish(new Error(`RPC ${method} cancelled`));
    const off = events.on(`subagents:rpc:v1:reply:${requestId}`, reply => {
      if (reply?.version !== 1 || reply.requestId !== requestId) return;
      if (!reply.success) finish(new Error(`RPC ${method}: ${reply.error?.code}: ${reply.error?.message}`));
      else finish(null, reply.data);
    });
    timer = setTimeout(() => finish(new Error(`RPC ${method} unavailable or timed out`)), timeoutMs);
    signal?.addEventListener('abort', abort, { once: true });
    if (signal?.aborted) return abort();
    events.emit('subagents:rpc:v1:request', { version: 1, requestId, method, params });
  });
}

export async function preflightRole(resolveLaunch, ctx, role, task, output, runId, authorization) {
  if (!role?.agent) throw new Error('Missing configured agent');
  if (!ctx.model?.provider || !ctx.model?.id) throw new Error('Missing parent model/provider');
  const external = role.agent === 'codex-cli';
  const aliases = new Set(['opus', 'sonnet', 'haiku', 'inherit']);
  let model = external || aliases.has(role.model) ? undefined : role.model;
  const availableModels = ctx.modelRegistry.getAvailable();
  if (model) {
    if (!model.includes('/')) throw new Error(`Unresolved model alias: ${model}`);
    if (!availableModels.some(m => `${m.provider}/${m.id}` === model)) throw new Error(`Unavailable model: ${model}`);
    if (model.split('/')[0] !== ctx.model.provider &&
        !(authorization?.runId === runId && authorization.provider === model.split('/')[0])) {
      throw new Error(`Cross-provider model requires run-specific owner authorization: ${model}`);
    }
  }
  const result = await resolveLaunch({ agent: role.agent, task, output, cwd: ctx.cwd,
    context: 'fresh', parentModel: ctx.model, availableModels,
    scopedModelIds: ctx.scopedModels?.map(row => `${row.model.provider}/${row.model.id}`),
    sessionRoot: ctx.cwd, runtimeSnapshotHost: ctx.pi, ...(model ? { model } : {}),
  });
  if (!result.ok) throw new Error(`Preflight ${role.agent}: ${result.message}`);
  const resolvedModel = result.contract.model?.replace(/:(off|minimal|low|medium|high|xhigh|max)$/, '');
  if (!external && resolvedModel !== (model || `${ctx.model.provider}/${ctx.model.id}`)) {
    throw new Error(`Preflight resolved conflicting model for ${role.agent}: ${result.contract.model}`);
  }
  return { agent: role.agent, task, output, context: 'fresh', ...(model ? { model } : {}) };
}

export async function dispatchNative(events, options, { signal, timeoutMs = 1800000, onLaunch } = {}) {
  const ping = await rpc(events, 'ping', {}, { signal });
  const event = ping.events?.asyncComplete || ping.capabilities?.events?.asyncComplete;
  if (typeof event !== 'string') throw new Error('RPC lacks async completion capability');
  let id, terminal, resolveTerminal, rejectTerminal;
  const early = new Map();
  const waiting = new Promise((resolve, reject) => { resolveTerminal = resolve; rejectTerminal = reject; });
  // Observe before spawn; immediate terminal events may precede the reply.
  const off = events.on(event, payload => {
    if (!payload?.runId) return;
    if (!id) { if (early.size < 64) early.set(payload.runId, payload); return; }
    if (payload.runId === id) { terminal = payload; resolveTerminal(payload); }
  });
  const abort = () => rejectTerminal(new Error('RPC child cancelled'));
  let timer;
  try {
    if (signal?.aborted) throw new Error('RPC child cancelled before spawn');
    // Keep the bounded spawn handshake alive after cancellation so its identity
    // can be persisted and stopped; aborting this reply wait would orphan a child.
    const data = await rpc(events, 'spawn', { script: `return await runs.run(${JSON.stringify(options.key)}, ${JSON.stringify(options.child)});`,
      cwd: options.cwd, context: 'fresh', timeoutMs });
    id = data?.details?.asyncId || data?.details?.runId;
    if (!id) throw new Error('RPC spawn omitted durable run identity');
    await onLaunch?.({ runId: id, response: data });
    signal?.addEventListener('abort', abort, { once: true });
    timer = setTimeout(() => rejectTerminal(new Error('RPC child timed out')), timeoutMs);
    if (signal?.aborted) abort();
    if (early.has(id)) resolveTerminal(early.get(id));
    terminal = await waiting;
    if (terminal.exitCode !== 0 || terminal.error || terminal.success !== true || terminal.state !== 'complete' || !Array.isArray(terminal.results) || terminal.results.some(r => r.success !== true || r.error || r.outputPartial || r.outputSaveError)) {
      throw new Error(`RPC child failed: ${terminal.error || terminal.state || terminal.exitCode}`);
    }
    return terminal;
  } catch (error) {
    if (id && !terminal) {
      try { await rpc(events, 'stop', { id }); } catch (stopError) {
        throw new Error(`${error.message}; stop unconfirmed for ${id}: ${stopError.message}`);
      }
    }
    throw error;
  } finally {
    off(); clearTimeout(timer); signal?.removeEventListener('abort', abort);
  }
}
