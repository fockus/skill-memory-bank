// Pi session memory: v2 session capture, restore, compaction handoff and bounded finalization.
// Portable scripts own bank resolution, handoff, summarization and _recent.md; this module only
// maps Pi lifecycle events onto them.
import { mkdir, readFile, readdir, rename, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { execute, findBank } from './pi_native_commands.mjs';

export const RESTORE_TYPE = 'mb-session-restore';
export const HANDOFF_TYPE = 'mb-handoff-restore';
const RECENT_CAP = 4000;
const HANDOFF_CAP = 1500;

// ponytail: one process-wide write chain shared by every runtime (reloads included);
// per-bank chains if a slow summarizer ever stalls an unrelated project.
let chain = Promise.resolve();
const serial = job => {
  const next = chain.then(job);
  chain = next.catch(() => {});
  return next;
};

const off = name => process.env[name] === 'off';
const clock = () => new Date().toLocaleTimeString('en-GB', { hour12: false });
const pad = n => String(n).padStart(2, '0');
const readText = (file, cap) => readFile(file, 'utf8').then(t => t.slice(0, cap).trim(), () => '');

async function writeAtomic(file, text) {
  const tmp = `${file}.tmp.${process.pid}`;
  await writeFile(tmp, text, 'utf8');
  await rename(tmp, file);
}

function fmGet(text, key) {
  const head = text.startsWith('---\n') ? text.slice(4, text.indexOf('\n---', 4)) : '';
  return head.match(new RegExp(`^${key}: ?(.*)$`, 'm'))?.[1];
}

function fmSet(text, key, value) {
  const end = text.indexOf('\n---', 4);
  const head = text.slice(0, end), rest = text.slice(end);
  const line = `${key}: ${value}`;
  const re = new RegExp(`^${key}:.*$`, 'm');
  return (re.test(head) ? head.replace(re, line) : `${head}\n${line}`) + rest;
}

// Append a bullet to a section, before the next heading; a missing section is created at the
// end. Keeps every turn inside `## Live log` even once a summary exists (resume).
function appendTo(text, line, heading = '## Live log') {
  const start = text.indexOf(`\n${heading}\n`);
  if (start < 0) return `${text.trimEnd()}\n\n${heading}\n${line}\n`;
  const next = text.indexOf('\n## ', start + 1);
  if (next < 0) return `${text}${text.endsWith('\n') ? '' : '\n'}${line}\n`;
  return `${text.slice(0, next)}\n${line}${text.slice(next)}`;
}

function dropSummary(text) {
  return text.replace(/\n## Summary\n[\s\S]*?(?=\n## |$)/, '');
}

function deterministicSummary(text, note) {
  const live = text.slice(text.indexOf('## Live log')).split('\n## ')[0];
  const requests = [...live.matchAll(/User: "(.*)"$/gm)].map(m => m[1]);
  const files = [...new Set([...live.matchAll(/^ {2}- Files: (.*)$/gm)].flatMap(m => m[1].split(', ')))];
  const tools = (live.match(/^ {2}- Tools: /gm) || []).length;
  const errors = (live.match(/^ {2}- Outcome: error$/gm) || []).length;
  const turns = (live.match(/^- Turn \d+: completed$/gm) || []).length;
  return ['', '## Summary',
    `Mode: deterministic — built from the live log without an LLM${note ? `; ${note}` : ''}.`,
    '### What changed',
    ...(requests.length ? requests.slice(-10).map(r => `- Request: "${r}"`) : ['- (no user requests captured)']),
    `- Turns completed: ${turns}; tool calls: ${tools} (errors: ${errors})`,
    '### Decisions', '- (not inferred in deterministic mode)',
    '### Open questions', '- (not inferred in deterministic mode)',
    '### Files', ...(files.length ? files.map(f => `- ${f}`) : ['- (none)']), ''].join('\n');
}

export function createSessionMemory({ skillDir, projectRoot = '' }) {
  let current = null;
  const script = (args, cwd, options = {}) => execute('bash', args, cwd, options);
  const resolveBank = cwd => findBank(skillDir, cwd, { timeoutMs: 5000 });
  const redact = (text, cwd) => script(['-c', '. "$1"; sc_strip_private | sc_redact_secrets', 'mb-redact',
    join(skillDir, 'hooks/lib/session-common.sh')], cwd, { stdin: text, timeoutMs: 5000 }).then(t => t.trim(), () => '[redaction unavailable]');
  const edit = async (gen, change) => {
    if (!gen.file) return;
    try { await writeAtomic(gen.file, change(await readFile(gen.file, 'utf8'))); }
    catch (error) { gen.file = null; gen.captureError = String(error); }
  };
  // Every handler binds the live generation at call time; a replaced or closed one is a no-op.
  const bound = handler => (event, ctx) => {
    const gen = current;
    if (!gen) return undefined;
    return serial(() => (gen.closed ? undefined : handler(gen, event, ctx)));
  };

  async function findOrCreate(gen, ctx, bank) {
    const dir = join(bank, 'session');
    await mkdir(dir, { recursive: true });
    const sid8 = gen.id.slice(0, 8);
    for (const name of (await readdir(dir)).sort().reverse()) {
      if (!name.endsWith(`_${sid8}.md`)) continue;
      const text = await readFile(join(dir, name), 'utf8');
      if (fmGet(text, 'session_id') === gen.id) {
        gen.turns = Number(fmGet(text, 'turns')) || 0;
        return join(dir, name);
      }
    }
    const d = new Date();
    const file = join(dir, `${d.toISOString().slice(0, 10)}_${pad(d.getHours())}${pad(d.getMinutes())}_${sid8}.md`);
    const branch = await execute('git', ['-C', gen.cwd, 'rev-parse', '--abbrev-ref', 'HEAD'], gen.cwd, { timeoutMs: 2000 })
      .then(b => b.trim() || '-', () => '-');
    const header = ['---', `session_id: ${gen.id}`, `transcript: ${ctx.sessionManager?.getSessionFile?.() ?? ''}`,
      'agent: pi', `started: ${d.toISOString()}`, `branch: ${branch}`, 'turns: 0', 'last_turn:',
      'summarized: false', 'summary_schema: v2', '---', '', '## Live log', ''].join('\n');
    await writeFile(file, header, { encoding: 'utf8', flag: 'wx' });
    return file;
  }

  async function restoreText(bank) {
    const recent = await readText(join(bank, 'session/_recent.md'), RECENT_CAP);
    const handoff = await readText(join(bank, 'handoff/latest.md'), HANDOFF_CAP);
    if (!recent && !handoff) return null;
    return ['# Memory Bank restored context',
      `Prior-session memory from ${bank} (not a new user request).`,
      recent && `## Recent sessions\n${recent}`, handoff && `## Latest handoff capsule\n${handoff}`]
      .filter(Boolean).join('\n\n');
  }

  async function summarize(gen) {
    let note = '';
    try {
      // The summarizer applies the inherited backend policy; for Pi without explicit
      // MB_SUMMARY_BACKEND/MB_SUMMARIZE_BIN it exits without calling any CLI.
      const seconds = Number(process.env.MB_SESSION_LLM_TIMEOUT) || 30;
      await script([join(skillDir, 'hooks/mb-session-summarize.sh'), gen.file], gen.cwd, { timeoutMs: seconds * 1000 });
    } catch (error) {
      note = `LLM summarizer did not complete (${/timed out/.test(error.message) ? 'timed out' : 'failed'})`;
    }
    const text = await readFile(gen.file, 'utf8');
    if (fmGet(text, 'summarized') === 'true' && text.includes('\n## Summary\n')) {
      await edit(gen, t => fmSet(t, 'summary_mode', 'llm'));
    } else {
      // summarized stays false: no LLM summary exists; summary_mode discloses what was written.
      await edit(gen, t => fmSet(dropSummary(t), 'summary_mode', 'deterministic') + deterministicSummary(t, note));
    }
  }

  async function finalize(gen, reason) {
    gen.closed = true;
    if (current === gen) current = null;
    if (!gen.file || reason === 'reload') return;
    await edit(gen, t => fmSet(t, 'ended', new Date().toISOString()));
    if (gen.dirty && gen.file) {
      // New turns invalidate an earlier summary of this session (resume).
      await edit(gen, t => fmSet(dropSummary(t), 'summarized', 'false'));
      // Captured evidence stays on disk even if summarization cannot finish.
      await summarize(gen).catch(() => {});
    }
    await script([join(skillDir, 'scripts/mb-session-recent-rebuild.sh'), gen.bank], gen.cwd, { timeoutMs: 10000 }).catch(() => {});
    // I-132 spawn discipline: mark the index dirty; the next search catches up inline.
    try {
      const indexDir = process.env.MB_INDEX_DIR || join(gen.bank, '.index');
      await mkdir(indexDir, { recursive: true });
      await writeFile(join(indexDir, '.dirty'), '');
    } catch { /* optional marker: never breaks shutdown */ }
  }

  return {
    session_start(event, ctx) {
      const cwd = projectRoot || ctx.cwd;
      const sm = ctx.sessionManager;
      const sf = sm?.getSessionFile?.() ?? null;
      const id = sm?.getSessionId?.() || (sf ? sf.replace(/[^a-zA-Z0-9]/g, '-').slice(-36) : `pi-${Date.now().toString(36)}`);
      const gen = { id, cwd, turns: 0, files: new Set() };
      current = gen;
      return serial(async () => {
        if (gen.closed) return;
        gen.bank = await resolveBank(cwd).catch(() => null);
        if (!gen.bank || gen.closed) return;
        if (!off('MB_AUTOLOAD_CONTEXT')) gen.restore = await restoreText(gen.bank);
        if (off('MB_SESSION_CAPTURE')) return;
        gen.file = await findOrCreate(gen, ctx, gen.bank).catch(error => { gen.captureError = String(error); return null; });
      });
    },
    input: bound(async (gen, event) => {
      if (!gen.file || event.source === 'extension') return;
      const text = (await redact(event.text || '', gen.cwd)).slice(0, 200);
      gen.dirty = true;
      await edit(gen, t => appendTo(t, `- ${clock()} — User: "${text.replace(/\n/g, ' ')}"`));
    }),
    tool_execution_start: bound((gen, event) => {
      const path = event.args?.path ?? event.args?.file_path;
      if (typeof path === 'string') gen.files.add(path);
    }),
    tool_execution_end: bound(async (gen, event) => {
      const error = event.isError ? ' · ERROR' : '';
      await edit(gen, t => appendTo(t, `  - Tools: ${event.toolName || 'unknown'}${error}\n  - Outcome: ${error ? 'error' : 'ok'}`));
    }),
    agent_end: bound(async gen => {
      if (!gen.file) return;
      const n = ++gen.turns;
      const files = [...gen.files].join(', ');
      gen.files.clear();
      gen.dirty = true;
      await edit(gen, t => appendTo(fmSet(fmSet(t, 'turns', n), 'last_turn', `pi-turn-${n}`),
        `${files ? `  - Files: ${files}\n` : ''}- Turn ${n}: completed`));
    }),
    before_agent_start: bound((gen, _event, ctx) => {
      const onBranch = (ctx.sessionManager?.getBranch?.() || [])
        .some(e => e.type === 'custom_message' && e.customType === RESTORE_TYPE);
      const parts = [];
      let customType = HANDOFF_TYPE;
      if (gen.restore && !onBranch) { parts.push(gen.restore); customType = RESTORE_TYPE; }
      if (gen.handoff) parts.push(`# Memory Bank handoff after compaction (not a new user request)\n\n${gen.handoff}`);
      gen.restore = gen.handoff = null;
      if (!parts.length || off('MB_AUTOLOAD_CONTEXT')) return undefined;
      return { message: { customType, content: parts.join('\n\n'), display: false } };
    }),
    session_before_compact: bound(async (gen, event) => {
      if (!gen.bank || off('MB_PRECOMPACT_HANDOFF')) return undefined;
      const seconds = Number(process.env.MB_PRECOMPACT_BUDGET) || 2;
      try {
        await script([join(skillDir, 'scripts/mb-handoff.sh'), '--actualize', gen.bank, 'pre_compact'], gen.cwd,
          { env: { MB_SESSION_ID: gen.id }, signal: event.signal, timeoutMs: seconds * 1000 });
        gen.pendingHandoff = await readText(join(gen.bank, 'handoff/latest.md'), HANDOFF_CAP);
        await edit(gen, t => appendTo(t, `- ${clock()} — saved handoff/latest.md (pre_compact, ${event.reason || 'threshold'})`, '## Handoff capsule'));
      } catch (error) {
        gen.pendingHandoff = null;
        await edit(gen, t => appendTo(t, `- ${clock()} — failed: ${String(error.message).split('\n')[0].slice(0, 160)}`, '## Handoff capsule'));
      }
      return undefined;
    }),
    session_compact: bound(gen => { gen.handoff = gen.pendingHandoff; gen.pendingHandoff = null; }),
    session_compact_failed: bound(gen => { gen.pendingHandoff = null; }),
    session_shutdown(event) {
      const gen = current;
      if (!gen) return undefined;
      current = null;
      return serial(() => finalize(gen, event?.reason));
    },
  };
}
