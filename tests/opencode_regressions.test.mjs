import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fixture, request, turn } from './opencode_fixture.mjs';
import { createRunner } from '../adapters/opencode_process.mjs';

test('S3-SEC-1 multiline private sources never reach native restore or persisted handoff', async t => {
  const f = await fixture(t); const host = await f.load();
  await fs.writeFile(path.join(f.mb, 'checklist.md'), '<private>\n- [ ] CHECKLIST_PRIVATE_CANARY\n</private>\n- [ ] public remaining task\n');
  const event = request(); await host.hook('session.context', event);
  assert.doesNotMatch(event.system.map(p => p.text).join('\n'), /CHECKLIST_PRIVATE_CANARY/);
  assert.match(event.system.map(p => p.text).join('\n'), /public remaining task/);
  await host.hook('session.compaction', request());
  const handoff = await fs.readFile(path.join(f.mb, 'handoff/latest.md'), 'utf8');
  assert.doesNotMatch(handoff, /CHECKLIST_PRIVATE_CANARY/);
  assert.match(handoff, /public remaining task/);
});

test('S3-SEC-2 recent rebuilding cannot launder an outside session document through a symlink', async t => {
  const f = await fixture(t); const host = await f.load();
  const outside = path.join(f.temp, 'outside-summary.md');
  const secret = '---\nbranch: fixture\n---\n## Summary\n### Decisions\n- OUTSIDE_SESSION_CANARY\n';
  await fs.writeFile(outside, secret); await fs.mkdir(path.join(f.mb, 'session'));
  await fs.symlink(outside, path.join(f.mb, 'session/9999-12-31_2359_abcdefab.md'));
  f.histories.root = turn();
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } });
  assert.doesNotMatch(await fs.readFile(path.join(f.mb, 'session/_recent.md'), 'utf8').catch(() => ''), /OUTSIDE_SESSION_CANARY/);
  const diagnostic = request(); await host.hook('session.context', diagnostic);
  assert.match(diagnostic.system.map(p => p.text).join('\n'), /unsafe|symlink|rebuild/i);
  const restored = request('fresh'); await host.hook('session.context', restored);
  assert.doesNotMatch(restored.system.map(p => p.text).join('\n'), /OUTSIDE_SESSION_CANARY/);
  assert.equal(await fs.readFile(outside, 'utf8'), secret);
  assert((await fs.lstat(path.join(f.mb, 'session/9999-12-31_2359_abcdefab.md'))).isSymbolicLink());
});

for (const target of ['handoff', 'handoff/archive', 'handoff/latest.md']) test(`S3-SEC-3 compaction preserves outside data behind ${target} symlink`, async t => {
  const f = await fixture(t); const host = await f.load();
  const outside = path.join(f.temp, 'outside-handoff'); await fs.mkdir(outside);
  await fs.writeFile(path.join(outside, 'latest.md'), 'OUTSIDE_HANDOFF_CANARY');
  if (target !== 'handoff') await fs.mkdir(path.join(f.mb, 'handoff'));
  if (target === 'handoff/archive') await fs.writeFile(path.join(f.mb, 'handoff/latest.md'), 'previous capsule');
  await fs.symlink(target.endsWith('.md') ? path.join(outside, 'latest.md') : outside, path.join(f.mb, target));
  await host.hook('session.compaction', request());
  assert((await fs.lstat(path.join(f.mb, target))).isSymbolicLink());
  assert.equal(await fs.readFile(path.join(outside, 'latest.md'), 'utf8'), 'OUTSIDE_HANDOFF_CANARY');
  assert.deepEqual(await fs.readdir(outside), ['latest.md']);
  const restored = request(); await host.hook('session.context', restored);
  assert.match(restored.system.map(p => p.text).join('\n'), /unsafe|handoff.*skip|symlink/i);
});

test('S3-SEC-4 subagent budget refuses an outside JSON symlink before any mutation', async t => {
  const f = await fixture(t); const host = await f.load();
  const outside = path.join(f.temp, 'outside-budget.json');
  const before = JSON.stringify({ total_estimate_tokens: 10, soft_warn_tokens: 100, hard_stop_tokens: 200 });
  await fs.writeFile(outside, before); await fs.symlink(outside, path.join(f.mb, '.session-spend.json'));
  await assert.rejects(host.hook('tool.execute.before', { tool: 'subagent', input: { agent: 'mb-backend', description: 'Implement', prompt: 'Continue work' }, sessionID: 'root', id: 'budget' }), /BLOCKED/);
  assert.equal(await fs.readFile(outside, 'utf8'), before);
});

for (const kind of ['compaction', 'budget']) test(`S3-SEC-${kind === 'budget' ? 4 : 3} rejects a symlinked bank ancestor before ${kind} writes`, async t => {
  const f = await fixture(t); const host = await f.load();
  const outside = path.join(f.temp, 'outside-parent'), bank = path.join(outside, 'bank');
  await fs.mkdir(path.join(bank, 'handoff'), { recursive: true });
  const before = JSON.stringify({ total_estimate_tokens: 10, soft_warn_tokens: 100, hard_stop_tokens: 200 });
  await fs.writeFile(path.join(bank, '.session-spend.json'), before);
  await fs.writeFile(path.join(bank, 'handoff/latest.md'), 'outside capsule');
  const alias = path.join(f.temp, 'bank-parent-alias'); await fs.symlink(outside, alias);
  process.env.MB_PATH = path.join(alias, 'bank');
  if (kind === 'compaction') await host.hook('session.compaction', request());
  else await assert.rejects(host.hook('tool.execute.before', { tool: 'subagent', input: { agent: 'mb-backend', description: 'Implement', prompt: 'Continue work' }, sessionID: 'root', id: 'budget-ancestor' }), /BLOCKED/);
  assert.equal(await fs.readFile(path.join(bank, '.session-spend.json'), 'utf8'), before);
  assert.equal(await fs.readFile(path.join(bank, 'handoff/latest.md'), 'utf8'), 'outside capsule');
  assert.deepEqual(await fs.readdir(path.join(bank, 'handoff')), ['latest.md']);
});

test('S3-SEC-4 budget initialization refuses a dangling state symlink', async t => {
  const f = await fixture(t); const host = await f.load(); const outside = path.join(f.temp, 'new-outside-budget.json');
  await fs.symlink(outside, path.join(f.mb, '.session-spend.json'));
  await assert.rejects(host.hook('tool.execute.before', { tool: 'subagent', input: { agent: 'mb-backend', description: 'Implement', prompt: 'Continue work' }, sessionID: 'root', id: 'budget-init' }), /BLOCKED/);
  await assert.rejects(fs.stat(outside), /ENOENT/);
});

test('S3-SEC-5 an explicit missing pipeline cannot downgrade the selected protected policy', async t => {
  const f = await fixture(t); const host = await f.load();
  await fs.writeFile(path.join(f.mb, 'pipeline.yaml'), 'protected_paths:\n  - secret/**\n');
  process.env.MB_PIPELINE = 'missing-explicit-policy';
  await assert.rejects(host.hook('tool.execute.before', { tool: 'write', input: { path: 'secret/token.txt', content: 'safe' }, sessionID: 'root', id: 'policy' }), /BLOCKED/);
});

test('S3-SEC-6 successful helpers clean an observer-witnessed setsid descendant before returning', async t => {
  const f = await fixture(t); const controller = new AbortController();
  const runner = createRunner(f.bundle, f.cwd, controller.signal);
  const childFile = path.join(f.temp, 'escaped-success.py'), pidFile = path.join(f.temp, 'escaped-success.pid');
  const fifo = path.join(f.temp, 'observer.fifo'), witnessed = path.join(f.temp, 'observer.json');
  const realPs = execFileSync('which', ['ps'], { encoding: 'utf8' }).trim();
  const bin = path.join(f.temp, 'observer-bin'); await fs.mkdir(bin);
  // Release the parent only after the runner's real ps snapshot contains child -> parent.
  await fs.writeFile(path.join(bin, 'ps'), `#!/usr/bin/env python3
import json, os, subprocess, sys
result = subprocess.run([${JSON.stringify(realPs)}, *sys.argv[1:]], capture_output=True, text=True, check=False)
sys.stdout.write(result.stdout)
sys.stderr.write(result.stderr)
try:
    with open(${JSON.stringify(pidFile)}) as stream:
        expected = json.load(stream)
    rows = [list(map(int, line.split())) for line in result.stdout.splitlines()]
    pair = [expected['child'], expected['parent']]
    if result.returncode == 0 and pair in rows:
        fd = os.open(${JSON.stringify(fifo)}, os.O_WRONLY | os.O_NONBLOCK)
        try:
            with open(${JSON.stringify(witnessed)}, 'w') as stream:
                json.dump({'child': pair[0], 'parent': pair[1], 'row': pair}, stream)
            os.write(fd, b'observed\\n')
        finally:
            os.close(fd)
except (OSError, ValueError, KeyError):
    pass
sys.exit(result.returncode)
`, { mode: 0o755 });
  process.env.PATH = `${bin}${path.delimiter}${process.env.PATH}`;
  await fs.writeFile(childFile, 'import os, time\nos.setsid()\nprint(os.getpid(), flush=True)\ntime.sleep(60)\n');
  await fs.writeFile(path.join(f.bundle, 'adapters/success.py'), `import json, os, subprocess, sys\nos.mkfifo(${JSON.stringify(fifo)})\nchild = subprocess.Popen([sys.executable, ${JSON.stringify(childFile)}], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)\nchild_pid = int(child.stdout.readline())\nwith open(${JSON.stringify(pidFile)}, 'w') as stream:\n    json.dump({'child': child_pid, 'parent': os.getpid()}, stream)\nwith open(${JSON.stringify(fifo)}) as witness:\n    assert witness.read() == 'observed\\n'\nprint('helper completed')\n`);
  let child;
  try {
    assert.equal(await runner.run('adapters/success.py'), 'helper completed');
    const identity = JSON.parse(await fs.readFile(pidFile, 'utf8'));
    child = identity.child;
    const observation = JSON.parse(await fs.readFile(witnessed, 'utf8'));
    assert.deepEqual(observation.row, [child, identity.parent]);
    assert.throws(() => process.kill(child, 0), /ESRCH/);
  } finally {
    child ??= JSON.parse(await fs.readFile(pidFile, 'utf8').catch(() => '{}')).child;
    if (child) { try { process.kill(child, 'SIGKILL'); } catch { /* Already cleaned. */ } }
    await runner.dispose();
  }
});

for (const [language, statements, decision, next] of [
  ['English', 'Decision: Keep the native shared resolver.\nNext: Verify remaining work.', 'Keep the native shared resolver', 'Verify remaining work'],
  ['Russian', 'Решение: Сохранить общий resolver.\nОсталось: Проверить восстановление.', 'Сохранить общий resolver', 'Проверить восстановление'],
]) test(`S3-LOG-1 acknowledged explicit ${language} user facts survive a fresh session`, async t => {
  const f = await fixture(t); const host = await f.load(); const [user, answer] = turn('1', 'Acknowledged.');
  f.histories.root = [{ ...user, text: `<private>\nDecision: PRIVATE_USER_CANARY\n</private>\n${statements}` }, answer];
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } });
  const event = request('fresh'); await host.hook('session.context', event);
  const restored = event.system.map(p => p.text).join('\n');
  assert(restored.includes(decision)); assert(restored.includes(next));
  assert.doesNotMatch(restored, /PRIVATE_USER_CANARY/);
});

test('S3-LOG-2 latest decisions and unfinished work survive twelve ordinary completed turns', async t => {
  const f = await fixture(t); const host = await f.load();
  f.histories.root = Array.from({ length: 12 }, (_, i) => turn(String(i), `Changed: Ordinary completed work ${i}: ${'public detail '.repeat(30)}`)).flat();
  f.histories.root.push(...turn('final', 'Decision: FINAL_DECISION_CANARY keep the shared boundary.\nNext: FINAL_OPEN_WORK_CANARY verify the last case.'));
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } });
  const event = request('fresh'); await host.hook('session.context', event);
  const text = event.system.map(p => p.text).join('\n');
  assert.match(text, /FINAL_DECISION_CANARY/); assert.match(text, /FINAL_OPEN_WORK_CANARY/);
});

test('S3-LOG-3 one completed patch syncs every unique plan and finalizes the shared chain once', async t => {
  const f = await fixture(t); const host = await f.load();
  await fs.mkdir(path.join(f.mb, 'plans')); await fs.writeFile(path.join(f.mb, 'roadmap.md'), '# Roadmap\n');
  const files = ['2026-10-16_feature_first.md', '2026-10-16_feature_second.md'].map(name => path.join(f.mb, 'plans', name));
  for (const file of files) await fs.writeFile(file, `---\nstatus: in_progress\n---\n# ${path.basename(file)}\n<!-- mb-stage:1 -->\n### Stage 1: Work\n- [ ] Verify\n`);
  const receipt = path.join(f.temp, 'sync-receipt');
  for (const relative of ['hooks/mb-plan-sync-post-write.sh', 'scripts/mb-roadmap-sync.sh', 'scripts/mb-traceability-gen.sh']) {
    const original = path.join(f.bundle, relative), saved = original.replace('.sh', '.real.sh');
    await fs.rename(original, saved);
    await fs.writeFile(original, `#!/bin/bash\nprintf '%s\\n' '${relative}' >> '${receipt}'\nexec bash '${saved}' "$@"\n`, { mode: 0o755 });
  }
  const patchText = `*** Begin Patch\n${[...files, files[0]].map(file => `*** Update File: ${file}\n@@\n-old\n+new`).join('\n')}\n*** End Patch`;
  const event = { tool: 'patch', input: { patchText }, sessionID: 'root', id: 'multi-plan', status: 'completed' };
  await host.hook('tool.execute.after', event);
  const checklist = await fs.readFile(path.join(f.mb, 'checklist.md'), 'utf8');
  for (const file of files) assert(checklist.includes(`mb-plan:${path.basename(file)}`));
  const before = await fs.readFile(receipt, 'utf8');
  assert.deepEqual(before.trim().split('\n'), ['hooks/mb-plan-sync-post-write.sh', 'scripts/mb-roadmap-sync.sh', 'scripts/mb-traceability-gen.sh']);
  await host.hook('tool.execute.after', event);
  assert.equal(await fs.readFile(receipt, 'utf8'), before);
});
