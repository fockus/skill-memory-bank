// Event harness: the real GraphRAG extension (installed shape, through Pi's own jiti) with real
// scripts on a real filesystem. Only Pi's tool registry and event dispatch are simulated.
import { readFile, writeFile, mkdtemp, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';

let raw = '';
for await (const chunk of process.stdin) raw += chunk;
const input = JSON.parse(raw);
const root = process.cwd();
const packageRoot = process.env.PI_PACKAGE_ROOT || join(execFileSync('npm', ['root', '-g'], { encoding: 'utf8' }).trim(), '@earendil-works/pi-coding-agent');
const require = createRequire(join(packageRoot, 'package.json'));
const { createJiti } = require('jiti');
const dir = await mkdtemp(join(input.home, 'ext-'));
const ext = join(dir, 'memory-bank-graph-rag.ts');
await writeFile(ext, (await readFile(join(root, 'adapters/pi_graph_rag_extension.ts'), 'utf8'))
  .replaceAll('__MB_SKILL_DIR_JSON__', JSON.stringify(root))
  .replaceAll('__MB_PROJECT_ROOT_JSON__', JSON.stringify(input.projectRoot || '')));

const tools = new Map(), handlers = new Map();
const pi = {
  registerTool: def => tools.set(def.name, def),
  on: (name, fn) => handlers.set(name, [...(handlers.get(name) || []), fn]),
};
const ctxFor = s => ({ cwd: s.cwd, hasUI: false, ui: { notify() {} },
  sessionManager: { getSessionId: () => s.sessionId || 'sess-1' } });
const jiti = createJiti(import.meta.url, { alias: { typebox: require.resolve('typebox') } });
const factory = (await jiti.import(ext)).default;
await factory(pi);

const results = [{ tools: [...tools.keys()].sort(), events: [...handlers.keys()].sort() }];
for (const step of input.steps) {
  const started = Date.now();
  try {
    if (step.call) {
      const controller = new AbortController();
      if (step.abortAfterMs !== undefined) setTimeout(() => controller.abort(), step.abortAfterMs);
      const out = await tools.get(step.call).execute('call-1', step.params || {}, controller.signal, undefined, ctxFor(step));
      results.push({ ok: true, text: out.content.map(c => c.text).join('\n'), details: out.details, ms: Date.now() - started });
    } else if (step.emit) {
      const outs = [];
      for (const fn of handlers.get(step.emit) || []) outs.push(await fn({ type: step.emit, ...step.event }, ctxFor(step)));
      results.push({ ok: true, outputs: outs.filter(Boolean), ms: Date.now() - started });
    } else if (step.waitFile) {
      while (!(await stat(step.waitFile).then(() => true, () => false)) && Date.now() - started < (step.timeoutMs || 20000)) {
        await new Promise(r => setTimeout(r, 50));
      }
      results.push({ ok: true, exists: await stat(step.waitFile).then(() => true, () => false) });
    }
  } catch (error) {
    results.push({ ok: false, error: String(error?.message || error), ms: Date.now() - started });
  }
}
process.stdout.write(`${JSON.stringify(results)}\n`);
