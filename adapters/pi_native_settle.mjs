// Pi settle-resume gate: at agent_before_settle (the last point before Pi goes idle) an unfinished
// `/mb drive` or `/mb work` run gets a hidden custom message and `continue: true`, so a text-only
// turn does not end the run. The drive decision is the read-only hooks/mb-drive-resume-gate.sh,
// called as a subprocess (not re-implemented). Fail open: any problem settles normally.
// Capped per settle cycle (the counter resets when Pi really settles); error/aborted never resume.
import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { execute, findBank } from './pi_native_commands.mjs';

const MAX_RESUMES = 3;
const GATE_TIMEOUT_MS = 15000;
const WORK_FRESH_MS = 6 * 3600 * 1000;

async function driveReason(skillDir, ctx, cwd) {
  let sessionId = '';
  try { sessionId = String(ctx.sessionManager?.getSessionId?.() || ''); } catch {}
  const out = await execute('bash', [join(skillDir, 'hooks', 'mb-drive-resume-gate.sh')], cwd, {
    signal: ctx.signal, timeoutMs: GATE_TIMEOUT_MS, stdin: JSON.stringify({ cwd, session_id: sessionId }),
  });
  const verdict = JSON.parse(out.trim() || '{}');
  return verdict.decision === 'block' && typeof verdict.reason === 'string' ? verdict.reason : null;
}

// Run files present now; a /mb work run counts only when it appeared after session_start.
async function runFiles(bank) {
  return new Set((await readdir(join(bank, '.work-state')).catch(() => [])).filter(n => n.endsWith('.json')));
}

// Newest recently-updated `/mb work` run of this session whose phase is not done.
async function workReason(bank, before) {
  const dir = join(bank, '.work-state');
  let newest = null;
  for (const name of await readdir(dir).catch(() => [])) {
    if (!name.endsWith('.json') || before.has(name)) continue;
    try {
      const run = JSON.parse(await readFile(join(dir, name), 'utf8'));
      const age = Date.now() - Date.parse(run.updated);
      if (run.run_id && run.phase && run.phase !== 'done' && age >= 0 && age < WORK_FRESH_MS
        && (!newest || Date.parse(run.updated) > Date.parse(newest.updated))) newest = run;
    } catch {}
  }
  if (!newest) return null;
  return `Work resume gate: /mb work run ${newest.run_id} (${newest.source}, item ${newest.item_no}) is in phase ${newest.phase}, not done. ` +
    `Continue its remaining steps (${(newest.steps || []).join(' → ')}) with \`/mb work ${newest.source} --range ${newest.item_no}\` until a gate or a real blocker; ` +
    'do not end the turn with a status update.';
}

export function registerSettleGate(pi, { skillDir, projectRoot = '' }) {
  let resumes = 0;
  const preexisting = new Map(); // bank -> run files that predate this session (owned by others)
  pi.on('session_start', async (_event, ctx) => {
    try {
      const bank = await findBank(skillDir, projectRoot || ctx.cwd, { timeoutMs: GATE_TIMEOUT_MS });
      if (bank) preexisting.set(bank, await runFiles(bank));
    } catch {}
  });
  pi.on('agent_settled', () => { resumes = 0; });
  pi.on('agent_before_settle', async (event, ctx) => {
    try {
      if (event?.outcome !== undefined && event.outcome !== 'completed') return;
      if (resumes >= MAX_RESUMES) return;
      const cwd = projectRoot || ctx.cwd;
      const reason = await driveReason(skillDir, ctx, cwd) || await (async () => {
        const bank = await findBank(skillDir, cwd, { timeoutMs: GATE_TIMEOUT_MS, signal: ctx.signal });
        const before = bank && preexisting.get(bank);
        return before ? workReason(bank, before) : null;
      })();
      if (!reason) return;
      resumes += 1;
      return {
        entries: [...(event.entries || []), { type: 'custom_message', customType: 'mb-settle-resume', content: reason, display: false }],
        continue: true,
      };
    } catch {
      return;
    }
  });
}
