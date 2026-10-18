// OpenCode 2 boundary. Shared scripts own bank resolution and portable behavior.
import { open, stat } from 'node:fs/promises';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRunner } from './opencode_process.mjs';
import { createToolHooks } from './opencode_hooks.mjs';
import { createSessionMemory } from './opencode_session.mjs';
import { createWorkflowBinding } from './opencode_workflow.mjs';

const skillDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const binding = 'OpenCode 2 host binding (authoritative over older examples): '
  + 'dispatch with subagent({agent, description, prompt, model?: "provider/model#variant", sessionID?, background?}); '
  + 'omit model to use the role pin, or inherit the parent when unpinned. /mb work --model inherit and --step-model role=inherit override pins for this run only. Never use task(subagent_type) or launch another host CLI. '
  + 'Use native commands, skills and named roles; shared scripts implement /mb workflows. '
  + 'There is no blocking Stop hook; use explicit workflow/tool/commit gates. '
  + 'GraphRAG CLI: scripts/mb-graph.sh, scripts/mb-code-context.py (no native wrappers).';

async function read(file, cap = 32768) {
  let handle;
  try {
    handle = await open(file, 'r');
    const buffer = Buffer.alloc(cap);
    const { bytesRead } = await handle.read(buffer, 0, cap, 0);
    return buffer.subarray(0, bytesRead).toString('utf8');
  } catch { return ''; }
  finally { await handle?.close().catch(() => {}); }
}

/** @returns {import('@opencode/plugin').Plugin.Plugin} */
export function createMemoryBankPlugin({ extended = false } = {}) {
  return {
    id: 'memory-bank',
    async setup(ctx) {
      const directory = path.resolve(ctx.location.directory);
      const controller = new AbortController();
      const runner = createRunner(skillDir, directory, controller.signal);
      const registrations = [];
      const notified = new Set();
      const invoke = (action, sid, input = '') => runner.optional('adapters/opencode_session.sh', [action, directory, sid], input);
      const session = async (sid) => {
        try {
          const info = await ctx.session.get({ sessionID: sid }, { signal: AbortSignal.any([controller.signal, AbortSignal.timeout(3000)]) });
          if (path.resolve(info.location.directory) !== directory) return null;
          if (info.projectID !== ctx.location.project.id) return null;
          if (('workspaceID' in info.location ? info.location.workspaceID : undefined) !== ctx.location.workspaceID) return null;
          return info;
        } catch { return null; }
      };
      const resolveBank = sid => invoke('resolve', sid);
      const memory = createSessionMemory({ ctx, directory, runner, locate: session, resolveBank, signal: controller.signal });
      const tools = createToolHooks({ root: skillDir, directory, runner, locate: session, resolveBank });
      const workflow = createWorkflowBinding({ ctx, root: skillDir, directory, runner, locate: session, resolveBank, signal: controller.signal });
      const hook = async (domain, name, callback) => {
        registrations.push(await ctx[domain].hook(name, callback));
      };
      try {
        const commands = await workflow.install();
        if (commands) registrations.push(commands);
        if (ctx.shell) await hook('shell', 'create.before', event => workflow.shell(event));
        await hook('session', 'context', async (event) => {
          if (!await session(event.sessionID)) return;
           await workflow.context(event);
          const config = path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'opencode');
          event.system.push({ type: 'text', text: `${binding}\nSkill root: ${skillDir}` });
          for (const root of [config, directory]) {
            const text = await read(path.join(root, 'AGENTS.md'));
            const keys = text.match(/<!-- mb-key-rules:start -->[\s\S]*?<!-- mb-key-rules:end -->/g) ?? [];
            for (const key of keys) {
              if (!event.system.some(p => p.text?.includes(key))) event.system.push({ type: 'text', text: key });
            }
          }
          const bank = await invoke('resolve', event.sessionID);
          const ruleFiles = [path.join(config, 'RULES.md'), path.join(directory, 'RULES.md')];
          if (bank) ruleFiles.push(path.join(bank, 'RULES.md'));
          event.system.push({ type: 'text', text: `Read applicable detailed sections before changes: ${path.join(skillDir, 'rules/RULES.md')}. AGENTS.md and its Key rules remain the instruction source.` });
          for (const file of new Set(ruleFiles)) {
            try {
              if ((await stat(file)).isFile()) event.system.push({ type: 'text', text: `Applicable detailed rules (read relevant sections before changes): ${file}` });
            } catch { /* Optional detailed-rule pointers fail open. */ }
          }
          if (extended) await memory.context(event);
          const note = tools.takeNote(event.sessionID);
          if (note) {
            let text = note;
            try { const data = JSON.parse(note); text = data.hookSpecificOutput?.additionalContext || ''; } catch { /* Plain diagnostic. */ }
            text = await runner.optional('adapters/opencode_memory.py', ['filter'], text);
            if (text) event.system.push({ type: 'text', text });
          }
          if (!notified.has(event.sessionID)) {
            notified.add(event.sessionID);
            const notice = await runner.optional('hooks/mb-update-notify.sh');
            if (notice) event.system.push({ type: 'text', text: notice });
            if (bank) {
              const hint = await runner.optional('adapters/opencode_session.sh', ['hint', directory, event.sessionID], '', { env: { MB_AUTO_REFRESH: 'off' } });
              if (hint) event.system.push({ type: 'text', text: hint });
            }
            if (!extended) event.system.push({ type: 'text', text: '[memory-bank-skill] OpenCode parity extensions not installed — run: install.sh --clients opencode --with-extensions=opencode' });
          }
        });
        await hook('session', 'prompt', async (event) => {
          if (extended) await memory.prompt(event);
        });
        await hook('tool', 'execute.before', async (event) => {
          const command = String(event.input?.command ?? '');
          if ([/rm\s+-rf\s+\//, /rm\s+-rf\s+~/, /:\(\)\s*\{\s*:\|:&\s*\};:/].some(re => re.test(command))) {
            throw new Error('[MB-opencode] BLOCKED dangerous command');
          }
          if (extended) await tools.before(event);
          await workflow.before(event);
        });
        await hook('tool', 'execute.after', async event => {
          if (extended) await tools.after(event);
          await workflow.after(event);
        });
        await hook('session', 'compaction', async (event) => {
          if (extended) { await memory.compaction(event); return; }
          const info = await session(event.sessionID);
          if (!info || info.parentID) return;
          const checkpoint = await invoke('compact', event.sessionID);
          if (checkpoint) event.system.push({ type: 'text', text: checkpoint });
        });
      } catch (error) {
        controller.abort();
        await runner.dispose();
        await memory.dispose();
        await Promise.allSettled(registrations.map(r => r.dispose()));
        throw error;
      }
      const events = (async () => {
        try {
          for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
            if (event.type !== 'command.updated' && event.type !== 'session.execution.succeeded' && event.type !== 'session.idle' && event.type !== 'session.status' && event.type !== 'session.deleted') continue;
            if (event.location && path.resolve(event.location.directory) !== directory) continue;
            const locationlessSuccess = event.type === 'session.execution.succeeded' && !event.location;
            if (!locationlessSuccess && event.location?.workspaceID !== ctx.location.workspaceID) continue;
            if (event.type === 'command.updated') { await workflow.refreshCommands(); continue; }
            const sid = 'sessionID' in event.data ? event.data.sessionID : undefined;
            if (!sid) continue;
            const idle = event.type === 'session.execution.succeeded' || event.type === 'session.idle' || (event.type === 'session.status' && event.data.status.type === 'idle');
            if (!idle && event.type !== 'session.deleted') continue;
            if (event.type === 'session.deleted') { notified.delete(sid); workflow.clear(sid); continue; }
            const info = await session(sid);
            if (info && !info.parentID) {
              const changed = extended ? await memory.idle(sid) : false;
              const current = await session(sid);
              if (!current || current.parentID) continue;
              await invoke('idle', sid);
              // The legacy default starts Claude CLI; only an explicit backend may run here.
              if (process.env.MB_SUMMARIZE_BIN && (!extended || changed) && await invoke('resolve', sid)) {
                await runner.optional(process.env.MB_SUMMARIZE_BIN, [], { cwd: directory, session_id: sid }, { trustedCustom: true });
              }
            }
            notified.delete(sid);
          }
        } catch { /* Optional live-only observations must not break ordinary work. */ }
      })();
      return async () => {
        controller.abort();
        await runner.dispose();
        await memory.dispose();
        await Promise.allSettled(registrations.map(r => r.dispose()));
        await events;
        notified.clear();
      };
    },
  };
}
