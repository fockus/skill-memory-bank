#!/usr/bin/env bats
# mb-recap.sh — /mb recap <sid>: reconstruct a full progress entry from a session
# file via ONE Haiku call, replacing the auto-capture stub idempotently.
# Covers spec tier1-graph-memory REQ-020, REQ-021 + Scenario 8. `claude` is mocked.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-recap.sh"
  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/session"

  SID8="431491af"
  SID_FULL="431491af-0bc4-476b-a223-a1ffcd4027dc"
  SF="$MB/session/2026-06-11_2030_${SID8}.md"
  cat > "$SF" <<EOF
---
session_id: $SID_FULL
transcript: $PROJECT/t.jsonl
started: 2026-06-11T17:30Z
branch: main
turns: 3
summarized: true
---

## Live log
- 20:30 — User: "add the recap command" · tools: Edit,Write,Bash · files: scripts/mb-recap.sh

## Summary
### What changed
- Added scripts/mb-recap.sh
### Decisions
- (none)
### Open questions
- (none)
### Files
- scripts/mb-recap.sh
EOF

  # progress.md with an auto-capture STUB for this session (mb session-end-autosave format)
  PROGRESS="$MB/progress.md"
  cat > "$PROGRESS" <<EOF
# Progress Log

## 2026-06-10 (earlier real entry)

- A real, immutable entry that must never be touched.

## 2026-06-11

### Auto-capture 2026-06-11 (session ${SID8})
- Session ended without an explicit /mb done
- Summary auto-captured to session/ (searchable via /mb recall); core files were not actualized
EOF

  # Mock claude: record calls + stdin, emit a deterministic recap body.
  STUB="$PROJECT/bin"; mkdir -p "$STUB"
  CALLS="$PROJECT/calls"; STDIN_SEEN="$PROJECT/stdin_seen"
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
echo call >> "$CALLS"
cat > "$STDIN_SEEN"
echo "- MOCK RECAP: added the recap command (scripts/mb-recap.sh)"
EOF
  chmod +x "$STUB/claude"
  CLAUDE="$STUB/claude"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

# ── Scenario 8 part 1: first run replaces the stub with a full entry ──────────
@test "recap: first run replaces the auto-capture stub with a generated entry (REQ-020)" {
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" 2026-06-11 "$MB"
  [ "$status" -eq 0 ]
  # one and only one Haiku call
  [ "$(wc -l < "$CALLS" | tr -d ' ')" -eq 1 ]
  # stub line is gone, generated content is in
  ! grep -q 'Session ended without an explicit /mb done' "$PROGRESS"
  grep -q 'MOCK RECAP' "$PROGRESS"
  # the day heading above the stub survives the replacement
  grep -q '^## 2026-06-11$' "$PROGRESS"
  # the older real entry is untouched
  grep -q 'A real, immutable entry that must never be touched.' "$PROGRESS"
  # session file is flagged recapped
  grep -q 'recapped: true' "$SF"
  # the session content reached the prompt
  grep -q 'Added scripts/mb-recap.sh' "$STDIN_SEEN"
}

# ── Scenario 8 part 2: rerun is a no-op (idempotent) ─────────────────────────
@test "recap: second run on a recapped session is a no-op (REQ-020 idempotency)" {
  env CLAUDE="$CLAUDE" bash "$SCRIPT" 2026-06-11 "$MB" >/dev/null
  before="$(md5 -q "$PROGRESS" 2>/dev/null || md5sum "$PROGRESS" | awk '{print $1}')"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" 2026-06-11 "$MB"
  [ "$status" -eq 0 ]
  # no second claude call
  [ "$(wc -l < "$CALLS" | tr -d ' ')" -eq 1 ]
  # progress.md unchanged on the rerun
  after="$(md5 -q "$PROGRESS" 2>/dev/null || md5sum "$PROGRESS" | awk '{print $1}')"
  [ "$before" = "$after" ]
  echo "$output" | grep -qi 'already recapped'
}

# ── Scenario 8 part 3: missing session → exit 2, progress.md untouched ────────
@test "recap: missing session file exits 2 and leaves progress.md untouched (REQ-021)" {
  before="$(md5 -q "$PROGRESS" 2>/dev/null || md5sum "$PROGRESS" | awk '{print $1}')"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" 2099-01-01 "$MB"
  [ "$status" -eq 2 ]
  # no claude call, byte-identical progress.md
  [ ! -f "$CALLS" ]
  after="$(md5 -q "$PROGRESS" 2>/dev/null || md5sum "$PROGRESS" | awk '{print $1}')"
  [ "$before" = "$after" ]
}

# ── Refuse when a REAL (non-stub) entry already exists for the session ────────
@test "recap: refuses when a real entry already exists for the session, no writes (REQ-020)" {
  # Replace the stub block with a real, non-stub entry referencing the same sid8.
  cat > "$PROGRESS" <<EOF
# Progress Log

## 2026-06-11

### Recap 2026-06-11 (session ${SID8})
- This is a real entry written by /mb done; not a stub.
EOF
  before="$(md5 -q "$PROGRESS" 2>/dev/null || md5sum "$PROGRESS" | awk '{print $1}')"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" 2026-06-11 "$MB"
  [ "$status" -ne 0 ]
  [ ! -f "$CALLS" ]
  echo "$output" | grep -qi 'already'
  after="$(md5 -q "$PROGRESS" 2>/dev/null || md5sum "$PROGRESS" | awk '{print $1}')"
  [ "$before" = "$after" ]
}

# ── No claude binary → install hint, exit 3, no writes ───────────────────────
@test "recap: missing claude binary prints a hint, exits 3, no writes (claude-absent guard)" {
  before="$(md5 -q "$PROGRESS" 2>/dev/null || md5sum "$PROGRESS" | awk '{print $1}')"
  run env CLAUDE="$PROJECT/nope-claude" bash "$SCRIPT" 2026-06-11 "$MB"
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi 'claude'
  # stub stays intact, no generated content
  grep -q 'Session ended without an explicit /mb done' "$PROGRESS"
  ! grep -q 'recapped: true' "$SF"
  after="$(md5 -q "$PROGRESS" 2>/dev/null || md5sum "$PROGRESS" | awk '{print $1}')"
  [ "$before" = "$after" ]
}

# ── No stub at all (clean progress.md, no entry for the sid) → exit 4, no writes
@test "recap: no stub and no entry for the session → exit 4, no writes" {
  cat > "$PROGRESS" <<EOF
# Progress Log

## 2026-06-10 (unrelated)

- Nothing about this session here.
EOF
  before="$(md5 -q "$PROGRESS" 2>/dev/null || md5sum "$PROGRESS" | awk '{print $1}')"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" 2026-06-11 "$MB"
  [ "$status" -eq 4 ]
  [ ! -f "$CALLS" ]
  after="$(md5 -q "$PROGRESS" 2>/dev/null || md5sum "$PROGRESS" | awk '{print $1}')"
  [ "$before" = "$after" ]
}

# ── Missing progress.md → exit 2, no writes (do not create it) ───────────────
@test "recap: missing progress.md exits 2 without creating it" {
  rm -f "$PROGRESS"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" 2026-06-11 "$MB"
  [ "$status" -eq 2 ]
  [ ! -f "$PROGRESS" ]
  [ ! -f "$CALLS" ]
}

# ── Usage when no sid given ──────────────────────────────────────────────────
@test "recap: no sid argument → usage, non-zero" {
  run env CLAUDE="$CLAUDE" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'usage'
}

# ── API error from the Haiku call → exit 5, progress.md & session untouched ───
@test "recap: error-shaped Haiku response → exit 5, no writes, not recapped" {
  # Stub claude to emit an API error string instead of a recap body.
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
echo call >> "$CALLS"
cat > "$STDIN_SEEN"
echo "API Error: overloaded_error"
EOF
  chmod +x "$STUB/claude"
  before="$(md5 -q "$PROGRESS" 2>/dev/null || md5sum "$PROGRESS" | awk '{print $1}')"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" 2026-06-11 "$MB"
  [ "$status" -eq 5 ]
  # progress.md byte-identical — the error response was never persisted
  after="$(md5 -q "$PROGRESS" 2>/dev/null || md5sum "$PROGRESS" | awk '{print $1}')"
  [ "$before" = "$after" ]
  # the session was NOT flagged recapped, so a retry is possible
  ! grep -q 'recapped: true' "$SF"
}

# ── Ambiguous sid (same date prefix matches two sessions) → exit 2, no writes ─
@test "recap: ambiguous sid matching multiple sessions → exit 2, lists files, no writes" {
  # A SECOND session on the same date — both files match the '2026-06-11'* glob.
  SID8B="b2c3d4e5"
  SFB="$MB/session/2026-06-11_2200_${SID8B}.md"
  cat > "$SFB" <<EOF
---
session_id: ${SID8B}-1111-2222-3333-444455556666
started: 2026-06-11T22:00Z
turns: 1
summarized: true
---

## Summary
### Files
- scripts/other.sh
EOF
  before="$(md5 -q "$PROGRESS" 2>/dev/null || md5sum "$PROGRESS" | awk '{print $1}')"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" 2026-06-11 "$MB"
  [ "$status" -eq 2 ]
  # both candidate session files are listed on stderr so the user can disambiguate
  echo "$output" | grep -q "$(basename "$SF")"
  echo "$output" | grep -q "$(basename "$SFB")"
  # no claude call recorded, progress.md byte-identical, neither session recapped
  [ ! -f "$CALLS" ]
  after="$(md5 -q "$PROGRESS" 2>/dev/null || md5sum "$PROGRESS" | awk '{print $1}')"
  [ "$before" = "$after" ]
  ! grep -q 'recapped: true' "$SF"
  ! grep -q 'recapped: true' "$SFB"
}

# ── Exact sid8 disambiguates among same-date candidates (full match wins) ─────
@test "recap: exact sid8 selects the right session even when a date prefix is ambiguous" {
  # Second same-date session, as above — but now address the FIRST by its exact sid8.
  SID8B="b2c3d4e5"
  SFB="$MB/session/2026-06-11_2200_${SID8B}.md"
  cat > "$SFB" <<EOF
---
session_id: ${SID8B}-1111-2222-3333-444455556666
started: 2026-06-11T22:00Z
turns: 1
summarized: true
---

## Summary
### Files
- scripts/other.sh
EOF
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$SID8" "$MB"
  [ "$status" -eq 0 ]
  # exactly the requested session was recapped, the other left alone
  grep -q 'recapped: true' "$SF"
  ! grep -q 'recapped: true' "$SFB"
}

# ── Duplicate EXACT sid8 matches (resumed session across dates) must refuse ──
@test "recap: two files with the same sid8 → exit 2, lists both, no writes" {
  # A second file carrying the SAME sid8 (a session resumed past midnight):
  # both match the exact *_<sid8>.md pattern — exact-match preference must
  # NOT silently pick the first; it must refuse like any other ambiguity.
  SFB="$MB/session/2026-06-12_0010_${SID8}.md"
  cat > "$SFB" <<EOG
---
session_id: ${SID8}-1111-2222-3333-444455556666
started: 2026-06-12T00:10Z
turns: 1
summarized: true
---

## Summary
### Files
- scripts/other.sh
EOG
  before="$(md5 -q "$PROGRESS" 2>/dev/null || md5sum "$PROGRESS" | awk '{print $1}')"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$SID8" "$MB"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "$(basename "$SF")"
  echo "$output" | grep -q "$(basename "$SFB")"
  [ ! -f "$CALLS" ]
  after="$(md5 -q "$PROGRESS" 2>/dev/null || md5sum "$PROGRESS" | awk '{print $1}')"
  [ "$before" = "$after" ]
  ! grep -q 'recapped: true' "$SF"
  ! grep -q 'recapped: true' "$SFB"
}
