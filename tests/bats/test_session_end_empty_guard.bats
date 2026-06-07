#!/usr/bin/env bats
# Tests for the empty-session guard in hooks/mb-session-end.sh.
# Trivial sessions (no real user request AND no tool calls) must NOT spend an LLM
# call, must NOT append a ## Summary, and must NOT touch _recent.md. A single
# non-empty user request OR one real tool call makes the session substantive.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/mb-session-end.sh"
  command -v jq >/dev/null || skip "jq required"
  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"; MB="$PROJ/.memory-bank"
  mkdir -p "$MB/session" "$MB/notes" "$TMP/bin"
  CALLLOG="$TMP/claude.calls"
  # fake `claude`: drains stdin, records each invocation, prints a deterministic summary
  cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null 2>&1 || true
printf '%s\n' "called" >> "$CLAUDE_CALLLOG"
printf 'FAKE SUMMARY: a deterministic one-line summary.\n'
EOF
  chmod +x "$TMP/bin/claude"
  SID="deadbeef-1111-2222-3333-444455556666"
  SID8="${SID:0:8}"
  SF="$MB/session/2026-06-08_0208_${SID8}.md"
  printf '{"cwd":"%s","session_id":"%s"}' "$PROJ" "$SID" > "$TMP/input.json"
}
teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

# Run the hook with a stubbed claude and the prepared stdin payload.
_run() {
  run env CLAUDE_CALLLOG="$CALLLOG" CLAUDE="$TMP/bin/claude" MB_SEMANTIC=off \
    "$@" bash -c "bash '$HOOK' < '$TMP/input.json'"
}

_write_session() {
  # $1 = a single Live-log bullet body (after "User: ")
  cat > "$SF" <<EOF
---
session_id: $SID
transcript:
branch: dev
turns: 2
summarized:
---

## Live log
$1
EOF
}

@test "empty session: no LLM call, no Summary, no _recent.md" {
  _write_session '- 02:08 — User: "" · tools: (none) · files: (none)
- 02:08 — User: "" · tools: (none) · files: (none)'
  _run
  [ "$status" -eq 0 ]
  [ ! -f "$CALLLOG" ]
  ! grep -q '## Summary' "$SF"
  [ ! -f "$MB/session/_recent.md" ]
}

@test "substantive session (real user request): LLM called, Summary appended" {
  _write_session '- 02:08 — User: "fix the failing build" · tools: (none) · files: (none)'
  _run
  [ "$status" -eq 0 ]
  [ -f "$CALLLOG" ]
  grep -q '## Summary' "$SF"
  grep -q 'FAKE SUMMARY' "$SF"
  grep -q 'FAKE SUMMARY' "$MB/session/_recent.md"
}

@test "tool-only session (empty prompt but a real tool): treated as substantive" {
  _write_session '- 02:08 — User: "" · tools: Bash · files: (x.sh)'
  _run
  [ "$status" -eq 0 ]
  [ -f "$CALLLOG" ]
  grep -q '## Summary' "$SF"
}

@test "MB_SESSION_EMPTY_GUARD=off restores old behaviour (empty still summarized)" {
  _write_session '- 02:08 — User: "" · tools: (none) · files: (none)'
  _run MB_SESSION_EMPTY_GUARD=off
  [ "$status" -eq 0 ]
  [ -f "$CALLLOG" ]
  grep -q '## Summary' "$SF"
}
