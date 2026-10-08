// Event harness: real session extension (through Pi's own jiti loader) + real scripts on a
// real filesystem. Only Pi's event dispatch and session manager are simulated.
import { readFile, writeFile, mkdtemp } from 'node:fs/promises';
import { join } from 'node:path';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';

let raw = '';
for await (const chunk of process.stdin) raw += chunk;
const input = JSON.parse(raw);
const root = process.cwd();
const packageRoot = process.env.PI_PACKAGE_ROOT || join(execFileSync('npm', ['root', '-g'], { encoding: 'utf8' }).trim(), '@earendil-works/pi-coding-agent');
const { createJiti } = createRequire(join(packageRoot, 'package.json'))('jiti');
const dir = await mkdtemp(join(input.home, 'ext-'));
// Installed shape of the current opt-in path: the template alone, placeholders baked.
const ext = join(dir, 'memory-bank-session.ts');
await writeFile(ext, (await readFile(join(root, 'adapters/pi_session_memory_extension.ts'), 'utf8'))
  .replaceAll('__MB_SKILL_DIR_JSON__', JSON.stringify(root)).replaceAll('__MB_PROJECT_ROOT_JSON__', '""'));

const runtimes = new Map(), pending = [], results = [];
const branches = input.branches || {};
const ctxFor = s => ({
  cwd: s.cwd, hasUI: false, ui: { notify() {} },
  sessionManager: {
    getSessionId: () => s.id,
    getSessionFile: () => s.file ?? `/sandbox/.pi/agent/sessions/${s.id}.jsonl`,
    getBranch: () => branches[s.id] || [],
  },
});
async function emit(step) {
  const handlers = runtimes.get(step.rt || 'r1').get(step.event) || [];
  const values = [];
  for (const handler of handlers) values.push(await handler({ type: step.event, ...(step.payload || {}) }, ctxFor(step.session)));
  for (const value of values) {
    // Pi persists before_agent_start messages as custom_message entries on the branch.
    if (step.event === 'before_agent_start' && value?.message) {
      (branches[step.session.id] ||= []).push({ type: 'custom_message', ...value.message });
    }
  }
  return values.filter(v => v !== undefined);
}
for (const step of input.steps) {
  if (step.op === 'load') {
    const handlers = new Map();
    const jiti = createJiti(import.meta.url, { moduleCache: false });
    const factory = await jiti.import(ext, { default: true });
    await factory({ on(name, fn) { if (!handlers.has(name)) handlers.set(name, []); handlers.get(name).push(fn); return () => {}; } });
    runtimes.set(step.rt || 'r1', handlers);
  } else if (step.op === 'emit') {
    const started = Date.now();
    const run = emit(step).then(values => ({ event: step.event, values, ms: Date.now() - started }),
      error => ({ event: step.event, error: String(error) }));
    if (step.wait === false) pending.push(run); else results.push(await run);
  } else if (step.op === 'settle') {
    results.push(...await Promise.all(pending.splice(0)));
  } else if (step.op === 'kill') {
    process.kill(process.pid, 'SIGKILL');
  }
}
results.push(...await Promise.all(pending.splice(0)));
console.log(JSON.stringify({ results, branches }));
