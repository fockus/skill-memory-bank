#!/usr/bin/env bats
# Stage 2 — mb-session-turn.sh (Stop hook): per-turn bullet + frontmatter + guards.

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$BIN/mb-session-turn.sh"
  FIX="$BATS_TEST_DIRNAME/fixtures"
  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"
  mkdir -p "$PROJ/.memory-bank"
  cp "$FIX/transcript-two-turns.jsonl" "$TMP/t.jsonl"
}
teardown() { rm -rf "$TMP"; }

# Helper: build a Stop payload JSON into $TMP/in.json
_payload() { # $1=stop_hook_active
  printf '{"cwd":"%s","session_id":"af0a3685-3ee9-4db8","transcript_path":"%s","stop_hook_active":%s}' \
    "$PROJ" "$TMP/t.jsonl" "${1:-false}" > "$TMP/in.json"
}

@test "stop hook appends one bullet + frontmatter (REQ-SM-001, REQ-SM-013)" {
  _payload false
  run bash -c "bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  sf="$(ls "$PROJ/.memory-bank/session/"*.md)"
  grep -q 'User: "second request please"' "$sf"
  grep -q 'tools: Bash,Edit' "$sf"
  grep -q 'files: a.ts' "$sf"
  grep -q "transcript: $TMP/t.jsonl" "$sf"
  grep -q 'turns: 1' "$sf"
  # exactly one Live-log bullet
  [ "$(grep -c '^- ' "$sf")" -eq 1 ]
}

@test "two turns append two bullets, turns=2" {
  _payload false
  bash "$HOOK" < "$TMP/in.json"
  bash "$HOOK" < "$TMP/in.json"
  sf="$(ls "$PROJ/.memory-bank/session/"*.md)"
  [ "$(grep -c '^- ' "$sf")" -eq 2 ]
  grep -q 'turns: 2' "$sf"
}

@test "duplicate Stop for same turn deduped by uuid (double-registration safe)" {
  cp "$FIX/transcript-with-uuid.jsonl" "$TMP/u.jsonl"
  printf '{"cwd":"%s","session_id":"af0a3685-3ee9-4db8","transcript_path":"%s","stop_hook_active":false}' \
    "$PROJ" "$TMP/u.jsonl" > "$TMP/inu.json"
  bash "$HOOK" < "$TMP/inu.json"
  bash "$HOOK" < "$TMP/inu.json"
  sf="$(ls "$PROJ/.memory-bank/session/"*.md)"
  [ "$(grep -c '^- ' "$sf")" -eq 1 ]
  grep -q 'turns: 1' "$sf"
  # anchor is the last REAL user message uuid (u-1), not the transcript's last-line uuid
  grep -q 'last_turn: u-1' "$sf"
}

@test "duplicate Stop deduped when transcript's last line is a uuid-less record (real permission-mode/summary tail)" {
  # Real transcripts often end with a uuid-less record (permission-mode, summary), so a dedup
  # key taken from the LAST line is empty and never matches → project-local + global Stop
  # registrations double-logged the turn. Anchor on the last REAL user message uuid instead.
  cp "$FIX/transcript-trailing-meta.jsonl" "$TMP/m.jsonl"
  printf '{"cwd":"%s","session_id":"af0a3685-3ee9-4db8","transcript_path":"%s","stop_hook_active":false}' \
    "$PROJ" "$TMP/m.jsonl" > "$TMP/inm.json"
  bash "$HOOK" < "$TMP/inm.json"
  bash "$HOOK" < "$TMP/inm.json"
  bash "$HOOK" < "$TMP/inm.json"
  sf="$(ls "$PROJ/.memory-bank/session/"*.md)"
  [ "$(grep -c '^- ' "$sf")" -eq 1 ]
  grep -q 'turns: 1' "$sf"
  grep -q 'last_turn: user-7' "$sf"
}

@test "turn in a later clock-minute appends to the existing session file, not a new one (REQ-SM-001)" {
  # Simulate turn 1 captured at an earlier minute (filename 0900), same session_id.
  # The hook must locate the file by session_id — not re-derive the path from the
  # current wall-clock minute — so a minute boundary never splits one session.
  mkdir -p "$PROJ/.memory-bank/session"
  pre="$PROJ/.memory-bank/session/2026-06-06_0900_af0a3685.md"
  {
    printf -- '---\n'
    printf 'session_id: af0a3685-3ee9-4db8\n'
    printf 'transcript: %s\n' "$TMP/t.jsonl"
    printf 'started: 2026-06-06T09:00Z\nbranch: -\nturns: 1\nlast_turn: zzz-old\nsummarized: false\n'
    printf -- '---\n\n## Live log\n'
    printf -- '- 09:00 — User: "first request" · tools: (none) · files: (none)\n'
  } > "$pre"
  _payload false
  run bash -c "bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  # still exactly ONE session file for this session_id (no minute-boundary split)
  [ "$(ls "$PROJ/.memory-bank/session/"*.md | wc -l | tr -d ' ')" -eq 1 ]
  # the new bullet was appended to the pre-existing file → 2 bullets, turns=2
  [ "$(grep -c '^- ' "$pre")" -eq 2 ]
  grep -q 'turns: 2' "$pre"
}

@test "clean turn bullet carries outcome 'ok' (REQ-009)" {
  _payload false
  run bash -c "bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  sf="$(ls "$PROJ/.memory-bank/session/"*.md)"
  grep -q '· ok' "$sf"
  # no failed tool calls in this transcript → never err(N)
  if grep -q '· err(' "$sf"; then false; fi
}

@test "failed tool call → bullet carries err(N) outcome (REQ-009)" {
  cp "$FIX/transcript-tool-error.jsonl" "$TMP/e.jsonl"
  printf '{"cwd":"%s","session_id":"af0a3685-3ee9-4db8","transcript_path":"%s","stop_hook_active":false}' \
    "$PROJ" "$TMP/e.jsonl" > "$TMP/ine.json"
  run bash -c "bash '$HOOK' < '$TMP/ine.json'"
  [ "$status" -eq 0 ]
  sf="$(ls "$PROJ/.memory-bank/session/"*.md)"
  grep -q '· err(1)' "$sf"
  if grep -q '· ok' "$sf"; then false; fi
}

@test "non-git project → no diffstat segment, exit 0 (REQ-009)" {
  # $PROJ has a .memory-bank but is NOT a git work tree → diffstat must be absent.
  _payload false
  run bash -c "bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  sf="$(ls "$PROJ/.memory-bank/session/"*.md)"
  # no aggregate diffstat segment when outside a git repo
  if grep -qE '· \+[0-9]+/-[0-9]+' "$sf"; then false; fi
}

@test "git work tree with changes → bullet carries EXACT +A/-B diffstat (REQ-009)" {
  command -v git >/dev/null || skip "git required"
  git -C "$PROJ" init -q
  git -C "$PROJ" config user.email t@t.t
  git -C "$PROJ" config user.name t
  printf 'line one\nline two\n' > "$PROJ/tracked.txt"
  git -C "$PROJ" add tracked.txt
  git -C "$PROJ" commit -qm init
  # Unstaged edit with KNOWN counts: numstat reports the file as +2/-1
  # (git numstat counts modified-line as one add + one delete, plus the new line):
  #   - "line one"  → "line one CHANGED"  (1 del, 1 add)
  #   - "line three" appended             (1 add)
  # → +2/-1. Assert the EXACT value so an always-"+0/-0" impl fails.
  printf 'line one CHANGED\nline two\nline three\n' > "$PROJ/tracked.txt"
  expected="$(git -C "$PROJ" diff --numstat \
    | awk '{a+=($1=="-"?0:$1); d+=($2=="-"?0:$2)} END{printf "+%d/-%d", a, d}')"
  [ "$expected" = "+2/-1" ]
  _payload false
  run bash -c "bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  sf="$(ls "$PROJ/.memory-bank/session/"*.md)"
  grep -qF "· +2/-1" "$sf"
}

@test "bare repo → no diffstat segment, exit 0 (REQ-009)" {
  # A bare repo is not a work tree → `git diff` fails there, so the segment must be
  # omitted entirely (an --is-inside-work-tree probe wrongly prints "false" + exits 0,
  # which would emit a spurious +0/-0). CWD points AT the bare repo dir.
  command -v git >/dev/null || skip "git required"
  bare="$TMP/bare.git"
  git init --bare -q "$bare"
  mkdir -p "$bare/.memory-bank"
  printf '{"cwd":"%s","session_id":"af0a3685-3ee9-4db8","transcript_path":"%s","stop_hook_active":false}' \
    "$bare" "$TMP/t.jsonl" > "$TMP/inb.json"
  run bash -c "bash '$HOOK' < '$TMP/inb.json'"
  [ "$status" -eq 0 ]
  sf="$(ls "$bare/.memory-bank/session/"*.md)"
  # bullet present, but NO diffstat segment in a bare repo
  [ "$(grep -c '^- ' "$sf")" -eq 1 ]
  if grep -qE '· \+[0-9]+/-[0-9]+' "$sf"; then false; fi
}

@test "stop_hook_active=true → exit 0, nothing written (REQ-SM-014)" {
  _payload true
  run bash -c "bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ ! -e "$PROJ/.memory-bank/session" ]
}

@test "MB_CAPTURE_SUBPROCESS=1 → exit 0, nothing written (REQ-SM-006)" {
  _payload false
  run bash -c "MB_CAPTURE_SUBPROCESS=1 bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ ! -e "$PROJ/.memory-bank/session" ]
}

@test "MB_SESSION_CAPTURE=off → exit 0, nothing written (REQ-SM-009)" {
  _payload false
  run bash -c "MB_SESSION_CAPTURE=off bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ ! -e "$PROJ/.memory-bank/session" ]
}

@test "missing jq → exit 0, nothing written (REQ-SM-007)" {
  _payload false
  run bash -c "JQ=__definitely_not_jq__ bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  [ ! -e "$PROJ/.memory-bank/session" ]
}

@test "unresolved MB (no .memory-bank) → exit 0" {
  mkdir -p "$TMP/nobank"
  printf '{"cwd":"%s","session_id":"x","transcript_path":"%s","stop_hook_active":false}' \
    "$TMP/nobank" "$TMP/t.jsonl" > "$TMP/in.json"
  run bash -c "bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
}
