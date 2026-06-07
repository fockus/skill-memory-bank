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
