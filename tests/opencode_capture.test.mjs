import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { fixture, turn } from './opencode_fixture.mjs';

test('snapshot-free native write and edit retain completed file evidence without tool bodies', async t => {
  const f = await fixture(t); const host = await f.load(); const [user, answer] = turn();
  f.histories.root = [user, { ...answer, snapshot: undefined, content: [
    { type: 'reasoning', text: 'PRIVATE_REASONING_NOT_MEMORY' },
    { type: 'tool', id: 'write', name: 'write', time: { created: 1, completed: 2 }, state: {
      status: 'completed', input: { path: 'src/created.py', content: 'INPUT_BODY_NOT_MEMORY' },
      content: [{ type: 'text', text: 'OUTPUT_BODY_NOT_MEMORY' }],
    } },
    { type: 'tool', id: 'edit', name: 'edit', time: { created: 2, completed: 3 }, state: {
      status: 'completed', input: { path: 'src/edited.py', oldString: 'old', newString: 'NEW_BODY_NOT_MEMORY' },
      content: [{ type: 'text', text: 'OUTPUT_BODY_NOT_MEMORY' }],
      metadata: { files: [{ file: 'src/edited.py', status: 'modified', patch: 'PATCH_BODY_NOT_MEMORY', additions: 1, deletions: 1 }] },
    } },
    { type: 'text', text: 'Decision: Keep actual native tool evidence.\n<private>PRIVATE_TEXT_NOT_MEMORY</private> API_KEY=sk-abcdefghijklmnopqrstuvwxyz12345' },
  ] }];
  await host.emit('session.execution.succeeded', { sessionID: 'root' });
  const names = await f.records(); assert.equal(names.length, 1);
  const text = await fs.readFile(path.join(f.mb, 'session', names[0]), 'utf8');
  assert.match(text, /### Files\n- src\/created.py\n- src\/edited.py/);
  assert.match(text, /tools: write, edit/); assert.match(text, /Keep actual native tool evidence/);
  assert.doesNotMatch(text, /(?:INPUT|OUTPUT|NEW|PATCH)_BODY_NOT_MEMORY|PRIVATE_(?:REASONING|TEXT)_NOT_MEMORY|abcdefghijklmnopqrstuvwxyz12345/);
});

test('native terminal tool-only turn without snapshot or assistant text persists once', async t => {
  const f = await fixture(t); const host = await f.load(); const [user, answer] = turn();
  f.histories.root = [user, { ...answer, snapshot: undefined, content: [
    { type: 'tool', id: 'write', name: 'write', time: { created: 1, completed: 2 }, state: {
      status: 'completed', input: { path: 'tool-only.py', content: 'RAW_INPUT_NOT_MEMORY' },
      content: [{ type: 'text', text: 'RAW_OUTPUT_NOT_MEMORY' }],
    } },
  ] }];
  await host.emit('session.execution.succeeded', { sessionID: 'root' });
  const names = await f.records(); assert.equal(names.length, 1);
  const file = path.join(f.mb, 'session', names[0]); const saved = await fs.readFile(file, 'utf8');
  assert.match(saved, /turns: 1\n/); assert.match(saved, /### Files\n- tool-only.py/);
  assert.match(saved, /tools: write/); assert.match(saved, /no public assistant text; native turn ended/);
  assert.doesNotMatch(saved, /RAW_(?:INPUT|OUTPUT)_NOT_MEMORY/);
  await host.emit('session.execution.succeeded', { sessionID: 'root' });
  assert.equal(await fs.readFile(file, 'utf8'), saved);
});

test('native failed and pending writes record errors without claiming changed files', async t => {
  const f = await fixture(t); const host = await f.load(); const [user, answer] = turn();
  f.histories.root = [user, { ...answer, snapshot: undefined, content: [
    { type: 'tool', id: 'failed', name: 'write', time: { created: 1, completed: 2 }, state: {
      status: 'error', input: { path: 'failed.py', content: 'FAILED_INPUT_NOT_MEMORY' },
      error: { type: 'blocked', message: 'ERROR_BODY_NOT_MEMORY', response: { body: 'RESPONSE_NOT_MEMORY' } },
      metadata: { files: [{ file: 'failed.py', status: 'added' }] },
    } },
    { type: 'tool', id: 'pending', name: 'edit', time: { created: 1 }, state: {
      status: 'running', input: { path: 'pending.py' }, metadata: { files: [{ file: 'pending.py', status: 'modified' }] },
    } },
    { type: 'tool', id: 'streaming', name: 'write', time: { created: 1 }, state: { status: 'streaming', input: 'STREAMING_NOT_MEMORY' } },
  ] }];
  await host.emit('session.execution.succeeded', { sessionID: 'root' });
  const names = await f.records(); assert.equal(names.length, 1);
  const text = await fs.readFile(path.join(f.mb, 'session', names[0]), 'utf8');
  assert.match(text, /err\(1\)/); assert.match(text, /tools: write/);
  assert.match(text, /### Files\n- \(none\)/);
  assert.doesNotMatch(text, /failed.py|pending.py|(?:FAILED_INPUT|ERROR_BODY|RESPONSE|STREAMING)_NOT_MEMORY/);
});

test('completed native multi-file metadata excludes credential paths and keeps facts within each user turn', async t => {
  const f = await fixture(t); const host = await f.load(); const [user, answer] = turn();
  const [nextUser, nextAnswer] = turn('next', 'Decision: Keep later work separate.');
  f.histories.root = [user, { ...answer, snapshot: undefined, content: [
    { type: 'tool', id: 'edit', name: 'edit', time: { created: 1, completed: 2 }, state: {
      status: 'completed', input: { path: 'first.py', oldString: 'old', newString: 'new' },
      content: [{ type: 'text', text: 'PATCH_BODY_NOT_MEMORY' }], metadata: { files: [
        { file: 'first.py', status: 'modified' }, { file: 'second.py', status: 'added' },
        { file: '.env.local', status: 'modified' }, { file: 'credentials.json', status: 'modified' },
        { file: '<private>PRIVATE_FILENAME_NOT_MEMORY</private>', status: 'added' },
      ] },
    } },
  ] }, nextUser, { ...nextAnswer, snapshot: undefined }];
  await host.emit('session.execution.succeeded', { sessionID: 'root' });
  const text = await fs.readFile(path.join(f.mb, 'session', (await f.records())[0]), 'utf8');
  assert.match(text, /turns: 2\n/); assert.match(text, /### Files\n- first.py\n- second.py/);
  const logs = text.split('## Live log\n')[1].split('\n## Summary')[0].trim().split('\n');
  assert.equal(logs.length, 2); assert.match(logs[1], /tools: \(none\) · files: \(none\) · ok/);
  assert.doesNotMatch(text, /\.env.local|credentials.json|PRIVATE_FILENAME_NOT_MEMORY|PATCH_BODY_NOT_MEMORY/);
});
