# shellcheck shell=bash
# Native V2 boundary fixture: no service, credentials, model, or SDK dependency.
v2_node() {
  local script="$BATS_TEST_TMPDIR/native-contract.mjs"
  local fixture_runtime="" fixture_bundle=""
  # Replace external helpers inside a private bundle, never teach production an
  # arbitrary executable-path seam for update notices or instruction libraries.
  if [ -n "${MB_UPDATE_NOTIFY_BIN:-}${MB_AGENTS_LIB:-}" ]; then
    fixture_bundle="$(mktemp -d "$BATS_TEST_TMPDIR/runtime.XXXXXX")"
    cp -R "$REPO_ROOT/adapters" "$REPO_ROOT/hooks" "$REPO_ROOT/scripts" \
      "$REPO_ROOT/memory_bank_skill" "$REPO_ROOT/references" "$REPO_ROOT/rules" "$fixture_bundle/"
    cp "$REPO_ROOT/SKILL.md" "$REPO_ROOT/VERSION" "$fixture_bundle/"
    if [ -n "${MB_UPDATE_NOTIFY_BIN:-}" ]; then
      if [ -f "$MB_UPDATE_NOTIFY_BIN" ]; then cp "$MB_UPDATE_NOTIFY_BIN" "$fixture_bundle/hooks/mb-update-notify.sh"
      else rm -f "$fixture_bundle/hooks/mb-update-notify.sh"; fi
    fi
    if [ -n "${MB_AGENTS_LIB:-}" ]; then
      if [ -f "$MB_AGENTS_LIB" ]; then cp "$MB_AGENTS_LIB" "$fixture_bundle/adapters/_lib_agents_md.sh"
      else rm -f "$fixture_bundle/adapters/_lib_agents_md.sh"; fi
    fi
    fixture_runtime="$fixture_bundle/adapters/opencode_plugin.mjs"
  fi
  cat > "$script" <<'JS'
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { pathToFileURL } from 'node:url';
const directory = process.env.PROJECT;
async function loadV2(sessions = {}, history = {}) {
  const file = path.join(directory, '.opencode/plugins/memory-bank.js');
  const copy = path.join(directory, 'plugin-under-test.mjs');
  let bootstrap = fs.readFileSync(file, 'utf8');
  if (process.env.MB_V2_FIXTURE_RUNTIME) bootstrap = bootstrap.replace(/from "[^"]+"/, `from ${JSON.stringify(pathToFileURL(process.env.MB_V2_FIXTURE_RUNTIME).href)}`);
  fs.writeFileSync(copy, bootstrap);
  const definition = (await import(pathToFileURL(copy))).default;
  assert.equal(typeof definition, 'object', 'V2 needs a default definition, not a V1 function');
  assert.equal(definition.id, 'memory-bank');
  const hooks = new Map();
  let pending, previous, signal;
  const events = [];
  const register = (domain) => async (name, callback) => {
    const key = `${domain}.${name}`;
    assert(!hooks.has(key), `duplicate hook: ${key}`);
    hooks.set(key, callback);
    return { async dispose() { hooks.delete(key); } };
  };
  const cleanup = await definition.setup({
    location: { directory, project: { id: 'fixture', directory, canonical: directory } },
    session: {
      hook: register('session'),
      async get({ sessionID }) {
        return { projectID: 'fixture', ...(sessions[sessionID] ?? { id: sessionID, location: { directory } }) };
      },
      async context({ sessionID }, options) {
        assert(options?.signal instanceof AbortSignal);
        return structuredClone(history[sessionID] ?? []);
      },
    },
    tool: { hook: register('tool') },
    event: { subscribe(options) {
      signal = options.signal;
      return { [Symbol.asyncIterator]() { return this; }, next() {
        previous?.();
        previous = undefined;
        if (signal.aborted) return Promise.resolve({ done: true });
        return new Promise((resolve) => {
          const deliver = () => {
            const item = events.shift();
            previous = item.done;
            resolve({ value: item.event, done: false });
          };
          if (events.length) deliver();
          else pending = deliver;
          signal.addEventListener('abort', () => resolve({ done: true }), { once: true });
        });
      } };
    } },
  });
  return {
    hooks,
    async hook(name, event) {
      assert(hooks.has(name), `missing native hook: ${name}`);
      await hooks.get(name)(event);
    },
    async emit(type, data) {
      await new Promise((done) => {
        events.push({ event: { type, data }, done });
        const deliver = pending;
        pending = undefined;
        deliver?.();
      });
    },
    async dispose() {
      await cleanup();
      assert(signal.aborted, 'event stream must be aborted');
      assert.equal(hooks.size, 0, 'registrations must be disposed');
    },
  };
}
function request(sessionID = 'root') {
  return { sessionID, agent: 'mb-backend', system: [], messages: [], options: {}, tools: {} };
}
function completedTurn(userID, answerID, text, answer = 'What changed: Request handled.\nDecision: Keep the shared implementation.\nNext: Verify the remaining work.') {
  return [
    { id: userID, type: 'user', text, time: { created: 1 } },
    { id: answerID, type: 'assistant', content: [{ type: 'text', text: answer }], time: { created: 2, completed: 3 }, finish: 'stop', snapshot: { files: ['src/example.py'] } },
  ];
}
JS
  cat >> "$script"
  PROJECT="$PROJECT" MB_V2_FIXTURE_RUNTIME="$fixture_runtime" node "$script"
}
