#!/usr/bin/env bats
# Tests for adapters/cursor.sh — Cursor IDE cross-agent adapter.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ADAPTER="$REPO_ROOT/adapters/cursor.sh"
  PROJECT="$(mktemp -d)"
  command -v jq >/dev/null || skip "jq required"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

run_adapter() {
  local raw
  raw=$(bash "$ADAPTER" "$@" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

@test "cursor: install creates expected directory structure" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -d "$PROJECT/.cursor" ]
  [ -d "$PROJECT/.cursor/rules" ]
  [ ! -d "$PROJECT/.cursor/hooks" ]
}

# A23 (CDX-I8): the rules file is a whole-file overwrite via `{ ... } > "$RULES_FILE"`
# with no backup at all — a user's own same-named memory-bank.mdc is clobbered
# without any recoverable copy.
@test "cursor: install backs up a pre-existing user memory-bank.mdc before overwriting (A23)" {
  mkdir -p "$PROJECT/.cursor/rules"
  printf -- '---\ndescription: user rules\n---\nUSER_CURSOR_RULES_MARKER\n' \
    > "$PROJECT/.cursor/rules/memory-bank.mdc"

  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]

  local rules="$PROJECT/.cursor/rules/memory-bank.mdc"
  # Freshly generated (MB content installed)...
  grep -qi "memory bank" "$rules"
  # ...but the user's original is recoverable via a backup.
  local found=0
  for b in "$rules".pre-mb-backup.*; do
    [ -f "$b" ] && grep -q "USER_CURSOR_RULES_MARKER" "$b" && found=1
  done
  [ "$found" -eq 1 ]
}

@test "cursor: install wires hooks.json to skill bundle paths" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hjson="$PROJECT/.cursor/hooks.json"
  grep -q 'memory-bank/hooks/mb-session-end.sh' "$hjson"
  grep -q 'MB_AGENT=cursor' "$hjson"
  [ ! -f "$PROJECT/.cursor/hooks/mb-session-end.sh" ]
}

# B4 (F-4): Cursor used to wire the basic placeholder-only session-end-autosave.sh
# for sessionEnd — missing the CC-compatible rich capture (Haiku summary + Sonnet
# judge notes) that Claude Code gets via mb-session-end.sh. Swap the wiring so
# Cursor gets the same capture script (fail-open: no `claude`/session file → noop).
@test "cursor: install wires sessionEnd to mb-session-end.sh, not session-end-autosave.sh (B4)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hjson="$PROJECT/.cursor/hooks.json"
  local cmd
  cmd=$(jq -r '.hooks.sessionEnd[0].command' "$hjson")
  [[ "$cmd" == *"mb-session-end.sh"* ]]
  [[ "$cmd" != *"session-end-autosave.sh"* ]]
}

@test "cursor: install removes legacy hook copies on reinstall" {
  run_adapter install "$PROJECT"
  mkdir -p "$PROJECT/.cursor/hooks"
  echo legacy > "$PROJECT/.cursor/hooks/mb-plan-sync-post-write.sh"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.cursor/hooks/mb-plan-sync-post-write.sh" ]
}

@test "cursor: install creates valid hooks.json with CC-compat events" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hjson="$PROJECT/.cursor/hooks.json"
  jq . "$hjson" >/dev/null
  jq -e '.hooks.sessionEnd' "$hjson" >/dev/null
  jq -e '.hooks.preCompact' "$hjson" >/dev/null
  jq -e '.hooks.beforeShellExecution' "$hjson" >/dev/null
}

@test "cursor: install references all twelve hook scripts in hooks.json" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hjson="$PROJECT/.cursor/hooks.json"
  local hooks=(mb-session-end.sh mb-session-turn.sh mb-pre-compact.sh block-dangerous.sh mb-protected-paths-guard.sh mb-ears-pre-write.sh mb-context-slim-pre-agent.sh mb-sprint-context-guard.sh file-change-log.sh mb-plan-sync-post-write.sh mb-session-start-context.sh mb-update-notify.sh)
  local h
  for h in "${hooks[@]}"; do
    grep -q "memory-bank/hooks/$h" "$hjson"
  done
}

@test "cursor: install has exactly twelve _mb_owned entries" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local count
  count=$(jq '[.hooks[][] | select(._mb_owned == true)] | length' "$PROJECT/.cursor/hooks.json")
  [ "$count" -eq 12 ]
}

# ═══════════════════════════════════════════════════════════════
# adapter-parity T7 (REQ-021): Cursor claims Claude-Code-tier session-memory
# and update-notify parity — these tests PROVE it via Cursor's own wired
# hooks.json commands (not the generic shared-script simulation elsewhere),
# closing a genuine gap found during T7 investigation: before this task,
# Cursor wired sessionEnd (mb-session-end.sh, summarize-only) but nothing to
# CC's Stop event (mb-session-turn.sh, the script that actually CREATES the
# session/*.md entry) — session/*.md was never populated end-to-end.
# ═══════════════════════════════════════════════════════════════

@test "cursor: stop event is wired to mb-session-turn.sh (REQ-021 — the script that creates session/*.md)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hjson="$PROJECT/.cursor/hooks.json"
  local cmd
  cmd=$(jq -r '.hooks.stop[0].command' "$hjson")
  [[ "$cmd" == *"mb-session-turn.sh"* ]]
}

@test "cursor: invoking the wired stop+sessionEnd commands end-to-end creates a real CC v2-schema session/*.md (REQ-021)" {
  # Hermetic HOME: cursor_resolve_skill_hooks_dir prefers
  # $HOME/.cursor/skills/memory-bank/hooks when present (a real global
  # install) and only falls back to this worktree's bundle otherwise — a
  # fresh sandboxed HOME guarantees we exercise THIS worktree's hooks, not
  # whatever happens to be globally installed on the machine running the test.
  local sandbox_home
  sandbox_home="$(mktemp -d)"
  run env HOME="$sandbox_home" bash "$ADAPTER" install "$PROJECT"
  [ "$status" -eq 0 ]
  mkdir -p "$PROJECT/.memory-bank"

  local sid="11111111-2222-3333-4444-555555555555"
  local transcript="$PROJECT/transcript.jsonl"
  cat > "$transcript" <<EOF
{"type":"user","uuid":"u-1","message":{"content":"fix the flaky upload test"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"src/upload.py"}}]}}
EOF
  local payload
  payload="$(jq -n --arg cwd "$PROJECT" --arg sid "$sid" --arg tp "$transcript" \
    '{cwd: $cwd, session_id: $sid, transcript_path: $tp, stop_hook_active: false}')"

  local hjson="$PROJECT/.cursor/hooks.json"
  local stop_cmd end_cmd
  stop_cmd=$(jq -r '.hooks.stop[0].command' "$hjson")
  end_cmd=$(jq -r '.hooks.sessionEnd[0].command' "$hjson")
  [[ "$stop_cmd" == *"$REPO_ROOT/hooks/mb-session-turn.sh"* ]]

  run env HOME="$sandbox_home" MB_SESSION_CAPTURE=auto bash -c "printf '%s' \"\$1\" | $stop_cmd" _ "$payload"
  [ "$status" -eq 0 ]

  local found=0
  for f in "$PROJECT/.memory-bank/session"/*"${sid:0:8}"*.md; do
    [ -f "$f" ] && found=1
  done
  [ "$found" -eq 1 ]
  grep -rq "fix the flaky upload test" "$PROJECT/.memory-bank/session/"

  # sessionEnd (summarize step) must find the file the stop step created —
  # proves the two events genuinely compose into the CC lifecycle, not just
  # each independently no-op. adapter-parity T7 Codex-review fix (MAJOR):
  # `claude` is unavailable in a bare test environment, so mb-session-end.sh
  # fail-opens to exit 0 WITHOUT summarizing (see its own
  # `command -v "$CLAUDE" >/dev/null 2>&1 || exit 0` guard) — asserting only
  # `[ "$status" -eq 0 ]` therefore passes even as a pure no-op and proves
  # nothing about REQ-021's claimed sessionEnd summarization. Stub CLAUDE
  # (the same seam mb-session-end.sh/mb-session-summarize.sh already read —
  # see tests/bats/test_session_end_empty_guard.bats) so the summarizer
  # deterministically runs, then assert the wired sessionEnd command
  # genuinely writes the v2 summary fields, not just exit 0.
  local claude_stub="$PROJECT/fake-claude-summarizer.sh"
  cat > "$claude_stub" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null 2>&1 || true
printf '%s\n' \
'### What changed
- Fixed the flaky upload test in src/upload.py

### Decisions
- (none)

### Open questions
- (none)

### Files
- src/upload.py'
EOF
  chmod +x "$claude_stub"

  run env HOME="$sandbox_home" MB_SESSION_CAPTURE=auto CLAUDE="$claude_stub" MB_SESSION_JUDGE=off \
    bash -c "printf '%s' \"\$1\" | $end_cmd" _ "$payload"
  [ "$status" -eq 0 ]

  local sfile2=""
  for f in "$PROJECT/.memory-bank/session"/*"${sid:0:8}"*.md; do
    [ -f "$f" ] && sfile2="$f"
  done
  [ -n "$sfile2" ]
  grep -q "^summarized: true$" "$sfile2"
  grep -q "^summary_schema: v2$" "$sfile2"
  grep -q "^## Summary$" "$sfile2"
  grep -q "Fixed the flaky upload test" "$sfile2"

  rm -rf "$sandbox_home"
}

@test "cursor: invoking the wired sessionStart update-notify command emits a real notice (REQ-021)" {
  local sandbox_home
  sandbox_home="$(mktemp -d)"
  run env HOME="$sandbox_home" bash "$ADAPTER" install "$PROJECT"
  [ "$status" -eq 0 ]
  local hjson="$PROJECT/.cursor/hooks.json"
  local cmd
  cmd=$(jq -r '.hooks.sessionStart[] | select(.command | test("mb-update-notify.sh")) | .command' "$hjson")
  [[ "$cmd" == *"mb-update-notify.sh"* ]]

  local checker="$PROJECT/fake-checker.sh"
  cat > "$checker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"current": "5.3.0", "latest": "5.4.0", "update_available": true, "flavor": "pipx", "upgrade_command": "pipx upgrade memory-bank-skill", "checked_at": "x", "source": "github"}'
exit 0
EOF
  chmod +x "$checker"

  run env HOME="$sandbox_home" MB_VERSION_CHECK_BIN="$checker" bash -c "$cmd"
  [ "$status" -eq 0 ]
  [[ "$output" == *"5.3.0"* ]]
  [[ "$output" == *"5.4.0"* ]]
  [[ "$output" == *"pipx upgrade memory-bank-skill"* ]]

  rm -rf "$sandbox_home"
}

@test "cursor: uninstall removes all our files" {
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.cursor/rules/memory-bank.mdc" ]
  [ ! -f "$PROJECT/.cursor/.mb-manifest.json" ]
}

@test "cursor: adapter hooks.json supports global storage via MB_AGENT" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  grep -q 'MB_AGENT=cursor' "$PROJECT/.cursor/hooks.json"
  grep -q 'MB_SKILLS_ROOT=' "$PROJECT/.cursor/hooks.json"
}

# A15 (M-7): MB_SKILLS_ROOT was written unquoted into the generated hooks.json
# command string — a $HOME containing a space (e.g. "/Users/john doe") breaks
# the env-var assignment when Cursor's hook runner hands the command to a
# shell (the value gets split at the first space into a stray extra word).
@test "cursor: hooks.json MB_SKILLS_ROOT survives a HOME with a space (A15)" {
  local home
  home="$(mktemp -d)/john doe"
  mkdir -p "$home"

  run env HOME="$home" bash "$ADAPTER" install "$PROJECT"
  [ "$status" -eq 0 ]

  local hjson="$PROJECT/.cursor/hooks.json"
  local cmd env_part
  cmd=$(jq -r '.hooks.sessionEnd[0].command' "$hjson")
  [[ "$cmd" == *"MB_SKILLS_ROOT="* ]]
  env_part="${cmd%% bash *}"

  # Hand just the env-assignment prefix to a real shell and read back
  # MB_SKILLS_ROOT — it must be the FULL path (with the space intact), not
  # truncated at the first word boundary.
  run bash -c "${env_part} bash -c 'printf %s \"\$MB_SKILLS_ROOT\"'"
  [ "$status" -eq 0 ]
  [ "$output" = "$home/.claude/skills" ]

  rm -rf "$(dirname "$home")"
}

# ═══════════════════════════════════════════════════════════════
# H-2: run_texttool must honor ${MB_PYTHON:-python3} (pipx isolated venv)
# ═══════════════════════════════════════════════════════════════

@test "cursor: run_texttool honors MB_PYTHON (not bare python3)" {
  command -v python3 >/dev/null || skip "python3 required"
  local home stub marker real_py
  home="$(mktemp -d)"
  stub="$(mktemp -d)"
  marker="$stub/mb_python_called"
  real_py="$(command -v python3)"
  # Recording interpreter: notes it was called, then delegates to the real python
  # (so _texttools still resolves and install-global completes).
  cat > "$stub/mb-python" <<EOF
#!/usr/bin/env bash
echo called >> "$marker"
exec "$real_py" "\$@"
EOF
  chmod +x "$stub/mb-python"
  run env HOME="$home" MB_PYTHON="$stub/mb-python" MB_LANGUAGE=en \
    bash "$ADAPTER" install-global </dev/null
  # run_texttool (via localize) must have used MB_PYTHON, not a bare python3.
  [ -f "$marker" ]
  rm -rf "$home" "$stub"
}

@test "cursor: no bare 'python3 -m memory_bank_skill' in any adapter" {
  # Grep-invariant: every python entry point must go through ${MB_PYTHON:-python3}
  # so pipx/pip isolated installs (bare system python3 can't import the package)
  # do not abort under set -euo pipefail.
  ! grep -rnE '(^|[^-])python3 -m memory_bank_skill' "$REPO_ROOT"/adapters/*.sh
}

# ═══════════════════════════════════════════════════════════════
# H-2 tail: install-global must record the locale in its manifest, so the
# install.sh idempotency guard can detect a language switch at the same skill
# version (en → ru) and re-localize instead of skipping. Without a recorded
# `lang`, the version-only guard leaves stale English rules after `--language ru`.
# ═══════════════════════════════════════════════════════════════

@test "cursor: global manifest records the install locale (for the language-aware guard)" {
  command -v jq >/dev/null || skip "jq required"
  local home
  home="$(mktemp -d)"
  run env HOME="$home" MB_LANGUAGE=ru bash "$ADAPTER" install-global </dev/null
  [ "$status" -eq 0 ]
  jq -e '.lang == "ru"' "$home/.cursor/.mb-manifest.json" >/dev/null
  rm -rf "$home"
}

@test "cursor: reinstall removes legacy mb-compact-reminder.sh copy left by old install" {
  # Simulate an old install that left a physical copy of the renamed hook.
  run_adapter install "$PROJECT"
  mkdir -p "$PROJECT/.cursor/hooks"
  echo '#!/usr/bin/env bash' > "$PROJECT/.cursor/hooks/mb-compact-reminder.sh"
  chmod +x "$PROJECT/.cursor/hooks/mb-compact-reminder.sh"
  # Reinstall must clean up the stale legacy copy.
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.cursor/hooks/mb-compact-reminder.sh" ]
}
