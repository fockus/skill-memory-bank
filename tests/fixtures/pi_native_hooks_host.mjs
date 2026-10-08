// Tool-lifecycle harness for the Pi guard hooks: the real extension (installed shape, Pi's jiti)
// or the hooks module directly, real scripts on a real filesystem. Pi's runner order is simulated:
// tool_call handlers run first and a block stops the call before the tool body mutates anything;
// tool_result handlers then chain their content like ExtensionRunner.emitToolResult.
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

let raw = '';
for await (const chunk of process.stdin) raw += chunk;
const input = JSON.parse(raw);
const root = process.cwd();
const skillDir = input.skillDir || root;

const handlers = new Map();
const pi = {
  registerTool() {},
  on: (name, fn) => { handlers.set(name, [...(handlers.get(name) || []), fn]); return () => {}; },
};
if (input.mode === 'module') {
  const mod = await import(pathToFileURL(join(skillDir, 'adapters/pi_native_hooks.mjs')).href);
  mod.registerGuardHooks(pi, { skillDir, timeoutMs: input.timeoutMs });
} else {
  const packageRoot = process.env.PI_PACKAGE_ROOT || join(execFileSync('npm', ['root', '-g'], { encoding: 'utf8' }).trim(), '@earendil-works/pi-coding-agent');
  const require = createRequire(join(packageRoot, 'package.json'));
  const { createJiti } = require('jiti');
  const dir = await mkdtemp(join(input.home, 'ext-'));
  const ext = join(dir, 'memory-bank-graph-rag.ts');
  await writeFile(ext, (await readFile(join(root, 'adapters/pi_graph_rag_extension.ts'), 'utf8'))
    .replaceAll('__MB_SKILL_DIR_JSON__', JSON.stringify(skillDir))
    .replaceAll('__MB_PROJECT_ROOT_JSON__', '""'));
  const jiti = createJiti(import.meta.url, { alias: { typebox: require.resolve('typebox') } });
  await (await jiti.import(ext)).default(pi);
}

const ctxFor = (step, signal) => ({ cwd: step.cwd, hasUI: false, ui: { notify() {} }, signal,
  sessionManager: { getSessionId: () => 'sess-1' } });
const counts = {};
const run = async (name, event, ctx) => {
  counts[name] = (counts[name] || 0) + 1;
  const outs = [];
  for (const fn of handlers.get(name) || []) outs.push(await fn(event, ctx));
  return outs;
};

// The simulated tool bodies. Bash runs only fixtures the caller made inert (touch/echo in a temp dir).
async function perform(step) {
  const target = p => resolve(step.cwd, String(p).replace(/^@/, ''));
  if (step.tool === 'write') {
    await mkdir(dirname(target(step.input.path)), { recursive: true });
    await writeFile(target(step.input.path), step.input.content ?? '');
  } else if (step.tool === 'edit') {
    const file = target(step.input.path);
    const edit = step.input.edits[0];
    await writeFile(file, (await readFile(file, 'utf8')).replace(edit.oldText, edit.newText));
  } else if (step.tool === 'bash') {
    execFileSync('bash', ['-c', step.input.command], { cwd: step.cwd });
  }
}

const results = [{ events: [...handlers.keys()].sort() }];
for (const step of input.steps) {
  const started = Date.now();
  const controller = new AbortController();
  if (step.abortAfterMs !== undefined) setTimeout(() => controller.abort(), step.abortAfterMs);
  const ctx = ctxFor(step, controller.signal);
  try {
    if (step.emit) {
      await run(step.emit, { type: step.emit, ...step.event }, ctx);
      results.push({ ok: true, ms: Date.now() - started });
      continue;
    }
    const call = { type: 'tool_call', toolCallId: 'c1', toolName: step.tool, input: step.input };
    const block = (await run('tool_call', call, ctx)).find(r => r?.block);
    if (block) {
      results.push({ ok: true, blocked: true, reason: block.reason, executed: false, ms: Date.now() - started });
      continue;
    }
    if (!step.fail) await perform(step);
    const event = { type: 'tool_result', toolCallId: 'c1', toolName: step.tool, input: step.input,
      content: [{ type: 'text', text: step.output || 'tool output' }], isError: !!step.fail, details: undefined };
    for (const fn of handlers.get('tool_result') || []) {
      const out = await fn({ ...event }, ctx);
      if (out?.content) event.content = out.content;
    }
    counts.tool_result = (counts.tool_result || 0) + 1;
    results.push({ ok: true, blocked: false, executed: !step.fail,
      text: event.content.map(c => c.text).join('\n'), ms: Date.now() - started });
  } catch (error) {
    results.push({ ok: false, error: String(error?.message || error), ms: Date.now() - started });
  }
}
results.push({ counts });
process.stdout.write(`${JSON.stringify(results)}\n`);
