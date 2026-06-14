#!/usr/bin/env bats
# Task 8 / REQ-010 + REQ-011 — structured session summary (schema v2):
#   - summarizer input = redacted structured Live-log bullets + outcome signals,
#     NOT the raw transcript tail;
#   - Haiku prompt enforces the fixed section template (What changed / Decisions /
#     Open questions / Files);
#   - new summaries carry frontmatter `summary_schema: v2`;
#   - legacy summaries (no flag) still parse in the _recent.md rebuild.
# claude is mocked; the stub captures the exact stdin the summarizer received.

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$BIN/mb-session-end.sh"
  REBUILD="$(cd "$BIN/../scripts" && pwd)/mb-session-recent-rebuild.sh"
  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"; MB="$PROJ/.memory-bank"
  mkdir -p "$MB/session"
  # A real raw transcript on disk — its contents must NOT reach the summarizer.
  printf '{"type":"user","message":{"content":"RAW_TRANSCRIPT_MARKER do not leak"}}\n' > "$TMP/t.jsonl"
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
- 18:36 — User: "add the v2 summary schema" · tools: Edit,Bash · files: hooks/mb-session-end.sh · ok · +12/-3
EOF
  STUB="$TMP/bin"; mkdir -p "$STUB"
  CALLS="$TMP/calls"; STDIN_SEEN="$TMP/stdin_seen"
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
echo call >> "$CALLS"
cat > "$STDIN_SEEN"
echo "### What changed"
echo "edited the hook"
echo "### Decisions"
echo "use v2 schema"
echo "### Open questions"
echo "none"
echo "### Files"
echo "hooks/mb-session-end.sh"
EOF
  chmod +x "$STUB/claude"
  CLAUDE="$STUB/claude"
  printf '{"cwd":"%s","session_id":"af0a3685-3ee9-4db8"}' "$PROJ" > "$TMP/in.json"
}
teardown() { rm -rf "$TMP"; }

@test "summarizer input is the structured Live log, NOT the raw transcript (REQ-011)" {
  # Disable the judge so $STDIN_SEEN captures the SUMMARY prompt, not a later judge prompt.
  run bash -c "MB_SESSION_JUDGE=off CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  # ...and the raw transcript tail did NOT (assert the negative first so it genuinely fails
  # the test — a non-final `! grep` does not fail a bats test on older bats).
  run grep -q 'RAW_TRANSCRIPT_MARKER' "$STDIN_SEEN"
  [ "$status" -ne 0 ]
  # Live-log content reached the summarizer.
  grep -q 'add the v2 summary schema' "$STDIN_SEEN"
  grep -q 'tools: Edit,Bash' "$STDIN_SEEN"
}

@test "prompt enforces the four fixed sections (REQ-010)" {
  # Disable the judge so $STDIN_SEEN captures the SUMMARY prompt (the section template lives
  # only in the Haiku prompt; a later judge call would otherwise overwrite the capture).
  run bash -c "MB_SESSION_JUDGE=off CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  grep -q '### What changed' "$STDIN_SEEN"
  grep -q '### Decisions' "$STDIN_SEEN"
  grep -q '### Open questions' "$STDIN_SEEN"
  grep -q '### Files' "$STDIN_SEEN"
}

@test "new summary carries summary_schema: v2 frontmatter flag (REQ-010)" {
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  grep -q '^summary_schema: v2' "$SF"
  grep -q '## Summary' "$SF"
  grep -q '### What changed' "$SF"
}

@test "secrets in the Live log are redacted before reaching the summarizer (REQ-011)" {
  cat > "$SF" <<EOF
---
session_id: af0a3685-3ee9-4db8
transcript:
started: 2026-06-06T18:35Z
branch: dev
turns: 1
summarized: false
---

## Live log
- 18:36 — User: "deploy with sk-abcdefghijklmnopqrstuvwxyz0123" · tools: Bash · files: (none) · ok
EOF
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  # Assert the negative via run/status so it genuinely fails the test (non-final `! grep` won't).
  run grep -q 'sk-abcdefghijklmnopqrstuvwxyz0123' "$STDIN_SEEN"
  [ "$status" -ne 0 ]
  grep -q 'REDACTED' "$STDIN_SEEN"
}

@test "live-log extraction stops at the next ## heading — a prior ## Summary does not leak into SRC (REQ-011)" {
  # A re-run session file already carries a generated ## Summary (and ## Auto-notes emitted)
  # AFTER the ## Live log. The summarizer source must be the Live log ONLY: a previously
  # generated summary must never be fed back in as if it were a per-turn bullet.
  cat > "$SF" <<EOF
---
session_id: af0a3685-3ee9-4db8
transcript:
started: 2026-06-06T18:35Z
branch: dev
turns: 1
summarized: false
---

## Live log
- 18:36 — User: "add the v2 summary schema" · tools: Edit,Bash · files: hooks/mb-session-end.sh · ok · +12/-3

## Summary
### What changed
PRIOR_SUMMARY_SENTINEL_must_not_leak

## Auto-notes emitted
- notes/2026-06-06_1836_some-note.md
EOF
  run bash -c "MB_SESSION_JUDGE=off CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  # The prior summary section must NOT be part of the summarizer input.
  run grep -q 'PRIOR_SUMMARY_SENTINEL_must_not_leak' "$STDIN_SEEN"
  [ "$status" -ne 0 ]
  # ...nor the Auto-notes section.
  run grep -q 'Auto-notes emitted' "$STDIN_SEEN"
  [ "$status" -ne 0 ]
  # The actual Live-log turn still reached the summarizer.
  grep -q 'add the v2 summary schema' "$STDIN_SEEN"
}

@test "empty Live log falls back to the raw transcript only when the guard is off (MB_SESSION_EMPTY_GUARD=off)" {
  # Under DEFAULT config the empty-session guard exits first for a contentless Live log, so the
  # transcript fallback is reachable ONLY when the guard is explicitly disabled. This test pins
  # that documented toggle: with the guard off, a contentless Live log falls back to the raw
  # transcript so the session still gets summarized.
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
EOF
  run bash -c "MB_SESSION_EMPTY_GUARD=off CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  grep -q 'RAW_TRANSCRIPT_MARKER' "$STDIN_SEEN"
  grep -q '## Summary' "$SF"
}

# ── Legacy compatibility: files WITHOUT summary_schema must still rebuild _recent.md ──

@test "legacy summary (no summary_schema flag) still parses in _recent.md rebuild" {
  rm -f "$SF"
  legacy="$MB/session/2026-06-05_1000_deadbeef.md"
  cat > "$legacy" <<'EOF'
---
session_id: deadbeef-1111-2222
started: 2026-06-05T10:00Z
branch: main
turns: 2
summarized: true
---

## Live log
- 10:01 — User: "legacy work" · tools: Edit · files: a.py · ok

## Summary
LEGACY PLAIN-PROSE SUMMARY without sections or schema flag.
EOF
  run bash -c "bash '$REBUILD' '$MB'"
  [ "$status" -eq 0 ]
  grep -q 'deadbeef' "$MB/session/_recent.md"
  grep -q 'LEGACY PLAIN-PROSE SUMMARY' "$MB/session/_recent.md"
}

@test "malformed summarizer output (no four headings) is stored WITHOUT summary_schema flag (REQ-010)" {
  # The summarizer returns plain prose with none of the four required headings. The hook must
  # store it (non-empty, non-error output) but MUST NOT stamp `summary_schema: v2` — the flag's
  # contract is "present ⇒ the stored summary really has the four headings in order". A lying
  # flag breaks the deterministic parser for downstream consumers.
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
echo call >> "$CALLS"
cat > "$STDIN_SEEN"
echo "I edited the hook and it now works as expected."
EOF
  chmod +x "$STUB/claude"
  run bash -c "MB_SESSION_JUDGE=off CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  # Summary was stored as-is (legacy treatment).
  grep -q '## Summary' "$SF"
  grep -q 'I edited the hook and it now works as expected.' "$SF"
  # ...but the flag must be ABSENT (assert the negative via run/status so it genuinely fails).
  run grep -q '^summary_schema' "$SF"
  [ "$status" -ne 0 ]
}

@test "[MEMORY BANK: ...] preamble before the four sections is stripped; v2 flag IS set (REQ-010)" {
  # The user's global CLAUDE.md mandates `[MEMORY BANK: ACTIVE]` as the first response line, so
  # the `claude -p` subprocess realistically prefixes the summary with it. The hook must strip
  # the preamble (so the stored summary starts at ### What changed) yet still recognise the four
  # valid sections and stamp summary_schema: v2.
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
echo call >> "$CALLS"
cat > "$STDIN_SEEN"
echo "[MEMORY BANK: ACTIVE]"
echo "### What changed"
echo "edited the hook"
echo "### Decisions"
echo "use v2 schema"
echo "### Open questions"
echo "none"
echo "### Files"
echo "hooks/mb-session-end.sh"
EOF
  chmod +x "$STUB/claude"
  run bash -c "MB_SESSION_JUDGE=off CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  # Preamble stripped: the stored ## Summary body begins at ### What changed.
  grep -q '^summary_schema: v2' "$SF"
  run grep -q 'MEMORY BANK: ACTIVE' "$SF"
  [ "$status" -ne 0 ]
  # The four headings survive the strip.
  grep -q '### What changed' "$SF"
  grep -q '### Files' "$SF"
  # The stored Summary section starts immediately with the first heading, no stray preamble line.
  run bash -c "awk '/^## Summary\$/{getline; print; exit}' '$SF'"
  [ "$output" = '### What changed' ]
}

# ── I-069 (r3): strict v2 heading state machine ──────────────────────────────
# The schema-v2 validator must REJECT a body where a recognized heading is duplicated
# or appears out of canonical order. Rejection = stored as-is WITHOUT summary_schema: v2
# (the same honest-flag mechanism as the malformed-output case), never a hard crash.

@test "duplicate recognized heading is REJECTED — stored WITHOUT summary_schema flag (I-069)" {
  # ### Decisions appears twice. The four-in-order check used to pass it (want stayed 5),
  # falsely stamping v2 and breaking the deterministic single-section parser contract.
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
echo call >> "$CALLS"
cat > "$STDIN_SEEN"
echo "### What changed"
echo "edited the hook"
echo "### Decisions"
echo "use v2 schema"
echo "### Decisions"
echo "a duplicate decisions heading"
echo "### Open questions"
echo "none"
echo "### Files"
echo "hooks/mb-session-end.sh"
EOF
  chmod +x "$STUB/claude"
  run bash -c "MB_SESSION_JUDGE=off CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  # Summary is still stored (fail-open: non-empty, non-error output is never dropped).
  grep -q '## Summary' "$SF"
  grep -q 'a duplicate decisions heading' "$SF"
  # ...but the v2 flag must be ABSENT (assert the negative via run/status so it genuinely fails).
  run grep -q '^summary_schema' "$SF"
  [ "$status" -ne 0 ]
}

@test "out-of-order recognized headings are REJECTED — stored WITHOUT summary_schema flag (I-069)" {
  # A recognized heading (### Decisions) appears BEFORE its canonical predecessor
  # (### What changed). The canonical order is What changed → Decisions → Open questions →
  # Files; the lenient four-in-order check silently treats the early ### Decisions as prose
  # and still reaches want==5, falsely stamping v2. A strict machine must reject it.
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
echo call >> "$CALLS"
cat > "$STDIN_SEEN"
echo "### Decisions"
echo "an out-of-order decisions heading before What changed"
echo "### What changed"
echo "edited the hook"
echo "### Decisions"
echo "use v2 schema"
echo "### Open questions"
echo "none"
echo "### Files"
echo "hooks/mb-session-end.sh"
EOF
  chmod +x "$STUB/claude"
  run bash -c "MB_SESSION_JUDGE=off CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  # Summary is still stored (fail-open).
  grep -q '## Summary' "$SF"
  # ...but the v2 flag must be ABSENT.
  run grep -q '^summary_schema' "$SF"
  [ "$status" -ne 0 ]
}

@test "valid in-order body with unrecognized ### lines + prose still passes as v2 (I-069 regression)" {
  # Unrecognized ### lines (e.g. a sub-heading the model invented) and ordinary prose must
  # NOT trip the state machine: a correctly-ordered, no-duplicate v2 body still earns the flag.
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
echo call >> "$CALLS"
cat > "$STDIN_SEEN"
echo "### What changed"
echo "edited the hook"
echo "### Some other note"
echo "an unrecognized sub-heading that is just prose"
echo "### Decisions"
echo "use v2 schema"
echo "### Open questions"
echo "none"
echo "### Files"
echo "hooks/mb-session-end.sh"
EOF
  chmod +x "$STUB/claude"
  run bash -c "MB_SESSION_JUDGE=off CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  grep -q '^summary_schema: v2' "$SF"
  grep -q '### What changed' "$SF"
  grep -q 'an unrecognized sub-heading that is just prose' "$SF"
}

@test "rebuild handles mixed legacy + v2 summaries (both appear in _recent.md)" {
  rm -f "$SF"
  legacy="$MB/session/2026-06-05_1000_deadbeef.md"
  cat > "$legacy" <<'EOF'
---
session_id: deadbeef-1111-2222
started: 2026-06-05T10:00Z
branch: main
turns: 2
summarized: true
---

## Summary
LEGACY SUMMARY TEXT.
EOF
  v2="$MB/session/2026-06-06_1200_cafef00d.md"
  cat > "$v2" <<'EOF'
---
session_id: cafef00d-3333-4444
started: 2026-06-06T12:00Z
branch: dev
turns: 3
summarized: true
summary_schema: v2
---

## Summary
### What changed
new schema landed
### Files
hooks/mb-session-end.sh
EOF
  run bash -c "bash '$REBUILD' '$MB'"
  [ "$status" -eq 0 ]
  grep -q 'LEGACY SUMMARY TEXT' "$MB/session/_recent.md"
  grep -q 'new schema landed' "$MB/session/_recent.md"
  grep -q 'cafef00d' "$MB/session/_recent.md"
  grep -q 'deadbeef' "$MB/session/_recent.md"
}
