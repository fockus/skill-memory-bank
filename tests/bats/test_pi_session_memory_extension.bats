#!/usr/bin/env bats
# Runtime harness for adapters/pi_session_memory_extension.ts (adapter-parity T3,
# REQ-006/007/010/013/019). Node's --experimental-strip-types (Node >=22.6) lets us
# load the REAL installed .ts artifact directly (via a fake `pi` object mirroring
# ExtensionAPI's `.on(event, handler)` contract) — no fabricated JS mirror, no
# separate transpile step, mirroring the existing opencode B4 functional-test
# pattern (test_opencode_adapter.bats) for a host whose extension is TypeScript.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PROJECT="$(mktemp -d)"
  mkdir -p "$PROJECT/.memory-bank"
  SANDBOX_HOME="$(mktemp -d)"
  export HOME="$SANDBOX_HOME"
  command -v jq >/dev/null || skip "jq required"
  command -v node >/dev/null || skip "node required"
  # Feature-detect rather than version-sniff: some Node 22.x builds ship the
  # flag, older ones don't, and it's unflagged-default from Node 23.6 — a
  # runtime probe is honest on every LTS/CI combination.
  node --experimental-strip-types -e '' >/dev/null 2>&1 || skip "node --experimental-strip-types not supported (need Node >=22.6)"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
  [ -n "${SANDBOX_HOME:-}" ] && [ -d "$SANDBOX_HOME" ] && rm -rf "$SANDBOX_HOME"
}

# Installs both parity extensions into the sandboxed global Pi extensions dir
# and exports EXT = the absolute path of the installed session-memory .ts.
_install_global_session_ext() {
  run bash "$REPO_ROOT/adapters/pi.sh" install-global-extensions "$PROJECT"
  [ "$status" -eq 0 ]
  EXT="$SANDBOX_HOME/.pi/agent/extensions/memory-bank-session.ts"
  [ -f "$EXT" ]
}

# ═══════════════════════════════════════════════════════════════
# Scenario 2 (REQ-006/007): accepted Pi offer revives session memory —
# same v2 schema fields as a Claude Code capture (hooks/mb-session-turn.sh).
# ═══════════════════════════════════════════════════════════════

@test "pi session-memory extension: a simulated turn writes session/*.md with the CC v2 schema fields" {
  _install_global_session_ext

  local harness="$PROJECT/harness-turn.mjs"
  cat > "$harness" <<'EOF'
const [, , extPath, projectRoot] = process.argv;
const handlers = {};
const fakePi = { on: (name, fn) => { handlers[name] = fn; } };
const mod = await import(extPath);
mod.default(fakePi);
const ctx = {
  cwd: projectRoot,
  sessionManager: { getSessionFile: () => "pi-harness-session-abcdef" },
  ui: { notify: () => {} },
};
await handlers.session_start({}, ctx);
await handlers.input({ text: "fix the flaky upload test" }, ctx);
await handlers.tool_execution_end({ toolName: "Edit", isError: false }, ctx);
await handlers.agent_end({}, ctx);
await handlers.session_before_compact({ reason: "threshold" }, ctx);
await handlers.session_shutdown({}, ctx);
console.log("HARNESS_OK");
EOF

  run env MB_SESSION_CAPTURE=auto MB_UPDATE_CHECK=off node --experimental-strip-types "$harness" "$EXT" "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"HARNESS_OK"* ]]

  local sf=""
  for f in "$PROJECT/.memory-bank/session"/*.md; do
    [ -f "$f" ] && sf="$f"
  done
  [ -n "$sf" ]

  # Same v2 schema fields as hooks/mb-session-turn.sh's Claude Code capture
  # (session_id/transcript/started/branch/turns/last_turn/summarized), plus
  # the host marker + summary_schema.
  grep -q "^session_id: pi-harness-session-abcdef$" "$sf"
  grep -q "^transcript: pi-harness-session-abcdef$" "$sf"
  grep -q "^agent: pi$" "$sf"
  grep -q "^started: " "$sf"
  grep -q "^branch: " "$sf"
  grep -q "^turns: 1$" "$sf"
  grep -q "^last_turn: pi-turn-1$" "$sf"
  grep -q "^summarized: false$" "$sf"
  grep -q "^summary_schema: v2$" "$sf"

  # Content: user turn, tool outcome, turn/compaction/shutdown bookkeeping.
  grep -q 'fix the flaky upload test' "$sf"
  grep -q "Tools: Edit" "$sf"
  grep -q "Turn 1: completed" "$sf"
  grep -q "## Handoff capsule" "$sf"
  grep -q "^ended: " "$sf"
}

# ═══════════════════════════════════════════════════════════════
# Scenario 4 (REQ-013): update-notify reaches a Pi user on session_start.
# ═══════════════════════════════════════════════════════════════

@test "pi session-memory extension: session_start renders the update-notice via ctx.ui.notify" {
  _install_global_session_ext

  local checker="$PROJECT/fake-checker.sh"
  cat > "$checker" <<'EOF'
#!/usr/bin/env bash
echo '{"current":"5.3.0","latest":"9.9.9","update_available":true,"flavor":"git","upgrade_command":"bash /tmp/x/scripts/mb-upgrade.sh","checked_at":"x","source":"github"}'
EOF
  chmod +x "$checker"

  local harness="$PROJECT/harness-notice.mjs"
  cat > "$harness" <<'EOF'
const [, , extPath, projectRoot] = process.argv;
const notices = [];
const handlers = {};
const fakePi = { on: (name, fn) => { handlers[name] = fn; } };
const mod = await import(extPath);
mod.default(fakePi);
const ctx = {
  cwd: projectRoot,
  sessionManager: { getSessionFile: () => "pi-harness-notice" },
  ui: { notify: (msg) => notices.push(msg) },
};
await handlers.session_start({}, ctx);
console.log(JSON.stringify({ notices }));
EOF

  run env MB_VERSION_CHECK_BIN="$checker" node --experimental-strip-types "$harness" "$EXT" "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"5.3.0"* ]]
  [[ "$output" == *"9.9.9"* ]]
}

@test "pi session-memory extension: MB_UPDATE_CHECK=off renders no notice at all" {
  _install_global_session_ext

  local checker="$PROJECT/fake-checker-off.sh"
  cat > "$checker" <<'EOF'
#!/usr/bin/env bash
echo '{"current":"5.3.0","latest":"9.9.9","update_available":true,"flavor":"git","upgrade_command":"bash x","checked_at":"x","source":"github"}'
EOF
  chmod +x "$checker"

  local harness="$PROJECT/harness-notice-off.mjs"
  cat > "$harness" <<'EOF'
const [, , extPath, projectRoot] = process.argv;
const notices = [];
const handlers = {};
const fakePi = { on: (name, fn) => { handlers[name] = fn; } };
const mod = await import(extPath);
mod.default(fakePi);
const ctx = {
  cwd: projectRoot,
  sessionManager: { getSessionFile: () => "pi-harness-notice-off" },
  ui: { notify: (msg) => notices.push(msg) },
};
await handlers.session_start({}, ctx);
console.log(JSON.stringify({ notices }));
EOF

  run env MB_UPDATE_CHECK=off MB_VERSION_CHECK_BIN="$checker" node --experimental-strip-types "$harness" "$EXT" "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == '{"notices":[]}' ]]
}

# ═══════════════════════════════════════════════════════════════
# REQ-019: extension failure degrades to fallback, never blocks the session.
# ═══════════════════════════════════════════════════════════════

@test "pi session-memory extension: a broken skill dir + a THROWING ctx.ui.notify never blocks session_start, capture still works" {
  local fake_skill="$PROJECT/fake-skill"
  # A REAL hooks/mb-update-notify.sh that DOES produce a notice — the point
  # of this test is to prove a THROWING ctx.ui.notify is caught (REQ-019),
  # which requires renderUpdateNotice to actually return non-null text
  # first. No scripts/ sibling at all otherwise (deliberately missing), so
  # the catchup fire-and-forget spawn is also exercised on a broken skill dir.
  mkdir -p "$fake_skill/hooks"
  cat > "$fake_skill/hooks/mb-update-notify.sh" <<'NOTIFY_EOF'
#!/usr/bin/env bash
echo "a new release is out"
NOTIFY_EOF
  chmod +x "$fake_skill/hooks/mb-update-notify.sh"
  local ext="$PROJECT/broken-skill-session-ext.ts"
  jq -rn --arg skill "$fake_skill" --arg proj "$PROJECT" --rawfile tpl "$REPO_ROOT/adapters/pi_session_memory_extension.ts" \
    '$tpl | gsub("__MB_SKILL_DIR_JSON__"; ($skill | @json)) | gsub("__MB_PROJECT_ROOT_JSON__"; ($proj | @json))' > "$ext"
  ! grep -q '__MB_' "$ext"

  local harness="$PROJECT/harness-broken.mjs"
  cat > "$harness" <<'EOF'
const [, , extPath, projectRoot] = process.argv;
const handlers = {};
const fakePi = { on: (name, fn) => { handlers[name] = fn; } };
const mod = await import(extPath);
mod.default(fakePi);
// A host whose ctx.ui.notify ALSO throws must not break session_start either.
const ctx = {
  cwd: projectRoot,
  sessionManager: { getSessionFile: () => "pi-broken-skill" },
  ui: { notify: () => { throw new Error("host ui.notify is broken too"); } },
};
await handlers.session_start({}, ctx);
console.log("SESSION_START_COMPLETED");
EOF

  run node --experimental-strip-types "$harness" "$ext" "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SESSION_START_COMPLETED"* ]]

  # Fallback intact: session capture itself is unaffected by the missing
  # update-notify script or a throwing host notify().
  local found=0
  for f in "$PROJECT/.memory-bank/session"/*.md; do
    [ -f "$f" ] && found=1
  done
  [ "$found" -eq 1 ]
}

@test "pi session-memory extension: a hanging hooks/mb-update-notify.sh (no internal timeout of its own) is bounded by the extension's own 3s timeout" {
  # Point SKILL_DIR at a FAKE hooks/mb-update-notify.sh that sleeps forever
  # with NO internal watchdog of its own (unlike the real hook, which has
  # its own 1-2s watchdog — using the real one here would only prove THAT
  # watchdog works, not this extension's own execFileAsync `timeout: 3000`
  # bound). This is the genuine test of renderUpdateNotice()'s own timeout.
  local fake_skill="$PROJECT/fake-skill-hang"
  mkdir -p "$fake_skill/hooks"
  cat > "$fake_skill/hooks/mb-update-notify.sh" <<'HANG_EOF'
#!/usr/bin/env bash
sleep 30
HANG_EOF
  chmod +x "$fake_skill/hooks/mb-update-notify.sh"
  local ext="$PROJECT/hang-session-ext.ts"
  jq -rn --arg skill "$fake_skill" --arg proj "$PROJECT" --rawfile tpl "$REPO_ROOT/adapters/pi_session_memory_extension.ts" \
    '$tpl | gsub("__MB_SKILL_DIR_JSON__"; ($skill | @json)) | gsub("__MB_PROJECT_ROOT_JSON__"; ($proj | @json))' > "$ext"
  ! grep -q '__MB_' "$ext"

  local harness="$PROJECT/harness-hang.mjs"
  cat > "$harness" <<'EOF'
const [, , extPath, projectRoot] = process.argv;
const handlers = {};
const fakePi = { on: (name, fn) => { handlers[name] = fn; } };
const mod = await import(extPath);
mod.default(fakePi);
const ctx = { cwd: projectRoot, sessionManager: { getSessionFile: () => "pi-hang" }, ui: { notify: () => {} } };
const start = Date.now();
await handlers.session_start({}, ctx);
console.log(JSON.stringify({ elapsedMs: Date.now() - start }));
EOF

  run node --experimental-strip-types "$harness" "$ext" "$PROJECT"
  [ "$status" -eq 0 ]
  # Well under the 30s sleep AND generous CI-scheduling slack — proves
  # session_start is never held hostage by a wedged resolver script that has
  # no timeout of its own; this extension's own ~3s execFile bound wins.
  local elapsed
  elapsed=$(printf '%s' "$output" | jq -r '.elapsedMs')
  [ "$elapsed" -lt 10000 ]
}

# ═══════════════════════════════════════════════════════════════
# BLOCKER fix (Codex review): a GLOBAL install must not bake the accept-time
# project into the extension — every future Pi session in every OTHER
# project must resolve its OWN live cwd, never a frozen accept-time path.
# ═══════════════════════════════════════════════════════════════

@test "pi session-memory extension: global install accepted in project A never leaks session capture into A when a session runs in project B" {
  local project_a="$PROJECT"                 # accept-time project (setup()'s $PROJECT)
  local project_b
  project_b="$(mktemp -d)"
  mkdir -p "$project_b/.memory-bank"

  # Accept the offer FROM project A — this is exactly install.sh's
  # mb_install_host_extensions "pi" seam (install-global-extensions).
  _install_global_session_ext

  local harness="$PROJECT/harness-isolation.mjs"
  cat > "$harness" <<'EOF'
const [, , extPath, liveProjectCwd] = process.argv;
const handlers = {};
const fakePi = { on: (name, fn) => { handlers[name] = fn; } };
const mod = await import(extPath);
mod.default(fakePi);
const ctx = {
  cwd: liveProjectCwd,
  sessionManager: { getSessionFile: () => "pi-isolation-check" },
  ui: { notify: () => {} },
};
await handlers.session_start({}, ctx);
await handlers.input({ text: "does this leak into project A?" }, ctx);
await handlers.agent_end({}, ctx);
await handlers.session_shutdown({}, ctx);
console.log("HARNESS_OK");
EOF

  # A live Pi session for project B — ctx.cwd is B, NOT A. The installed
  # extension's baked PROJECT_ROOT (project A, at accept time) must NOT win.
  run env MB_SESSION_CAPTURE=auto MB_UPDATE_CHECK=off \
    node --experimental-strip-types "$harness" "$EXT" "$project_b"
  [ "$status" -eq 0 ]
  [[ "$output" == *"HARNESS_OK"* ]]

  # Capture landed in B...
  local found_b=0
  for f in "$project_b/.memory-bank/session"/*.md; do
    [ -f "$f" ] && found_b=1
  done
  [ "$found_b" -eq 1 ]

  # ...and NEVER in A (the accept-time project) — the actual leak this
  # finding described: every OTHER project's session silently writing into
  # the accept-time project's .memory-bank.
  local found_a=0
  for f in "$project_a/.memory-bank/session"/*.md; do
    [ -f "$f" ] && found_a=1
  done
  [ "$found_a" -eq 0 ]

  rm -rf "$project_b"
}

@test "pi graph-rag extension: global install bakes PROJECT_ROOT empty (project-local install still bakes the real path)" {
  _install_global_session_ext
  local global_graph_ext="$SANDBOX_HOME/.pi/agent/extensions/memory-bank-graph-rag.ts"
  [ -f "$global_graph_ext" ]
  # Global accept-path: PROJECT_ROOT baked EMPTY — process.cwd() wins at
  # runtime, never the accept-time project (the same leak class as above,
  # for the graph-rag tool-call path instead of session capture).
  grep -qE '^const PROJECT_ROOT = "";$' "$global_graph_ext"

  # Project-local install (pre-existing, unconditional, unchanged by this
  # fix): PROJECT_ROOT stays the real project path — this install IS
  # project-scoped by design (dest lives under that project's .pi/).
  (cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t)
  run bash "$REPO_ROOT/adapters/pi.sh" install "$PROJECT"
  [ "$status" -eq 0 ]
  local local_graph_ext="$PROJECT/.pi/extensions/memory-bank-graph-rag.ts"
  [ -f "$local_graph_ext" ]
  local resolved_proj
  resolved_proj="$(cd "$PROJECT" && pwd)"
  grep -qE "^const PROJECT_ROOT = \"$(printf '%s' "$resolved_proj" | sed 's/[\/&]/\\&/g')\";\$" "$local_graph_ext"
}
