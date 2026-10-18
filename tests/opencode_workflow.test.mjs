import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import * as fs from 'node:fs/promises';
import * as os from 'node:os';
import * as path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { createRunner } from '../adapters/opencode_process.mjs';
import { createWorkflowBinding } from '../adapters/opencode_workflow.mjs';

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const parent = { providerID: 'fixture', id: 'parent', variant: 'parent' };
const event = (agent = 'mb-developer', model) => ({ sessionID: 'root', tool: 'subagent', input: {
  agent, description: 'Contract dispatch', prompt: 'Identity must come from canonical state, not this text.',
  ...(model ? { model } : {}),
} });

async function fixture(t, { second = false, planning = false, sharedStep = false, planningOnly = false } = {}) {
  const directory = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'mb-s4-binding-')));
  const bank = path.join(directory, '.memory-bank');
  await fs.mkdir(path.join(bank, 'plans'), { recursive: true });
  const previous = { ...process.env };
  for (const key of Object.keys(process.env)) if (/^(MB_|CLAUDE_|XDG_)/.test(key)) delete process.env[key];
  Object.assign(process.env, { HOME: directory, MB_PATH: bank });
  const roles = { developer: { agent: 'mb-developer', model: 'fixture/one#deep' },
    backend: { agent: 'mb-developer', model: 'fixture/two#deep' }, planner: { agent: 'mb-architect', model: 'fixture/two#deep' },
    ...(sharedStep ? { verifier: { agent: 'mb-developer', model: 'fixture/two#deep' } } : {}) };
  await fs.writeFile(path.join(bank, 'pipeline.yaml'), JSON.stringify({ roles, qa: { enabled: false },
    workflow: { default: 'check' }, workflows: { check: { steps: planningOnly ? ['discuss', 'sdd', 'plan'] : planning ? ['discuss', 'sdd', 'plan', 'implement', 'done'] : sharedStep ? ['implement', 'verify', 'done'] : ['implement', 'done'],
      entrypoint: planning ? 'freeform_or_topic' : 'plan_or_spec' } } }));
  let source = path.join(bank, 'plans', 'case.md');
  if (!planning) await fs.writeFile(source, '<!-- mb-stage:1 -->\n### Stage 1\n**Role:** developer\n- [ ] First\n'
    + (second ? '<!-- mb-stage:2 -->\n### Stage 2\n**Role:** backend\n- [ ] Second\n' : ''));
  const catalog = ['one', 'two', 'parent'].map(id => ({ providerID: 'fixture', id, enabled: true, variants: [{ id: id === 'parent' ? 'parent' : 'deep' }] }));
  const definitions = new Map();
  const pins = new Map(['mb-developer', 'mb-architect'].map(id => [id, { providerID: 'fixture', id: 'one', variant: 'deep' }]));
  const messages = [];
  let admission = 0;
  let selectedRun;
  const ctx = { model: { async list() { return { data: catalog }; } },
    agent: { async get({ agentID }) { return { data: { id: agentID, model: pins.get(agentID) } }; } },
    command: { async transform(callback) { callback({ add(def) { definitions.set(def.name, def); } }); return { async dispose() {} }; },
      async list() { return { data: [...definitions.values()] }; } },
    session: { async prompt({ text }) {
      const marker = 'OpenCode work preflight (shared resolvers, authoritative): ';
      const result = JSON.parse(text.slice(text.lastIndexOf(marker) + marker.length).split('\n')[0]);
      if (result.run_id) selectedRun = result.run_id;
      const id = `msg_${++admission}`; messages.push({ id, type: 'user', text: 'Native command admission' }); return { id };
    },
      async context() { return messages; } } };
  const controller = new AbortController();
  const runner = createRunner(ROOT, directory, controller.signal);
  const binding = createWorkflowBinding({ ctx: /** @type {import('@opencode/plugin').Plugin.Context} */ (/** @type {unknown} */ (ctx)), root: ROOT, directory, runner, signal: controller.signal,
    locate: async sid => ({ id: sid, location: { directory }, model: parent }), resolveBank: async () => bank });
  const registration = await binding.install();
  const script = (name, args, foreign = false) => execFileSync('bash', [path.join(ROOT, 'scripts', name), ...args],
    { cwd: directory, env: { ...process.env, ...(foreign ? { MB_WORK_PARALLEL: '1' } : selectedRun ? {
      MB_WORK_RUN_ID: selectedRun, MB_WORK_PARALLEL: '1', MB_WORK_RETAIN_STATE: '1', MB_WORK_RETAIN_BANK: bank,
    } : {}) }, timeout: 10000, encoding: 'utf8' }).trim();
  const state = (verb, args = []) => script('mb-work-state.sh', [verb, ...args, '--mb', bank]);
  t.after(async () => {
    await registration?.dispose(); await runner.dispose();
    for (const key of Object.keys(process.env)) if (!(key in previous)) delete process.env[key];
    Object.assign(process.env, previous);
    await fs.rm(directory, { recursive: true, force: true });
  });
  return { bank, directory, binding, state, script,
    start: async args => { await binding.context({ sessionID: 'root', model: parent }); await definitions.get('work').execute({ sessionID: 'root', prompt: { text: args }, delivery: 'queue' }); },
    init: (number, run = '') => state('init', ['plan', String(number), '--source-path', source, '--max-cycles', '2', ...(run ? ['--run-id', run] : [])]),
    context: () => binding.context({ sessionID: 'root', model: parent }),
    flip: number => script('mb-work-checkbox.sh', ['flip', source, String(number), '--mb', bank]),
    foreignState: (...args) => script('mb-work-state.sh', [...args, '--mb', bank], true),
    finishPlanning: (outcome = 'succeeded') => { messages.push({ id: 'msg_assistant', type: 'assistant', finish: outcome === 'succeeded' ? 'stop' : 'error', time: { completed: 1 } },
      { id: 'msg_terminal', type: 'idle', outcome }); },
    planned: async () => { script('mb-plan.sh', ['feature', 'new-topic', bank]); source = path.join(bank, 'plans', (await fs.readdir(path.join(bank, 'plans'))).find(f => f.includes('new-topic'))); },
  };
}

test('S4-ITEM-3 the canonical current item governs a shared native agent, never a future or previous pin', async t => {
  const f = await fixture(t, { second: true });
  await f.start('case');
  const run = f.init(1);
  f.state('step', ['implement']);
  await assert.rejects(f.binding.before(event('mb-developer', 'fixture/two#deep')), /requires fixture\/one#deep/);
  const first = event(); await f.binding.before(first); assert.equal(first.input.model, 'fixture/one#deep');
  f.state('done'); f.flip(1); await f.context();
  f.init(2, run); f.state('step', ['implement']);
  await assert.rejects(f.binding.before(event('mb-developer', 'fixture/one#deep')), /requires fixture\/two#deep/);
  const second = event(); await f.binding.before(second); assert.equal(second.input.model, 'fixture/two#deep');
});

test('S4-RUN-4 confirmed canonical done/flip then clear expires only the run override', async t => {
  const f = await fixture(t);
  await f.start('case --model inherit');
  f.init(1); await f.context();
  const active = event(); await f.binding.before(active); assert.equal(active.input.model, 'fixture/parent#parent');
  f.state('done'); f.flip(1); await f.context();
  f.state('clear');
  const ordinary = event(); await f.binding.before(ordinary);
  assert.equal(ordinary.input.model, undefined, 'ordinary dispatch must leave its normal native agent pin untouched');
});

test('S4-RUN-4 grouped canonical done/flip/clear releases only the completed binding', async t => {
  const f = await fixture(t);
  await f.start('case --model inherit'); f.init(1); await f.context();
  f.state('done'); f.flip(1); f.state('clear');
  const ordinary = event(); await f.binding.before(ordinary); assert.equal(ordinary.input.model, undefined);
});

test('S4-RUN-4 grouped repeated clear preserves proof and restores ordinary dispatch', async t => {
  const f = await fixture(t);
  await f.start('case --model inherit'); f.init(1); await f.context();
  f.state('done'); f.flip(1); f.state('clear'); f.state('clear');
  const ordinary = event(); await f.binding.before(ordinary); assert.equal(ordinary.input.model, undefined);
});

test('S4-RUN-4 completion of one item cannot release a selection with unfinished items', async t => {
  const f = await fixture(t, { second: true }); await f.start('case --model inherit');
  const run = f.init(1); f.state('done'); f.flip(1); f.state('clear');
  await assert.rejects(f.binding.before(event()), /canonical|work-state/i);
  f.init(2, run); f.state('done'); f.flip(2); f.state('clear');
  const ordinary = event(); await f.binding.before(ordinary); assert.equal(ordinary.input.model, undefined);
});

test('S4-PREVIEW-7 dry-run leaves ordinary dispatch unbound', async t => {
  const f = await fixture(t); await f.start('case --dry-run');
  const ordinary = event(); await f.binding.before(ordinary); assert.equal(ordinary.input.model, undefined);
});

test('S4-PREVIEW-7 only the completed admitted planning generation ends its planning model binding', async t => {
  const f = await fixture(t, { planning: true, planningOnly: true }); await f.start('new-topic');
  const planner = event('mb-architect'); await f.binding.before(planner); assert.equal(planner.input.model, 'fixture/two#deep');
  f.finishPlanning();
  const ordinary = event('mb-architect'); await f.binding.before(ordinary); assert.equal(ordinary.input.model, undefined);
  await f.binding.before(event());
});

test('S4-PREVIEW-7 failed planning also ends model scope without certifying an execution item', async t => {
  const f = await fixture(t, { planning: true, planningOnly: true }); await f.start('new-topic');
  f.finishPlanning('failed');
  const ordinary = event('mb-architect'); await f.binding.before(ordinary); assert.equal(ordinary.input.model, undefined);
  assert.equal(f.state('status', ['--all']), '[]');
});

test('native shell host selection is location-scoped, never an ownership claim', async t => {
  const f = await fixture(t);
  const shell = { command: 'printf ordinary', cwd: f.directory, env: { MB_PIPELINE_HOST: 'codex' } };
  await f.binding.shell(shell);
  assert.equal(shell.env.MB_PIPELINE_HOST, 'opencode');
  assert.equal('MB_WORK_RUN_ID' in shell.env, false);
  const foreign = { command: 'printf foreign', cwd: path.dirname(f.directory), env: { MB_PIPELINE_HOST: 'codex' } };
  await f.binding.shell(foreign); assert.equal(foreign.env.MB_PIPELINE_HOST, 'codex');
});

test('S4-IDENTITY-9 an existing unfinished selection needs an explicit matching resume', async t => {
  const f = await fixture(t);
  const source = path.join(f.bank, 'plans', 'case.md');
  f.foreignState('init', source, '1', '--source-path', source, '--run-id', 'prior-root');
  await assert.rejects(f.start('case --model inherit'), /unfinished.*resume/i);
  await f.start('case --model inherit --run-id prior-root');
  const resumed = event(); await f.binding.before(resumed); assert.equal(resumed.input.model, 'fixture/parent#parent');
});

test('S4-IDENTITY-9 explicit singleton resume delivers its canonical slot mode to actual native shells', async t => {
  const f = await fixture(t);
  const source = path.join(f.bank, 'plans/case.md');
  f.script('mb-work-state.sh', ['init', 'plan', '1', '--source-path', source, '--run-id', 'legacy-root', '--mb', f.bank]);
  await f.start('case --model inherit --run-id legacy-root');
  const action = { sessionID: 'root', id: 'legacy-step', tool: 'shell', input: {
    command: `bash "${ROOT}/scripts/mb-work-state.sh" step implement --mb "${f.bank}"`, workdir: f.directory } };
  await f.binding.before(action);
  const shell = { command: action.input.command, cwd: f.directory, env: /** @type {NodeJS.ProcessEnv} */ ({}) };
  await f.binding.shell(shell);
  execFileSync('bash', ['-c', shell.command], { cwd: f.directory, env: { ...process.env, ...shell.env }, timeout: 10000 });
  assert.equal(shell.env.MB_WORK_PARALLEL, '0');
  const state = JSON.parse(await fs.readFile(path.join(f.bank, '.work-state.json'), 'utf8'));
  assert.equal(state.run_id, 'legacy-root'); assert.deepEqual(state.steps, ['implement']);
  assert.equal(await fs.stat(path.join(f.bank, '.work-state/legacy-root.json')).catch(() => null), null);
  await f.binding.after(action);
  const resumed = event(); await f.binding.before(resumed); assert.equal(resumed.input.model, 'fixture/parent#parent');
});

for (const conflict of ['foreign-source', 'duplicate-same-source', 'duplicate-foreign-source']) test(`S4-IDENTITY-9 explicit resume refuses ${conflict} without mutating either slot`, async t => {
  const f = await fixture(t);
  const source = path.join(f.bank, 'plans/case.md'), other = path.join(f.bank, 'plans/other.md');
  await fs.copyFile(source, other);
  f.script('mb-work-state.sh', ['init', 'plan', '1', '--source-path', conflict === 'foreign-source' ? other : source,
    '--run-id', 'legacy-root', '--mb', f.bank]);
  if (conflict !== 'foreign-source') f.foreignState('init', 'plan', '1', '--source-path', conflict === 'duplicate-same-source' ? source : other, '--run-id', 'legacy-root');
  const slots = [path.join(f.bank, '.work-state.json'), ...(conflict === 'foreign-source' ? [] : [path.join(f.bank, '.work-state/legacy-root.json')])];
  const original = await Promise.all(slots.map(slot => fs.readFile(slot, 'utf8')));
  await assert.rejects(f.start('case --run-id legacy-root'), /matching canonical|ambiguous|resume/i);
  assert.deepEqual(await Promise.all(slots.map(slot => fs.readFile(slot, 'utf8'))), original);
});

for (const wrapper of [false, true]) test(`S4-IDENTITY-9 full-cycle entry resumes the matching declaration (wrapper=${wrapper})`, async t => {
  const f = await fixture(t, { planning: true }); await f.planned();
  const source = (await fs.readdir(path.join(f.bank, 'plans'))).find(name => name.includes('new-topic'));
  let file = path.join(f.bank, 'plans', source);
  if (wrapper) {
    await fs.writeFile(file, '---\nlinked_spec: specs/topic\ntasks: 1\n---\n# Existing wrapper\n');
    file = path.join(f.bank, 'specs/topic/tasks.md'); await fs.mkdir(path.dirname(file), { recursive: true });
    await fs.writeFile(file, '<!-- mb-task:1 -->\n## Task 1\n**Role:** developer\n**Eval:** none — waiver: structural planning only\n**DoD:**\n- [ ] Work\n');
  }
  f.foreignState('init', wrapper ? 'spec' : file, '1', '--source-path', file, '--run-id', 'prior-root');
  await assert.rejects(f.start('new-topic --model inherit'), /unfinished.*resume/i);
  await assert.rejects(f.start('unrelated-topic --run-id prior-root'), /resume|not found|blocked/i);
  await f.start('new-topic --model inherit --run-id prior-root');
  const resumed = event(); await f.binding.before(resumed); assert.equal(resumed.input.model, 'fixture/parent#parent');
});

test('S4-STATE-8 absent unfinished state cannot fall through to the same agent verifier pin', async t => {
  const f = await fixture(t, { sharedStep: true }); await f.start('case --model inherit');
  const run = f.init(1); f.state('step', ['implement']); await f.context(); f.state('clear');
  await assert.rejects(f.binding.before(event()), /canonical|work-state/i);
  f.init(1, run); f.state('step', ['implement']);
  const resumed = event(); await f.binding.before(resumed); assert.equal(resumed.input.model, 'fixture/parent#parent');
});

test('S4-STATE-8 canonical reinit outranks stale checked boxes when item and verifier share an agent', async t => {
  const f = await fixture(t, { sharedStep: true });
  const source = path.join(f.bank, 'plans/case.md');
  await fs.writeFile(source, (await fs.readFile(source, 'utf8')).replace('[ ]', '[x]'));
  await f.start('case --model inherit'); f.init(1); f.state('step', ['implement']);
  const item = event(); await f.binding.before(item); assert.equal(item.input.model, 'fixture/parent#parent');
  f.state('clear'); await assert.rejects(f.binding.before(event()), /canonical|work-state/i);
});

test('S4-IDENTITY-9 neither a prior update nor a new foreign run belongs to deferred planning', async t => {
  const f = await fixture(t, { planning: true });
  const source = path.join(f.bank, 'plans', 'prior.md');
  await fs.writeFile(source, '<!-- mb-stage:1 -->\n### Stage 1\n**Role:** backend\n- [ ] Foreign work\n');
  f.foreignState('init', source, '1', '--source-path', source, '--run-id', 'prior-root');
  await f.start('new-topic'); f.foreignState('step', 'implement', '--run-id', 'prior-root');
  await assert.rejects(f.binding.before(event()), /canonical|planning|source|run/i);
  const other = path.join(f.bank, 'plans', 'other.md'); await fs.copyFile(source, other);
  f.foreignState('init', other, '1', '--source-path', other, '--run-id', 'new-foreign-root');
  await assert.rejects(f.binding.before(event()), /canonical|planning|source|run/i);
});

for (const markDone of [false, true]) test(`S4-RUN-4 absent unflipped state is not completion (done=${markDone})`, async t => {
  const f = await fixture(t);
  await f.start('case --model inherit');
  const run = f.init(1); await f.context();
  if (markDone) { f.state('done'); await f.context(); }
  f.state('clear'); await f.context();
  await assert.rejects(f.binding.before(event()), /canonical|work-state/i);
  f.init(1, run);
  const resumed = event(); await f.binding.before(resumed); assert.equal(resumed.input.model, 'fixture/parent#parent');
});

test('S4-ITEM-3 a shared native agent uses the current canonical step, not an allowed future step model', async t => {
  const f = await fixture(t, { sharedStep: true });
  await f.start('case'); f.init(1);
  await assert.rejects(f.binding.before(event()), /current canonical workflow step/);
  f.state('step', ['implement']);
  await assert.rejects(f.binding.before(event('mb-developer', 'fixture/two#deep')), /requires fixture\/one#deep/);
  f.state('step', ['verify']);
  await assert.rejects(f.binding.before(event('mb-developer', 'fixture/one#deep')), /requires fixture\/two#deep/);
  const verifier = event(); await f.binding.before(verifier); assert.equal(verifier.input.model, 'fixture/two#deep');
});

test('S4-ENTRY-1 execution binds only after the existing planning path creates and initializes the actual source', async t => {
  const f = await fixture(t, { planning: true });
  await f.start('new-topic');
  await f.binding.before(event('mb-architect'));
  await f.planned();
  f.init(1); f.state('step', ['implement']);
  const implementation = event(); await f.binding.before(implementation);
  assert.equal(implementation.input.model, 'fixture/one#deep');
});
