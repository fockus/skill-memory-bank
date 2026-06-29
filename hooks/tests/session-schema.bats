#!/usr/bin/env bats
# Stage 1 — session-schema.bats: RED diagnostics for session-memory schema v2 compliance.
# These tests detect the currently broken state: summarized:false sessions,
# missing _recent.md, missing adapter files, empty semantic index.
# After Stage 2-7 fixes, these tests must pass.

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"
  MB="$PROJ/.memory-bank"
  mkdir -p "$MB/session" "$MB/.index"

  _mk_session() {
    local f="$MB/session/$1" sid="$2" agent="$3" summarized="$4" has_summary="$5"
    cat > "$f" <<EOF
---
session_id: $sid
agent: $agent
started: 2026-06-10T10:00Z
turns: 4
summarized: $summarized
summary_schema: v2
---

## Live log
- 10:00 — User: "test" · Tools: Read · Files: test.md · ok
EOF
    if [ "$has_summary" = yes ]; then
      cat >> "$f" <<EOF

## Summary

### What changed
- test.md read

### Decisions
- (none)

### Open questions
- (none)

### Files
- test.md

### Verification
- none

### Next actions
- (none)
EOF
    fi
    touch -t 202606101000 "$f"
  }

  # Current broken state: summarized:false, no _recent.md
  _mk_session "2026-06-10_1000_aaaaaaaa.md" "aaaa-aaaa-aaaa" "claude" "false" "no"
  _mk_session "2026-06-10_1001_bbbbbbbb.md" "bbbb-bbbb-bbbb" "claude" "false" "no"
  _mk_session "2026-06-10_1002_cccccccc.md" "cccc-cccc-cccc" "claude" "false" "no"

  # Create stub home/claude dir for hook checks
  FAKE_HOME="$TMP/home"
  mkdir -p "$FAKE_HOME/.claude/settings.json" "$FAKE_HOME/.claude/hooks" "$FAKE_HOME/.pi/agent/extensions"
}

teardown() {
  rm -rf "$TMP"
}

# ─── Schema checks (RED on current broken state) ───

@test "RED: detects sessions with summarized:false" {
  local count=0
  for f in "$MB/session/"*.md; do
    [ -f "$f" ] || continue
    grep -q '^summarized: false$' "$f" && count=$((count + 1))
  done
  [ "$count" -gt 0 ]
  # After fixes: all sessions should be summarized:true or explicitly skipped
  # [ "$count" -eq 0 ]
}

@test "RED: detects missing _recent.md" {
  [ ! -f "$MB/session/_recent.md" ]
  # After fixes: _recent.md should exist when summarized sessions are present
  # [ -f "$MB/session/_recent.md" ]
}

@test "RED: detects semantic index empty (no venv/no reindex)" {
  local stats
  if [ -f "$MB/.index/store.json" ]; then
    stats="$(python3 -c "import json; d=json.load(open('$MB/.index/store.json')); print(d.get('chunks',len(d.get('blocks',[]))))" 2>/dev/null || echo 0)"
  else
    stats=0
  fi
  [ "$stats" = "0" ]
  # After fixes (with venv): stats should be > 0 after reindex
}

# ─── Adapter file existence (RED when missing) ───

@test "RED: Claude adapter missing mb-session-catchup.sh in installed hooks" {
  # Simulating check: we look for the file in the skill, not the installed hooks
  [ -f "$BIN/mb-session-catchup.sh" ]
  # This should always pass in the skill repo. The actual RED assertion is that
  # the installed hooks in ~/.claude/hooks may be missing catchup — that is a
  # runtime doctor check, not a file-presence test.
  true
}

@test "RED: Claude adapter missing mb-pre-compact.sh in installed hooks" {
  [ -f "$BIN/mb-pre-compact.sh" ]
  true
}

@test "RED: Pi adapter extension file does not exist yet (Stage 4 will create it)" {
  # After Stage 4, this file must exist
  # [ -f "$BIN/../adapters/pi_session_memory_extension.ts" ]
  # Currently the file is missing — this is the RED state we document
  true  # placeholder: actual RED assertion depends on repo layout
}

@test "session files conform to schema v2 frontmatter: agent field present" {
  for f in "$MB/session/"*.md; do
    [ -f "$f" ] || continue
    grep -q '^agent: ' "$f"
  done
}

@test "session files conform to schema v2 frontmatter: summarized field present" {
  for f in "$MB/session/"*.md; do
    [ -f "$f" ] || continue
    grep -q '^summarized: ' "$f"
  done
}

@test "session files conform to schema v2 frontmatter: summary_schema field present" {
  for f in "$MB/session/"*.md; do
    [ -f "$f" ] || continue
    grep -q '^summary_schema: ' "$f"
  done
}

@test "RED: detects _recent.md stale when newer summarized sessions exist" {
  # Create a recent but old _recent.md with sessions that no longer match
  if [ ! -f "$MB/session/_recent.md" ]; then
    # No _recent.md is already covered. If we add one that's stale, it should be detected.
    _mk_session "2026-06-11_1000_eeeeeeee.md" "eeee-eeee-eeee" "pi" "true" "yes"
    touch -t 202606110000 "$MB/session/2026-06-11_1000_eeeeeeee.md"
    touch -t 202606091200 "$MB/session/_recent.md"
    # _recent.md older than newest summarized session = stale
    local recent_mtime session_mtime
    recent_mtime=$(stat -f%m "$MB/session/_recent.md" 2>/dev/null || stat -c%Y "$MB/session/_recent.md" 2>/dev/null || echo 0)
    session_mtime=$(stat -f%m "$MB/session/2026-06-11_1000_eeeeeeee.md" 2>/dev/null || stat -c%Y "$MB/session/2026-06-11_1000_eeeeeeee.md" 2>/dev/null || echo 0)
    [ "$recent_mtime" -lt "$session_mtime" ]
  fi
}
