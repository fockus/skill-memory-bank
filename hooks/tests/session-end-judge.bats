#!/usr/bin/env bats
# Stage 4 — mb-session-end.sh step 2: Sonnet judge + judge-gate → 0–2 notes. claude mocked.

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$BIN/mb-session-end.sh"
  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"; MB="$PROJ/.memory-bank"
  mkdir -p "$MB/session" "$MB/notes"
  CALLS="$TMP/calls"; NOTES_JSON="$TMP/notes.json"
  printf '[]' > "$NOTES_JSON"
  STUB="$TMP/bin"; mkdir -p "$STUB"
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
model=""
while [ \$# -gt 0 ]; do case "\$1" in --model) model="\$2"; shift;; esac; shift; done
cat > /dev/null
echo "\$model" >> "$CALLS"
case "\$model" in
  *haiku*)  echo "MOCK SUMMARY" ;;
  *sonnet*) cat "$NOTES_JSON" ;;
  *)        echo "" ;;
esac
EOF
  chmod +x "$STUB/claude"
  CLAUDE="$STUB/claude"
  printf '{"cwd":"%s","session_id":"af0a3685-3ee9-4db8"}' "$PROJ" > "$TMP/in.json"
}
teardown() { rm -rf "$TMP"; }

# write a session file with given tools-string and turns
_mksf() { # $1=tools $2=turns
  SF="$MB/session/2026-06-06_1835_af0a3685.md"
  cat > "$SF" <<EOF
---
session_id: af0a3685-3ee9-4db8
transcript:
started: 2026-06-06T18:35Z
branch: dev
turns: ${2}
summarized: false
---

## Live log
- 18:36 — User: "x" · tools: ${1} · files: (none)
EOF
}

@test "significant (Edit) + 2 notes → 2 files linked, sonnet called (REQ-SM-003)" {
  _mksf "Bash,Edit" 2
  printf '[{"title":"Pattern X","body":"do this"},{"title":"Gotcha Y","body":"beware"}]' > "$NOTES_JSON"
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ "$(ls "$MB/notes/"*.md 2>/dev/null | wc -l | tr -d ' ')" -eq 2 ]
  grep -q '## Auto-notes emitted' "$SF"
  [ "$(grep -c '^- notes/' "$SF")" -eq 2 ]
  grep -q sonnet "$CALLS"
}

@test "trivial (no Write/Edit, turns<min) → judge NOT called, 0 notes (REQ-SM-003 gate)" {
  _mksf "(none)" 1
  printf '[{"title":"should not appear","body":"x"}]' > "$NOTES_JSON"
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ "$(ls "$MB/notes/"*.md 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
  ! grep -q sonnet "$CALLS"
  grep -q haiku "$CALLS"
}

@test "judge returns [] → 0 notes, no Auto-notes section" {
  _mksf "Bash,Edit" 2
  printf '[]' > "$NOTES_JSON"
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ "$(ls "$MB/notes/"*.md 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
  ! grep -q '## Auto-notes emitted' "$SF"
  grep -q sonnet "$CALLS"
}

@test "turns>=min gates judge even without Write/Edit" {
  _mksf "(none)" 5
  printf '[{"title":"Decision Z","body":"because"}]' > "$NOTES_JSON"
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ "$(ls "$MB/notes/"*.md 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]
  grep -q sonnet "$CALLS"
}

@test "MB_SESSION_JUDGE=off → judge skipped even when significant, summary still written" {
  _mksf "Bash,Edit" 9
  printf '[{"title":"should not appear","body":"x"}]' > "$NOTES_JSON"
  run bash -c "MB_SESSION_JUDGE=off CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ "$(ls "$MB/notes/"*.md 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
  ! grep -q sonnet "$CALLS"
  grep -q haiku "$CALLS"
  grep -q '## Summary' "$SF"
}

@test ">2 notes returned are capped at 2" {
  _mksf "Write" 2
  printf '[{"title":"a","body":"1"},{"title":"b","body":"2"},{"title":"c","body":"3"}]' > "$NOTES_JSON"
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ "$(ls "$MB/notes/"*.md 2>/dev/null | wc -l | tr -d ' ')" -eq 2 ]
}

# ── Decoupled idempotency: `summarized` (Haiku) and `judged` (Sonnet) are independent flags ──
# Regression for the coupling bug: a session summarized by an older hook version, or one whose
# judge was killed by the SessionEnd 180s budget, had summarized=true but was never judged —
# and the single shared `summarized` flag short-circuited the judge forever.

# write a session file with explicit summarized/judged state (+ a pre-existing ## Summary)
_mksf_state() { # $1=tools $2=turns $3=summarized $4=judged(optional)
  SF="$MB/session/2026-06-06_1835_af0a3685.md"
  {
    printf -- '---\n'
    printf 'session_id: af0a3685-3ee9-4db8\n'
    printf 'transcript:\n'
    printf 'started: 2026-06-06T18:35Z\n'
    printf 'branch: dev\n'
    printf 'turns: %s\n' "$2"
    printf 'summarized: %s\n' "$3"
    [ -n "${4:-}" ] && printf 'judged: %s\n' "$4"
    printf -- '---\n\n'
    printf '## Live log\n'
    printf -- '- 18:36 — User: "x" · tools: %s · files: (none)\n' "$1"
    [ "$3" = "true" ] && printf '\n## Summary\nPRE-EXISTING SUMMARY\n'
  } > "$SF"
}

@test "summarized=true but not judged → judge still runs, summary NOT regenerated (decoupled idempotency)" {
  _mksf_state "Bash,Edit" 2 true
  printf '[{"title":"Late Note","body":"recovered"}]' > "$NOTES_JSON"
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ "$(ls "$MB/notes/"*.md 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]
  grep -q '## Auto-notes emitted' "$SF"
  grep -q sonnet "$CALLS"
  ! grep -q haiku "$CALLS"                      # summary already done → not regenerated
  [ "$(grep -c '^## Summary' "$SF")" -eq 1 ]    # original summary not duplicated
  grep -q '^judged: true' "$SF"
}

@test "judged=true → judge NOT re-run, no duplicate notes (idempotent)" {
  _mksf_state "Bash,Edit" 2 true true
  printf '[{"title":"dup","body":"x"}]' > "$NOTES_JSON"
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ "$(ls "$MB/notes/"*.md 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
  ! grep -q sonnet "$CALLS"
}

@test "fresh significant session is marked judged=true after the judge runs" {
  _mksf "Bash,Edit" 2
  printf '[{"title":"X","body":"y"}]' > "$NOTES_JSON"
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  grep -q '^judged: true' "$SF"
}

@test "judge returns [] still marks judged=true (no infinite retry on a valid empty verdict)" {
  _mksf "Bash,Edit" 2
  printf '[]' > "$NOTES_JSON"
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ "$(ls "$MB/notes/"*.md 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
  grep -q '^judged: true' "$SF"
}

@test "unparseable judge output leaves judged unset (retry path for a killed/errored judge)" {
  _mksf "Bash,Edit" 2
  printf 'API Error: overloaded' > "$NOTES_JSON"   # sonnet emits garbage, not a JSON array
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ "$(ls "$MB/notes/"*.md 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
  grep -q '^summarized: true' "$SF"   # summary persisted...
  ! grep -q '^judged: true' "$SF"     # ...but judge stays retryable
}

@test "judge output prefixed with [MEMORY BANK: ACTIVE] preamble → array still extracted" {
  # The `claude -p` judge subprocess runs inside a project with .memory-bank/, so it obeys the
  # CLAUDE.md guard and prepends `[MEMORY BANK: ACTIVE]` before the JSON array. A plain jq parse
  # and a line-based sed both miss the array behind that preamble → notes were silently lost.
  _mksf "Bash,Edit" 2
  printf '[MEMORY BANK: ACTIVE]\n\n[{"title":"Recovered","body":"works despite preamble"}]' > "$NOTES_JSON"
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ "$(ls "$MB/notes/"*.md 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]
  grep -q '## Auto-notes emitted' "$SF"
  grep -q '^judged: true' "$SF"
}

@test "judge output with [MEMORY BANK: ACTIVE] preamble + empty [] → judged set, 0 notes" {
  _mksf "Bash,Edit" 2
  printf '[MEMORY BANK: ACTIVE]\n\n[]' > "$NOTES_JSON"
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ "$(ls "$MB/notes/"*.md 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
  ! grep -q '## Auto-notes emitted' "$SF"
  grep -q '^judged: true' "$SF"
}

@test "judge output wrapped in json code fences → array still extracted" {
  _mksf "Bash,Edit" 2
  printf '```json\n[{"title":"Fenced","body":"x"}]\n```' > "$NOTES_JSON"
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ "$(ls "$MB/notes/"*.md 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]
  grep -q '^judged: true' "$SF"
}
