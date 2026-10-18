import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { fixture, request, turn } from './opencode_fixture.mjs';

test('completed work is private, structured, deduplicated and restored after reload', async t => {
  const f = await fixture(t);
  let host = await f.load();
  await host.hook('session.prompt', { sessionID: 'root', messageID: 'u1', prompt: { text: 'not complete' } });
  await host.hook('session.prompt', { sessionID: 'root', messageID: 'u1', prompt: { text: 'not complete' } });
  assert.deepEqual(await f.records(), []);
  f.histories.root = turn('1', 'Changed: Native capture works.\nDecision: Keep the shared resolver.\nNext: Verify restart.\n<private>PRIVACY_CANARY</private> API_KEY=sk-abcdefghijklmnopqrstuvwxyz12345');
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } });
  const names = await f.records();
  assert.equal(names.length, 1);
  const file = path.join(f.mb, 'session', names[0]);
  const content = await fs.readFile(file, 'utf8');
  assert.match(content, /^summary_schema: v2$/m);
  assert.match(content, /^last_turn: a1$/m);
  assert.match(content, /^turns: 1$/m);
  assert.match(content, /### Decisions\n- .*Keep the shared resolver/);
  assert.match(content, /### Open questions\n- .*Verify restart/);
  assert.match(content, /### Files\n- src\/native.py/);
  assert.doesNotMatch(content, /PRIVACY_CANARY|abcdefghijklmnopqrstuvwxyz12345/);
  assert.equal((await fs.stat(file)).mode & 0o777, 0o600);
  assert.equal((await fs.stat(path.join(f.mb, 'session/_recent.md'))).mode & 0o777, 0o600);
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } });
  assert.equal(await fs.readFile(file, 'utf8'), content);
  await host.dispose(); host = await f.load();
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } });
  assert.equal(await fs.readFile(file, 'utf8'), content);
  process.env.MB_SESSION_CAPTURE = 'off';
  const event = request('fresh');
  await host.hook('session.context', event);
  const restored = event.system.map(p => p.text).join('\n');
  assert.match(restored, /Keep the shared resolver|Verify restart/);
  assert.match(restored, /Current task: verify the native boundary/);
  assert.doesNotMatch(restored, /PRIVACY_CANARY|abcdefghijklmnopqrstuvwxyz12345/);
});

for (const [name, env, expected] of /** @type {[string, Record<string, string>, boolean][]} */ ([
  ['capture off', { MB_SESSION_CAPTURE: 'off' }, false],
  ['legacy stub off', { MB_AUTO_CAPTURE: 'off' }, true],
  ['legacy strict', { MB_AUTO_CAPTURE: 'strict' }, true],
  ['autoload off', { MB_AUTOLOAD_CONTEXT: 'off' }, true],
])) test(`independent switches: ${name}`, async t => {
  const f = await fixture(t); Object.assign(process.env, env);
  f.histories.root = turn(); const host = await f.load();
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } });
  assert.equal((await f.records()).length > 0, expected);
  if (env.MB_AUTO_CAPTURE) assert.doesNotMatch(await fs.readFile(path.join(f.mb, 'progress.md'), 'utf8'), /Auto-capture/);
});

test('base variant adds no completed-turn capture or restore automation', async t => {
  const f = await fixture(t, { extended: false }); f.histories.root = turn();
  const host = await f.load(); const event = request();
  await host.hook('session.context', event);
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } });
  assert.deepEqual(await f.records(), []);
  assert(!f.calls.some(([kind]) => kind === 'context'));
});

test('children, foreign locations and deleted identities cannot capture or hand off the parent', async t => {
  const f = await fixture(t); const host = await f.load();
  f.sessions.child = { id: 'child', parentID: 'root', location: { directory: f.cwd } };
  f.sessions.foreign = { id: 'foreign', location: { directory: f.temp } };
  for (const id of ['child', 'foreign']) {
    f.histories[id] = turn();
    await host.emit('session.status', { sessionID: id, status: { type: 'idle' } });
    await host.hook('session.compaction', request(id));
  }
  f.histories.root = turn();
  await host.hook('session.context', request());
  const before = await fs.readFile(path.join(f.mb, 'progress.md'), 'utf8');
  f.sessions.root = new Error('deleted');
  await host.emit('session.deleted', { sessionID: 'root' });
  assert.equal(await fs.readFile(path.join(f.mb, 'progress.md'), 'utf8'), before);
  assert.deepEqual(await f.records(), []);
  await assert.rejects(fs.stat(path.join(f.mb, 'handoff/latest.md')), /ENOENT/);
});

test('bank created after startup is resolved without initializing absent memory', async t => {
  const f = await fixture(t, { bank: false }); const host = await f.load();
  await host.hook('session.context', request());
  await assert.rejects(fs.stat(f.mb), /ENOENT/);
  await fs.mkdir(f.mb); await fs.writeFile(path.join(f.mb, 'progress.md'), '# Progress\n');
  f.histories.root = turn();
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } });
  assert.equal((await f.records()).length, 1);
});

test('global MB_PATH capture never writes a second local session store', async t => {
  const f = await fixture(t); const global = path.join(f.temp, 'global bank');
  await fs.mkdir(global); process.env.MB_PATH = global;
  const host = await f.load(); f.histories.root = turn();
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } });
  assert((await fs.readdir(path.join(global, 'session'))).some(p => p.endsWith('.md')));
  assert.deepEqual(await f.records(), []);
});

test('failed capture preserves prior data and retries the uncommitted turn', async t => {
  const f = await fixture(t); const host = await f.load();
  await fs.writeFile(path.join(f.mb, 'session'), 'existing user data'); f.histories.root = turn();
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } });
  assert.equal(await fs.readFile(path.join(f.mb, 'session'), 'utf8'), 'existing user data');
  await fs.unlink(path.join(f.mb, 'session'));
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } });
  assert.equal((await f.records()).length, 1);
});

test('compaction persists structured work and calls the real shared handoff hook', async t => {
  const f = await fixture(t); f.histories.root = turn();
  const host = await f.load(); await host.hook('session.compaction', request());
  assert.equal((await f.records()).length, 1);
  assert.match(await fs.readFile(path.join(f.mb, 'handoff/latest.md'), 'utf8'), /handoff|Handoff|Memory Bank/);
  assert.equal((await fs.stat(path.join(f.mb, 'handoff/latest.md'))).mode & 0o777, 0o600);
  process.env.MB_PRECOMPACT_HANDOFF = 'off';
  const before = await fs.readFile(path.join(f.mb, 'handoff/latest.md'), 'utf8');
  await host.hook('session.compaction', request());
  assert.equal(await fs.readFile(path.join(f.mb, 'handoff/latest.md'), 'utf8'), before);
});

test('completed capture includes changed files and tools from preceding native tool steps', async t => {
  const f = await fixture(t); const host = await f.load();
  const [user, answer] = turn();
  f.histories.root = [user, { ...answer, id: 'tool-step', finish: 'tool-calls',
    content: [{ type: 'text', text: 'Decision: Use the existing shared port.' }, { type: 'tool', name: 'write', state: { status: 'completed', input: { path: 'src/earlier.py' }, content: [{ type: 'text', text: 'TOOL_BODY_CANARY' }] } }],
    snapshot: undefined,
  }, { ...answer, snapshot: undefined }];
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } });
  const text = await fs.readFile(path.join(f.mb, 'session', (await f.records())[0]), 'utf8');
  assert.match(text, /### Files\n- src\/earlier.py/);
  assert.match(text, /tools: write/);
  assert.match(text, /Use the existing shared port/);
  assert.doesNotMatch(text, /TOOL_BODY_CANARY/);
});

test('a location move during reconciliation cannot append a stub or hand off the old bank', async t => {
  const f = await fixture(t); const host = await f.load();
  Object.defineProperty(f.histories, 'root', { get() {
    f.sessions.root = { id: 'root', location: { directory: f.temp } };
    return turn();
  } });
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } });
  assert.equal(await fs.readFile(path.join(f.mb, 'progress.md'), 'utf8'), '# Progress\n');
  assert.deepEqual(await f.records(), []);
  delete f.sessions.root;
  await host.hook('session.compaction', request());
  await assert.rejects(fs.stat(path.join(f.mb, 'handoff/latest.md')), /ENOENT/);
});

test('restore never follows credential symlinks in recent or handoff files', async t => {
  const f = await fixture(t); const host = await f.load();
  const secret = path.join(f.temp, 'fixture-credentials');
  await fs.writeFile(secret, 'RAW_CREDENTIAL_CANARY');
  await fs.mkdir(path.join(f.mb, 'handoff')); await fs.symlink(secret, path.join(f.mb, 'handoff/latest.md'));
  await fs.mkdir(path.join(f.temp, 'outside-session')); await fs.writeFile(path.join(f.temp, 'outside-session/_recent.md'), 'RAW_CREDENTIAL_CANARY');
  await fs.symlink(path.join(f.temp, 'outside-session'), path.join(f.mb, 'session'));
  const event = request(); await host.hook('session.context', event);
  assert.doesNotMatch(event.system.map(p => p.text).join('\n'), /RAW_CREDENTIAL_CANARY/);
  process.env.MB_SEMANTIC = 'auto';
  const notes = path.join(f.temp, 'outside-notes'); await fs.mkdir(notes);
  await fs.writeFile(path.join(notes, 'credentials.md'), '# RAW_CREDENTIAL_CANARY native resolver boundary decision\n');
  await fs.symlink(notes, path.join(f.mb, 'notes'));
  await host.hook('session.prompt', { sessionID: 'root', messageID: 'q1', prompt: { text: 'native resolver boundary decision' } });
  const recalled = request(); await host.hook('session.context', recalled);
  assert.doesNotMatch(recalled.system.map(p => p.text).join('\n'), /RAW_CREDENTIAL_CANARY/);
});

test('automatic recall is filtered, read-only and replaced on each prompt', async t => {
  const f = await fixture(t); const host = await f.load();
  process.env.MB_SEMANTIC = 'auto'; process.env.MB_SEMANTIC_BACKEND = 'bm25';
  await fs.mkdir(path.join(f.mb, 'notes'));
  await fs.writeFile(path.join(f.mb, 'notes/decision.md'), '# native resolver stability decision\nDecision: Keep the shared resolver.\n<private>RECALL_CANARY</private> API_KEY=sk-abcdefghijklmnopqrstuvwxyz12345\n');
  await host.hook('session.prompt', { sessionID: 'root', messageID: 'q1', prompt: { text: 'Recall the native resolver stability decision and remaining verification work.' } });
  const event = request(); await host.hook('session.context', event);
  assert.match(event.system.map(p => p.text).join('\n'), /native resolver stability decision/);
  assert.match(event.system.map(p => p.text).join('\n'), /Keep the shared resolver/);
  assert.doesNotMatch(event.system.map(p => p.text).join('\n'), /RECALL_CANARY|abcdefghijklmnopqrstuvwxyz12345/);
  await assert.rejects(fs.stat(path.join(f.mb, '.index')), /ENOENT/);
  await host.hook('session.prompt', { sessionID: 'root', messageID: 'q2', prompt: { text: '/mb' } });
  const next = request(); await host.hook('session.context', next);
  assert.doesNotMatch(next.system.map(p => p.text).join('\n'), /native resolver stability decision/);
});

test('shared global registry stays authoritative when native XDG config differs', async t => {
  const f = await fixture(t, { bank: false }); const global = path.join(f.temp, 'global-bank');
  await fs.mkdir(global); const registry = path.join(f.temp, '.config/opencode/memory-bank');
  await fs.mkdir(registry, { recursive: true });
  await fs.writeFile(path.join(registry, 'registry.json'), JSON.stringify({ projects: { [await fs.realpath(f.cwd)]: { bank_path: global } } }));
  process.env.XDG_CONFIG_HOME = path.join(f.temp, 'native-config');
  const host = await f.load(); f.histories.root = turn();
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } });
  assert((await fs.readdir(path.join(global, 'session'))).some(p => p.endsWith('.md')));
  await assert.rejects(fs.stat(f.mb), /ENOENT/);
  await assert.rejects(fs.stat(path.join(process.env.XDG_CONFIG_HOME, 'opencode/memory-bank/registry.json')), /ENOENT/);
});

test('optional restore or recall failures do not block ordinary native work', async t => {
  const f = await fixture(t); const host = await f.load(); process.env.MB_SEMANTIC = 'auto';
  await fs.unlink(path.join(f.bundle, 'hooks/mb-session-start-context.sh'));
  await fs.unlink(path.join(f.bundle, 'adapters/opencode_memory.py'));
  await host.hook('session.prompt', { sessionID: 'root', messageID: 'q1', prompt: { text: 'Find prior decisions about the native resolver' } });
  const event = request(); await host.hook('session.context', event);
  assert(event.system.some(p => p.text.includes('subagent(')));
  await host.hook('tool.execute.before', { tool: 'shell', input: { command: 'printf safe' }, sessionID: 'root', id: 'safe' });
});

test('a completed tool-only turn retains changed files without storing raw tool output', async t => {
  const f = await fixture(t); const host = await f.load(); const [user, answer] = turn();
  f.histories.root = [user, { ...answer, id: 'step', finish: 'tool-calls', content: [
    { type: 'tool', name: 'write', state: { status: 'completed', input: { path: 'created.py' }, content: [{ type: 'text', text: 'RAW_TOOL_CANARY' }] } },
  ], snapshot: undefined }, { ...answer, content: [], snapshot: undefined }];
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } });
  assert.equal((await f.records()).length, 1);
  const text = await fs.readFile(path.join(f.mb, 'session', (await f.records())[0]), 'utf8');
  assert.match(text, /created\.py/); assert.match(text, /turns: 1/);
  assert.doesNotMatch(text, /RAW_TOOL_CANARY/);
});

test('workspace events and actual session identity reject foreign scope', async t => {
  const f = await fixture(t); const host = await f.load({ workspaceID: 'current' });
  f.histories.root = turn();
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } }, { directory: f.cwd, workspaceID: 'foreign' });
  assert.deepEqual(await f.records(), []);
  f.sessions.root = { id: 'root', projectID: 'foreign', location: { directory: f.cwd, workspaceID: 'current' } };
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } }, { directory: f.cwd, workspaceID: 'current' });
  assert.deepEqual(await f.records(), []);
  f.sessions.root = { id: 'root', location: { directory: f.cwd, workspaceID: 'current' } };
  await host.emit('session.status', { sessionID: 'root', status: { type: 'idle' } }, { directory: f.cwd, workspaceID: 'current' });
  assert.equal((await f.records()).length, 1);
});

test('native execution success reconciles only the current root and stays idempotent with legacy idle', async t => {
  const f = await fixture(t); const host = await f.load();
  f.histories.root = turn('native', 'Decision: Keep the native success boundary.');
  f.sessions.child = { id: 'child', parentID: 'root', location: { directory: f.cwd } };
  f.histories.child = turn('child');
  await host.emit('session.execution.succeeded', { sessionID: 'child' });
  await host.emit('session.execution.succeeded', { sessionID: 'root' }, { directory: f.temp });
  await host.emit('session.execution.succeeded', { sessionID: 'root' }, { directory: f.cwd, workspaceID: 'foreign' });
  assert.deepEqual(await f.records(), []);
  // Actual V2 success carries only sessionID, without a location envelope.
  await host.emit('session.execution.succeeded', { sessionID: 'root' });
  const names = await f.records();
  assert.equal(names.length, 1);
  const file = path.join(f.mb, 'session', names[0]);
  const saved = await fs.readFile(file, 'utf8');
  assert.match(saved, /Keep the native success boundary/);
  await host.emit('session.execution.succeeded', { sessionID: 'root' });
  await host.emit('session.idle', { sessionID: 'root' });
  assert.equal(await fs.readFile(file, 'utf8'), saved);
  const progress = await fs.readFile(path.join(f.mb, 'progress.md'), 'utf8');
  Object.defineProperty(f.histories, 'root', { get() {
    f.sessions.root = { id: 'root', location: { directory: f.temp } };
    return turn('moved');
  } });
  await host.emit('session.execution.succeeded', { sessionID: 'root' });
  assert.equal(await fs.readFile(file, 'utf8'), saved);
  assert.equal(await fs.readFile(path.join(f.mb, 'progress.md'), 'utf8'), progress);
});

test('configured workspace accepts locationless native success only for its verified root', async t => {
  const f = await fixture(t); const host = await f.load({ workspaceID: 'current' });
  const owned = { id: 'root', projectID: 'fixture', location: { directory: f.cwd, workspaceID: 'current' } };
  f.sessions.root = owned;
  f.histories.root = turn('configured', 'Decision: Keep the configured workspace boundary.');
  f.sessions.child = { ...owned, id: 'child', parentID: 'root' };
  f.sessions.foreign = { ...owned, id: 'foreign', location: { directory: f.cwd, workspaceID: 'other' } };
  f.histories.child = turn('child');
  f.histories.foreign = turn('foreign');
  await host.emit('session.execution.succeeded', { sessionID: 'child' });
  await host.emit('session.execution.succeeded', { sessionID: 'foreign' });
  await host.emit('session.execution.succeeded', { sessionID: 'root' }, { directory: f.cwd, workspaceID: 'foreign' });
  f.sessions.root = { ...owned, projectID: 'foreign' };
  await host.emit('session.execution.succeeded', { sessionID: 'root' });
  f.sessions.root = { ...owned, location: { directory: f.cwd } };
  await host.emit('session.execution.succeeded', { sessionID: 'root' });
  assert.deepEqual(await f.records(), []);
  assert.equal(await fs.readFile(path.join(f.mb, 'progress.md'), 'utf8'), '# Progress\n');
  f.sessions.root = owned;
  await host.emit('session.execution.succeeded', { sessionID: 'root' });
  const names = await f.records();
  assert.equal(names.length, 1);
  const file = path.join(f.mb, 'session', names[0]);
  const saved = await fs.readFile(file, 'utf8');
  assert.match(saved, /Keep the configured workspace boundary/);
  await host.emit('session.execution.succeeded', { sessionID: 'root' });
  assert.equal((await f.records()).length, 1);
  assert.equal(await fs.readFile(file, 'utf8'), saved);
  const progress = await fs.readFile(path.join(f.mb, 'progress.md'), 'utf8');
  Object.defineProperty(f.histories, 'root', { get() {
    f.sessions.root = { ...owned, location: { directory: f.cwd, workspaceID: 'other' } };
    return turn('moved');
  } });
  await host.emit('session.execution.succeeded', { sessionID: 'root' });
  assert.equal(await fs.readFile(file, 'utf8'), saved);
  assert.equal(await fs.readFile(path.join(f.mb, 'progress.md'), 'utf8'), progress);
});
