#!/usr/bin/env bats
# Stage 3 — mb-session-end.sh step 1: Haiku summary + _recent.md + idempotency. claude is mocked.

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$BIN/mb-session-end.sh"
  FIX="$BATS_TEST_DIRNAME/fixtures"
  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"; MB="$PROJ/.memory-bank"
  mkdir -p "$MB/session"
  cp "$FIX/transcript-two-turns.jsonl" "$TMP/t.jsonl"
  SF="$MB/session/2026-06-06_1835_af0a3685.md"
  cat > "$SF" <<EOF
---
session_id: af0a3685-3ee9-4db8
transcript: $TMP/t.jsonl
started: 2026-06-06T18:35Z
branch: dev
turns: 1
summarized: false
---

## Live log
- 18:36 — User: "second request please" · tools: (none) · files: (none)
EOF
  STUB="$TMP/bin"; mkdir -p "$STUB"
  CALLS="$TMP/calls"; STDIN_SEEN="$TMP/stdin_seen"
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
echo call >> "$CALLS"
cat > "$STDIN_SEEN"
echo "MOCK SUMMARY: user asked, work done"
EOF
  chmod +x "$STUB/claude"
  CLAUDE="$STUB/claude"
  # SessionEnd payload WITHOUT transcript_path (key audit finding)
  printf '{"cwd":"%s","session_id":"af0a3685-3ee9-4db8"}' "$PROJ" > "$TMP/in.json"
}
teardown() { rm -rf "$TMP"; }

@test "summary written, _recent updated, summarized=true; stdin lacks transcript (REQ-SM-002/013)" {
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  grep -q '## Summary' "$SF"
  grep -q 'MOCK SUMMARY' "$SF"
  grep -q 'summarized: true' "$SF"
  grep -q 'af0a3685' "$MB/session/_recent.md"
  grep -q 'MOCK SUMMARY' "$MB/session/_recent.md"
}

@test "idempotent: second SessionEnd does not re-summarize (REQ-SM-008)" {
  bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$(grep -c '## Summary' "$SF")" -eq 1 ]
  [ "$(wc -l < "$CALLS" | tr -d ' ')" -eq 1 ]
}

@test "missing claude → exit 0, Live log intact, no summary (REQ-SM-007)" {
  run bash -c "CLAUDE='$TMP/nope' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  ! grep -q '## Summary' "$SF"
  grep -q 'second request please' "$SF"
  grep -q 'summarized: false' "$SF"
}

@test "fallback to Live log when transcript file missing" {
  sed -i.bak "s#^transcript: .*#transcript: $TMP/gone.jsonl#" "$SF"
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  grep -q '## Summary' "$SF"
  grep -q 'second request please' "$STDIN_SEEN"
}

@test "_recent keeps newest N (MB_RECENT_KEEP)" {
  printf '## old5\nx\n\n## old4\nx\n\n## old3\nx\n\n## old2\nx\n\n## old1\nx\n' > "$MB/session/_recent.md"
  run bash -c "MB_RECENT_KEEP=3 CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^## ' "$MB/session/_recent.md")" -le 3 ]
  head -1 "$MB/session/_recent.md" | grep -q 'af0a3685'
}

@test "oversized transcript → summarize distilled Live-log, not a lossy raw slice (no context overflow)" {
  # transcript far larger than the cap (~100KB) → must NOT be sent to the summarizer
  yes 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX' | head -2000 > "$TMP/t.jsonl"
  run bash -c "MB_SUMMARY_MAX_CHARS=5000 CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  # claude saw a bounded prompt built from the Live-log, not the 100KB transcript
  seen="$(wc -c < "$STDIN_SEEN" | tr -d ' ')"
  [ "$seen" -le 6000 ]
  grep -q 'second request please' "$STDIN_SEEN"
  ! grep -q 'XXXXXXXX' "$STDIN_SEEN"
  # normal summary still produced
  grep -q '## Summary' "$SF"
  grep -q 'MOCK SUMMARY' "$SF"
}

@test "error-shaped summary is rejected: no Summary, summarized stays false, _recent clean (regression: a2236095)" {
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
echo "Prompt is too long · the request is ~217445 tokens (limit 200000) and this conversation cannot be compacted."
EOF
  chmod +x "$STUB/claude"
  run bash -c "CLAUDE='$STUB/claude' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  ! grep -q '## Summary' "$SF"
  grep -q 'summarized: false' "$SF"
  [ ! -f "$MB/session/_recent.md" ] || ! grep -qi 'too long' "$MB/session/_recent.md"
}
