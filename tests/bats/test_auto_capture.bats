#!/usr/bin/env bats
# Tests for hooks/session-end-autosave.sh — auto-capture hook for Memory Bank.
#
# Hook reads SessionEnd JSON from stdin, parses cwd, and works with
# $cwd/.memory-bank/progress.md in MB_AUTO_CAPTURE=auto|strict|off modes.
#
# Lock file `.memory-bank/.session-lock` means a manual /mb done
# already happened — the hook skips and clears the lock.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/session-end-autosave.sh"

  TMPHOME="$(mktemp -d)"
  export HOME="$TMPHOME"
  mkdir -p "$HOME/.claude"

  # Per-test CWD with a Memory Bank seeded.
  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/notes" "$MB/plans"
  printf '# Progress\n\nWork history.\n' > "$MB/progress.md"
  printf '# Checklist\n' > "$MB/checklist.md"
  printf '# STATUS\n' > "$MB/STATUS.md"

  command -v jq >/dev/null || skip "jq required for hook"
}

teardown() {
  [ -n "${TMPHOME:-}" ] && [ -d "$TMPHOME" ] && rm -rf "$TMPHOME"
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

# Build SessionEnd payload with overridable cwd.
payload_session_end() {
  local cwd="${1:-$PROJECT}"
  local session_id="${2:-abc123def456}"
  jq -n \
    --arg cwd "$cwd" \
    --arg sid "$session_id" \
    '{hook_event_name:"SessionEnd", cwd:$cwd, session_id:$sid, reason:"clear"}'
}

# Run hook capturing stdout+stderr and exit code through the __EXIT__ sentinel.
# Environment variables are passed through leading assignments.
run_hook_env() {
  local env_assign="$1" input="$2"
  local raw
  raw=$(printf '%s' "$input" | env $env_assign bash "$HOOK" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

run_hook() {
  run_hook_env "" "$1"
}

# ═══════════════════════════════════════════════════════════════
# Lock-file logic (a manual /mb done already happened)
# ═══════════════════════════════════════════════════════════════

@test "auto-capture: fresh lock exists → skip and clear lock" {
  # .session-lock created by manual /mb done one minute ago.
  touch "$MB/.session-lock"
  before=$(wc -l < "$MB/progress.md")

  run_hook "$(payload_session_end)"
  [ "$status" -eq 0 ]

  # Lock removed (so the next session does not treat it as stale).
  [ ! -f "$MB/.session-lock" ]

  # progress.md did not change.
  after=$(wc -l < "$MB/progress.md")
  [ "$before" -eq "$after" ]
}

@test "auto-capture: stale lock (>1h) → runs and appends" {
  touch "$MB/.session-lock"
  # Move mtime 2 hours back.
  old=$(($(date +%s) - 7200))
  touch -t "$(date -r "$old" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$old" +%Y%m%d%H%M.%S)" "$MB/.session-lock"

  run_hook "$(payload_session_end)"
  [ "$status" -eq 0 ]

  # Stale lock cleared, entry added.
  [ ! -f "$MB/.session-lock" ]
  grep -q "Auto-capture" "$MB/progress.md"
}

# ═══════════════════════════════════════════════════════════════
# MB_AUTO_CAPTURE modes
# ═══════════════════════════════════════════════════════════════

@test "auto-capture: default mode (auto) appends to progress.md" {
  before=$(wc -l < "$MB/progress.md")

  run_hook_env "MB_AUTO_CAPTURE=auto" "$(payload_session_end)"
  [ "$status" -eq 0 ]

  after=$(wc -l < "$MB/progress.md")
  [ "$after" -gt "$before" ]
  grep -q "Auto-capture" "$MB/progress.md"
}

@test "auto-capture: MB_AUTO_CAPTURE=off → full noop" {
  before=$(cat "$MB/progress.md")

  run_hook_env "MB_AUTO_CAPTURE=off" "$(payload_session_end)"
  [ "$status" -eq 0 ]

  after=$(cat "$MB/progress.md")
  [ "$before" = "$after" ]
}

@test "auto-capture: MB_AUTO_CAPTURE=strict → warning in stderr, skip" {
  before=$(cat "$MB/progress.md")

  run_hook_env "MB_AUTO_CAPTURE=strict" "$(payload_session_end)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict"* ]] || [[ "$output" == *"/mb done"* ]]

  after=$(cat "$MB/progress.md")
  [ "$before" = "$after" ]
}

@test "auto-capture: unknown MB_AUTO_CAPTURE → warning, skip" {
  before=$(cat "$MB/progress.md")

  run_hook_env "MB_AUTO_CAPTURE=bogus" "$(payload_session_end)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bogus"* ]] || [[ "$output" == *"unknown"* ]] || [[ "$output" == *"MB_AUTO_CAPTURE"* ]]

  after=$(cat "$MB/progress.md")
  [ "$before" = "$after" ]
}

# ═══════════════════════════════════════════════════════════════
# Edge cases
# ═══════════════════════════════════════════════════════════════

@test "auto-capture: no .memory-bank/ → noop exit 0" {
  NOBANK="$(mktemp -d)"
  before=$(cat "$MB/progress.md")  # our seeded MB must stay untouched.

  run_hook_env "MB_AUTO_CAPTURE=auto" "$(payload_session_end "$NOBANK")"
  [ "$status" -eq 0 ]

  after=$(cat "$MB/progress.md")
  [ "$before" = "$after" ]

  rm -rf "$NOBANK"
}

@test "auto-capture: missing progress.md → noop, no crash" {
  rm -f "$MB/progress.md"

  run_hook_env "MB_AUTO_CAPTURE=auto" "$(payload_session_end)"
  [ "$status" -eq 0 ]

  # The hook does NOT create progress.md — /mb init must do that.
  [ ! -f "$MB/progress.md" ]
}

@test "auto-capture: idempotent — 2 runs same day → 1 entry only" {
  run_hook_env "MB_AUTO_CAPTURE=auto" "$(payload_session_end)"
  [ "$status" -eq 0 ]
  first_count=$(grep -c "Auto-capture" "$MB/progress.md" || echo 0)

  run_hook_env "MB_AUTO_CAPTURE=auto" "$(payload_session_end)"
  [ "$status" -eq 0 ]
  second_count=$(grep -c "Auto-capture" "$MB/progress.md" || echo 0)

  [ "$first_count" -eq 1 ]
  [ "$second_count" -eq 1 ]
}

@test "auto-capture: concurrent invocation — fresh .auto-lock → second instance skips" {
  # Simulate another hook already in progress (fresh .auto-lock created).
  touch "$MB/.auto-lock"

  before=$(cat "$MB/progress.md")

  run_hook_env "MB_AUTO_CAPTURE=auto" "$(payload_session_end)"
  [ "$status" -eq 0 ]

  # The second instance does not touch progress.md.
  after=$(cat "$MB/progress.md")
  [ "$before" = "$after" ]
}

@test "auto-capture: .auto-lock cleaned up after successful run" {
  run_hook_env "MB_AUTO_CAPTURE=auto" "$(payload_session_end)"
  [ "$status" -eq 0 ]

  # Auto-lock (temp) should be removed through trap EXIT.
  [ ! -f "$MB/.auto-lock" ]
}

@test "auto-capture: entry contains session id prefix and date" {
  run_hook_env "MB_AUTO_CAPTURE=auto" "$(payload_session_end "$PROJECT" "deadbeef12345678")"
  [ "$status" -eq 0 ]

  today=$(date +%Y-%m-%d)
  grep -q "$today" "$MB/progress.md"
  # Short session_id prefix (first 8 characters).
  grep -q "deadbeef" "$MB/progress.md"
}
