import assert from 'node:assert/strict';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
export const turn = (id = '1', answer = 'Changed: Added the native bridge.\nDecision: Keep the shared resolver.\nNext: Verify timeout cleanup.') => [
  { id: `u${id}`, type: 'user', text: `Implement native memory ${id}`, time: { created: 1 } },
  { id: `a${id}`, type: 'assistant', content: [{ type: 'text', text: answer }], time: { created: 2, completed: 3 }, finish: 'stop', snapshot: { files: ['src/native.py'] } },
];
export function request(sessionID = 'root') {
  return { sessionID, agent: 'mb-backend', system: [], messages: [], options: {}, tools: {} };
}
export async function fixture(t, { extended = true, bank = true } = {}) {
  const temp = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'mb-opencode-')));
  const bundle = path.join(temp, 'bundle space');
  const cwd = path.join(temp, 'project');
  const mb = path.join(cwd, '.memory-bank');
  await fs.mkdir(cwd, { recursive: true });
  await fs.mkdir(bundle);
  for (const dir of ['adapters', 'scripts', 'hooks', 'memory_bank_skill', 'references', 'rules']) await fs.cp(path.join(ROOT, dir), path.join(bundle, dir), { recursive: true });
  for (const file of ['SKILL.md', 'VERSION']) await fs.copyFile(path.join(ROOT, file), path.join(bundle, file));
  const previous = { ...process.env };
  for (const key of Object.keys(process.env)) if (key.startsWith('MB_') || key.startsWith('CLAUDE_') || key.startsWith('XDG_')) delete process.env[key];
  Object.assign(process.env, { HOME: temp, MB_SEMANTIC: 'off', MB_GRAPH_CATCHUP: 'off', MB_AUTO_REFRESH: 'off' });
  if (bank) {
    await fs.mkdir(mb);
    await fs.writeFile(path.join(mb, 'progress.md'), '# Progress\n');
    await fs.writeFile(path.join(mb, 'status.md'), '# Current task: verify the native boundary\n');
    await fs.writeFile(path.join(mb, 'checklist.md'), '- [ ] Finish timeout verification\n');
  }
  const histories = {}, sessions = {}, calls = [];
  let live;
  /** @param {{workspaceID?: string}} [options] */
  async function load({ workspaceID } = {}) {
    const hooks = new Map();
    let signal, pending, acknowledged;
    const queue = [];
    const register = domain => async (name, fn) => {
      const key = `${domain}.${name}`;
      assert(!hooks.has(key));
      hooks.set(key, fn);
      return { async dispose() { hooks.delete(key); } };
    };
    const definition = (await import(pathToFileURL(path.join(bundle, 'adapters/opencode_plugin.mjs')).href)).createMemoryBankPlugin({ extended });
    const cleanup = await definition.setup({
      location: { directory: cwd, workspaceID, project: { id: 'fixture', directory: cwd, canonical: cwd } },
      session: { hook: register('session'),
        async get({ sessionID }, options) {
          calls.push(['get', sessionID]);
          if (sessions[sessionID] instanceof Error) throw sessions[sessionID];
          return { projectID: 'fixture', ...(sessions[sessionID] ?? { id: sessionID, location: { directory: cwd } }) };
        },
        async context({ sessionID }, options) {
          assert(options?.signal instanceof AbortSignal);
          calls.push(['context', sessionID]);
          return structuredClone(histories[sessionID] ?? []);
        },
      },
      tool: { hook: register('tool') },
      event: { subscribe(options) {
        signal = options.signal;
        return { [Symbol.asyncIterator]() { return this; }, next() {
          acknowledged?.(); acknowledged = undefined;
          if (signal.aborted) return Promise.resolve({ done: true });
          return new Promise(resolve => {
            const deliver = () => { const item = queue.shift(); acknowledged = item.done; resolve({ done: false, value: item.event }); };
            if (queue.length) deliver(); else pending = deliver;
            signal.addEventListener('abort', () => resolve({ done: true }), { once: true });
          });
        } };
      } },
    });
    live = {
      hook: async (name, input) => { assert(hooks.has(name), name); await hooks.get(name)(input); },
      emit: (type, data, location) => new Promise(done => { queue.push({ event: { type, data, location }, done }); const deliver = pending; pending = undefined; deliver?.(); }),
      async dispose() { await cleanup(); assert(signal.aborted); assert.equal(hooks.size, 0); },
    };
    return live;
  }
  t.after(async () => {
    await live?.dispose();
    for (const key of Object.keys(process.env)) if (!(key in previous)) delete process.env[key];
    Object.assign(process.env, previous);
    await fs.rm(temp, { recursive: true, force: true });
  });
  return { temp, bundle, cwd, mb, histories, sessions, calls, load,
    async records() { return (await fs.readdir(path.join(mb, 'session')).catch(() => [])).filter(f => f.endsWith('.md') && f !== '_recent.md'); },
  };
}
