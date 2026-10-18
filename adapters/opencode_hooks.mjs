// Native tool inputs mapped once onto portable MB policies, never a shell sandbox.
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';
import { validatePath } from './opencode_paths.mjs';

const writing = new Set(['write', 'edit', 'patch']);
const policyTools = new Set([...writing, 'shell', 'subagent']);
const requirement = file => /\/(?:context\/[^/]+|specs\/[^/]+\/requirements)\.md$/.test(file.replaceAll('\\', '/'));
const reject = detail => { throw new Error(`[MB] BLOCKED: ${detail}`); };
function text(value, name) {
  if (typeof value !== 'string' || !value.trim() || value.includes('\0') || value.length > 262144) reject(`malformed ${name}`);
  return value;
}
async function canonical(file) {
  const tail = [];
  for (let head = file; ; head = path.dirname(head)) {
    try { return path.join(await fs.realpath(head), ...tail); }
    catch (error) {
      if (error.code !== 'ENOENT') throw error;
      if (path.dirname(head) === head) throw error;
      tail.unshift(path.basename(head));
    }
  }
}
function inside(root, file) {
  const rel = path.relative(root, file);
  return rel && !rel.startsWith(`..${path.sep}`) && rel !== '..' && !path.isAbsolute(rel) ? rel : file;
}
function patchChanges(patchText) {
  const lines = text(patchText, 'patchText').trimEnd().split('\n');
  if (lines.shift() !== '*** Begin Patch' || lines.pop() !== '*** End Patch') reject('malformed patch envelope');
  const changes = [];
  let current;
  for (const line of lines) {
    const header = /^\*\*\* (Add File|Update File|Delete File): (.+)$/.exec(line);
    if (header) { current = { path: header[2], kind: header[1], content: '' }; changes.push(current); }
    else if (line.startsWith('*** Move to: ') && current?.kind === 'Update File') changes.push({ path: line.slice(13), kind: 'Move' });
    else if (current?.kind === 'Add File' && line.startsWith('+')) current.content += `${line.slice(1)}\n`;
    else if (!current || (current.kind === 'Delete File' && line) || (!/^(?:@@|[ +\-]|\*\*\* End of File$|$)/.test(line))) reject('malformed patch section');
  }
  if (!changes.length) reject('empty patch');
  return changes;
}

export function createToolHooks({ root, directory, runner, resolveBank, locate }) {
  const completed = new Set();
  const notes = new Map();
  const environment = bank => ({ MB_PROTECTED_MODE: 'deny', ...(bank ? { MB_PATH: bank } : {}) });
  const payload = (event, tool, input) => ({ cwd: directory, session_id: event.sessionID, tool_name: tool, tool_input: input });
  async function changes(event, candidate) {
    const input = event.input;
    if (!input || typeof input !== 'object' || Array.isArray(input)) reject('malformed native input');
    const raw = event.tool === 'patch' ? patchChanges(input.patchText) : [{ path: text(input.path, 'path'), kind: event.tool, content: undefined }];
    const result = [];
    for (const item of raw) {
      const rawPath = text(item.path, 'path');
      if (rawPath.includes('\n')) reject('malformed path');
      const lexical = path.resolve(directory, rawPath.startsWith('~/') ? path.join(os.homedir(), rawPath.slice(2)) : rawPath);
      const file = await canonical(lexical);
      let content = item.content;
      if (candidate && event.tool === 'write') {
        if (typeof input.content !== 'string') reject('malformed write content');
        content = input.content;
      }
      if (candidate && event.tool === 'edit') {
        const old = text(input.oldString, 'oldString');
        if (typeof input.newString !== 'string' || input.newString === old) reject('malformed newString');
        if ((await fs.stat(file)).size > 262144) reject('edit exceeds candidate validation limit');
        const original = await fs.readFile(file, 'utf8');
        const count = original.split(old).length - 1;
        if (!count || (count !== 1 && !input.replaceAll)) reject('ambiguous edit candidate');
        content = input.replaceAll ? original.split(old).join(input.newString) : original.replace(old, input.newString);
      }
      if (candidate && requirement(file) && event.tool === 'patch' && ['Update File', 'Move'].includes(item.kind)) {
        reject('requirement patch updates need a full candidate; use native write or edit for EARS validation');
      }
      result.push({ lexical, file, content });
    }
    return result;
  }
  async function guard(relative, data, bank, options = {}) {
    const out = await runner.run(relative, [], data, { env: environment(bank), ...options });
    if (out) {
      let parsed;
      try { parsed = JSON.parse(out); } catch { reject('policy returned malformed output'); }
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) reject('policy returned malformed output');
      if (parsed.decision === 'block' || ['deny', 'ask'].includes(parsed.hookSpecificOutput?.permissionDecision)) reject('policy requires approval');
    }
    return out;
  }
  async function before(event) {
    if (!policyTools.has(event.tool) && event.tool !== 'grep') return;
    if (!await locate(event.sessionID)) reject('session location unavailable or changed');
    const bank = await resolveBank(event.sessionID);
    if (!policyTools.has(event.tool)) {
      const out = await runner.optional('hooks/mb-graph-nudge.sh', [], payload(event, 'Grep', event.input), { env: environment(bank) });
      if (out) notes.set(event.sessionID, out);
      return;
    }
    // Shared guards deliberately fail open on missing dependencies; native policy does not.
    for (const file of ['SKILL.md', 'hooks/block-dangerous.sh', 'hooks/mb-protected-paths-guard.sh', 'scripts/mb-work-protected-check.sh', 'scripts/mb-pipeline.sh', 'references/pipeline.default.yaml', 'hooks/mb-ears-pre-write.sh', 'scripts/mb-ears-validate.sh', 'scripts/mb-session-spend.sh']) {
      try { await fs.access(path.join(root, file), file.endsWith('.sh') ? fs.constants.X_OK : fs.constants.R_OK); }
      catch { reject('required policy helper unavailable'); }
    }
    const pipeline = await runner.run('scripts/mb-pipeline.sh', ['path', ...(bank ? [bank] : [])], '', { env: environment(bank) });
    if (!path.isAbsolute(pipeline)) reject('policy selection unavailable');
    const selected = await fs.open(pipeline, 'r');
    try { if (!(await selected.stat()).isFile()) reject('selected policy is not a regular file'); }
    finally { await selected.close(); }
    await guard('hooks/block-dangerous.sh', payload(event, 'Bash', event.tool === 'shell' ? { command: text(event.input?.command, 'command') } : {}), bank);
    if (event.tool === 'shell') {
      const cwd = event.input.workdir === undefined ? directory : path.resolve(directory, text(event.input.workdir, 'workdir'));
      const data = { ...payload(event, 'Bash', event.input), cwd };
      await guard('hooks/mb-protected-paths-guard.sh', data, bank, { cwd });
      const targets = await runner.run('adapters/opencode_session.sh', ['targets', cwd, event.sessionID], data, { env: environment(bank), cwd });
      for (const target of targets.split('\n').filter(Boolean)) {
        const file = await canonical(path.resolve(cwd, target));
        await guard('hooks/mb-protected-paths-guard.sh', payload(event, 'Write', { file_path: inside(await canonical(directory), file) }), bank);
      }
      const out = await runner.optional('hooks/mb-graph-nudge.sh', [], data, { env: environment(bank) });
      if (out) notes.set(event.sessionID, out);
    } else if (writing.has(event.tool)) {
      for (const change of await changes(event, true)) {
        for (const file of new Set([change.lexical, change.file])) {
          const base = file === change.lexical ? directory : await canonical(directory);
          await guard('hooks/mb-protected-paths-guard.sh', payload(event, 'Write', { file_path: inside(base, file) }), bank);
        }
        if (change.content !== undefined) await guard('hooks/mb-ears-pre-write.sh', payload(event, 'Write', { file_path: change.file, content: change.content }), bank);
      }
    } else if (event.tool === 'subagent') {
      text(event.input?.agent, 'agent'); text(event.input?.description, 'description'); text(event.input?.prompt, 'prompt');
      if (bank) {
        const env = environment(bank);
        await validatePath(bank, 'directory');
        await validatePath(path.join(bank, '.session-spend.json'), 'file', true);
        try { await fs.access(path.join(bank, '.session-spend.json')); }
        catch { await runner.run('scripts/mb-session-spend.sh', ['init', '--mb', bank], '', { env }); }
        await validatePath(path.join(bank, '.session-spend.json'), 'file');
        await runner.run('scripts/mb-session-spend.sh', ['add', String(event.input.prompt.length + event.input.description.length), '--mb', bank], '', { env });
        await validatePath(path.join(bank, '.session-spend.json'), 'file');
        await runner.run('scripts/mb-session-spend.sh', ['check', '--mb', bank], '', { env, allowSoft: true });
      }
      const out = await runner.optional('hooks/mb-context-slim-pre-agent.sh', [], payload(event, 'Agent', event.input), { env: environment(bank) });
      if (out) notes.set(event.sessionID, out);
    }
  }
  return {
    before: event => before(event).catch(error => { throw new Error(error.message.startsWith('[MB]') ? error.message : '[MB] BLOCKED: policy could not evaluate this action'); }),
    async after(event) {
      if (event.status !== 'completed' || !writing.has(event.tool) || completed.has(event.id)) return;
      if (!await locate(event.sessionID)) return;
      const bank = await resolveBank(event.sessionID);
      try {
        const touched = await changes(event, false);
        for (const change of touched) await runner.run('hooks/file-change-log.sh', [], payload(event, 'Write', { file_path: change.file }), { env: environment(bank) });
        const canonicalBank = bank ? await canonical(bank) : null;
        const sync = [...new Set(touched.filter(c => canonicalBank && /^(plans|specs)\/.+\.md$/.test(inside(canonicalBank, c.file))).map(c => c.file))];
        if (sync.length) await runner.run('hooks/mb-plan-sync-post-write.sh', [], payload(event, 'Write', { file_path: sync[0], file_paths: sync }), { env: environment(bank), timeout: 30000 });
        completed.add(event.id);
      } catch { notes.set(event.sessionID, '[MB] Post-write synchronization failed; run /mb update and check shared hook output.'); }
    },
    takeNote(sid) { const out = notes.get(sid); notes.delete(sid); return out; },
  };
}
