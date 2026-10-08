// Pi guard hooks over the portable MB guard scripts; the policy lives in those scripts.
// tool_call: write/edit go through mb-protected-paths-guard.sh, bash through block-dangerous.sh
// and the protected guard. Exit 0 allows; anything else (exit 2, crash, timeout, cancellation,
// malformed input) blocks before the tool body runs. tool_result: a successful write/edit of a
// plan or spec inside the current bank runs the same sync scripts as the Codex adapter.
// Hooks spawn scripts, never Pi tools, so they cannot re-enter themselves. Not an OS sandbox.
import { realpath } from 'node:fs/promises';
import { homedir } from 'node:os';
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { execute, findBank } from './pi_native_commands.mjs';

const GUARD_TIMEOUT_MS = 15000;
const SYNC_TIMEOUT_MS = 60000;
const DIAGNOSTIC_LIMIT = 1500;

const bounded = text => {
  const value = String(text).trim();
  return value.length > DIAGNOSTIC_LIMIT ? `…${value.slice(-DIAGNOSTIC_LIMIT)}` : value;
};

// Pi's own tool path rules: strip a leading '@', expand '~', resolve against ctx.cwd.
function toolPath(raw, cwd) {
  const path = raw.replace(/^@/, '');
  return resolve(cwd, path === '~' || path.startsWith('~/') ? join(homedir(), path.slice(1)) : path);
}

// realpath of the deepest existing ancestor: `..` or a symlinked directory cannot hide a target.
async function canonical(path) {
  const tail = [];
  for (let head = path; ; head = dirname(head)) {
    try {
      return join(await realpath(head), ...tail);
    } catch {
      if (dirname(head) === head) return path;
      tail.unshift(basename(head));
    }
  }
}

function inside(root, path) {
  const rel = relative(root, path);
  return rel && rel !== '..' && !rel.startsWith(`..${sep}`) && !isAbsolute(rel) ? rel : null;
}

export function registerGuardHooks(pi, { skillDir, projectRoot = '', timeoutMs = GUARD_TIMEOUT_MS }) {
  async function locate(ctx) {
    const cwd = projectRoot || ctx.cwd;
    const bank = await findBank(skillDir, cwd, { timeoutMs, signal: ctx.signal });
    // A global bank does not sit inside its project: the project root is then the live cwd.
    const root = await canonical(bank && basename(bank) === '.memory-bank' ? dirname(bank) : cwd);
    return { bank: bank && await canonical(bank), root };
  }

  // Resolves to a block reason, or null when the guard allowed the call.
  async function guard(script, payload, loc, cwd, signal) {
    try {
      await execute('bash', [join(skillDir, 'hooks', script)], cwd, {
        signal, timeoutMs, stdin: JSON.stringify({ hook_event_name: 'PreToolUse', ...payload }),
        env: { MB_PROTECTED_MODE: 'deny', ...(loc.bank ? { MB_PATH: loc.bank } : {}) },
      });
      return null;
    } catch (error) {
      return `Memory Bank ${script} refused this call: ${bounded(error.message)}`;
    }
  }

  async function check(event, ctx) {
    const input = event.input && typeof event.input === 'object' ? event.input : {};
    if (event.toolName === 'bash') {
      if (typeof input.command !== 'string') return 'Memory Bank guard: malformed bash input (command is not a string)';
      const loc = await locate(ctx);
      const payload = { tool_name: 'Bash', tool_input: { command: input.command }, cwd: ctx.cwd };
      return await guard('block-dangerous.sh', payload, loc, ctx.cwd, ctx.signal)
        || await guard('mb-protected-paths-guard.sh', payload, loc, ctx.cwd, ctx.signal);
    }
    if (typeof input.path !== 'string' || !input.path.trim()) {
      return `Memory Bank guard: malformed ${event.toolName} input (path is missing or not a string)`;
    }
    const loc = await locate(ctx);
    const target = await canonical(toolPath(input.path, ctx.cwd));
    // Project-relative, so path globs match even without a git checkout to anchor them.
    const file = inside(loc.root, target) || target;
    return guard('mb-protected-paths-guard.sh',
      { tool_name: event.toolName === 'write' ? 'Write' : 'Edit', tool_input: { file_path: file }, cwd: loc.root },
      loc, loc.root, ctx.signal);
  }

  pi.on('tool_call', async (event, ctx) => {
    if (!['write', 'edit', 'bash'].includes(event.toolName)) return undefined;
    try {
      const reason = await check(event, ctx);
      return reason ? { block: true, reason } : undefined;
    } catch (error) {
      return { block: true, reason: `Memory Bank guard could not run: ${bounded(error.message)}` };
    }
  });

  // Post-write sync is best-effort: the write already happened, so failures become a bounded note.
  pi.on('tool_result', async (event, ctx) => {
    if (event.isError || !['write', 'edit'].includes(event.toolName)) return undefined;
    if (typeof event.input?.path !== 'string' || !event.input.path.endsWith('.md')) return undefined;
    const notes = [];
    try {
      const { bank, root } = await locate(ctx);
      if (!bank) return undefined;
      const rel = inside(bank, await canonical(toolPath(event.input.path, ctx.cwd)));
      if (!rel) return undefined;
      const parts = rel.split(sep);
      const steps = parts.length === 2 && parts[0] === 'plans' ? [['mb-plan-sync.sh', [join(bank, rel), bank]]]
        : parts[0] === 'specs' ? [['mb-roadmap-sync.sh', [bank]], ['mb-traceability-gen.sh', [bank]]]
        : [];
      for (const [script, args] of steps) {
        await execute('bash', [join(skillDir, 'scripts', script), ...args], root,
          { env: { MB_PATH: bank }, timeoutMs: SYNC_TIMEOUT_MS, signal: ctx.signal })
          .catch(error => notes.push(`[Memory Bank] plan-sync failed: ${script}: ${bounded(error.message)}`));
      }
    } catch (error) {
      notes.push(`[Memory Bank] plan-sync failed: ${bounded(error.message)}`);
    }
    if (!notes.length) return undefined;
    return { content: [...event.content, { type: 'text', text: notes.join('\n') }],
      ...(event.structuredContent === undefined ? {} : { structuredContent: event.structuredContent }) };
  });
}
