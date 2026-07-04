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

# --- A1: bullets splice into Live log before ## Summary; resumed sessions re-summarize ---

# Seed an already-summarized session file for this session_id (af0a3685-3ee9-4db8).
# $1 extra frontmatter line (e.g. "judged: true") is optional.
_seed_summarized() {
  mkdir -p "$PROJ/.memory-bank/session"
  SEED="$PROJ/.memory-bank/session/2026-06-06_0900_af0a3685.md"
  {
    printf -- '---\n'
    printf 'session_id: af0a3685-3ee9-4db8\n'
    printf 'transcript: %s\n' "$TMP/t.jsonl"
    printf 'started: 2026-06-06T09:00Z\nbranch: -\nturns: 1\nlast_turn: zzz-old\n'
    printf 'summarized: true\n'
    [ -n "${1:-}" ] && printf '%s\n' "$1"
    printf -- '---\n\n## Live log\n'
    printf -- '- 09:00 — User: "first request" · tools: (none) · files: (none) · ok\n'
    printf -- '\n## Summary\nA one-line summary of turn 1 only.\n'
  } > "$SEED"
}

@test "A1: new bullet inserted INSIDE Live log, before ## Summary (not after EOF)" {
  _seed_summarized
  _payload false
  run bash -c "bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  # the new turn's bullet exists
  grep -q 'User: "second request please"' "$SEED"
  # and it lands BEFORE the ## Summary heading, not after it (line-number check)
  new_ln="$(grep -n 'second request please' "$SEED" | head -1 | cut -d: -f1)"
  sum_ln="$(grep -n '^## Summary' "$SEED" | head -1 | cut -d: -f1)"
  [ -n "$new_ln" ] && [ -n "$sum_ln" ]
  [ "$new_ln" -lt "$sum_ln" ]
  # nothing appended after the Summary body (last non-empty line is the summary text)
  [ "$(tail -1 "$SEED")" = "A one-line summary of turn 1 only." ]
}

@test "A1: resumed append resets summarized=false, leaves judged untouched" {
  _seed_summarized "judged: true"
  _payload false
  run bash -c "bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  grep -q '^summarized: false' "$SEED"
  grep -q '^judged: true' "$SEED"
}

@test "A1: sc_livelog_append preserves backslash sequences verbatim (byte-stable contract)" {
  # A bullet whose User text contains literal backslashes (regex/Windows path) must land
  # on ONE line with the backslashes intact — awk -v would interpret \n/\t/\d and corrupt it.
  . "$BIN/lib/session-common.sh"
  f="$TMP/ll.md"
  printf -- '---\ns: 1\n---\n\n## Live log\n' > "$f"
  txt='- 10:00 — User: "match \d+\n and C:\Users\x" · tools: Edit · files: a.go · ok'
  sc_livelog_append "$f" "$txt"
  # exactly one bullet line, byte-identical to the input (no escape interpretation, no split)
  [ "$(grep -c '^- ' "$f")" -eq 1 ]
  [ "$(grep '^- ' "$f")" = "$txt" ]
}

@test "A1: fresh session (no ## Summary) still appends to Live log at EOF (regression)" {
  _payload false
  run bash -c "bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  sf="$(ls "$PROJ/.memory-bank/session/"*.md)"
  [ "$(grep -c '^- ' "$sf")" -eq 1 ]
  grep -q 'turns: 1' "$sf"
  # fresh sessions start summarized:false and stay so (no reset side effect)
  grep -q '^summarized: false' "$sf"
}

# --- A2: hard caps on file-list length and whole-bullet length ---

# Write a transcript whose single turn touches $1 files named "<$2>NN.ts".
_make_files_jsonl() { # $1=count $2=name_prefix $3=prompt
  python3 - "$1" "$2" "$3" > "$TMP/mf.jsonl" <<'PY'
import json, sys
n = int(sys.argv[1]); pre = sys.argv[2]; prompt = sys.argv[3]
print(json.dumps({"type": "user", "uuid": "u-1",
                  "message": {"role": "user", "content": [{"type": "text", "text": prompt}]}}))
blocks = [{"type": "tool_use", "name": "Edit",
           "input": {"file_path": f"{pre}{i:02d}.ts"}} for i in range(n)]
print(json.dumps({"type": "assistant", "uuid": "a-1",
                  "message": {"role": "assistant", "content": blocks}}))
PY
}
_payload_mf() {
  printf '{"cwd":"%s","session_id":"af0a3685-3ee9-4db8","transcript_path":"%s","stop_hook_active":false}' \
    "$PROJ" "$TMP/mf.jsonl" > "$TMP/in.json"
}

@test "A2: files list capped to 12 entries + accurate '+K more' suffix" {
  _make_files_jsonl 25 "a" "short prompt"   # short paths → bullet stays well under 600
  _payload_mf
  run bash -c "bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  sf="$(ls "$PROJ/.memory-bank/session/"*.md)"
  bl="$(grep '^- ' "$sf" | tail -1)"
  # 25 files, cap 12 → 13 dropped
  printf '%s' "$bl" | grep -q ' +13 more'
  # the 12th kept file present, the 13th (a12.ts) dropped
  printf '%s' "$bl" | grep -q 'a11.ts'
  if printf '%s' "$bl" | grep -q 'a12.ts'; then false; fi
}

@test "A2: whole bullet truncated to MB_SESSION_BULLET_MAX with trailing …, prefix intact" {
  _make_files_jsonl 25 "/Users/fockus/Apps/proj/src/module/component/verylongfilename_" "short"
  _payload_mf
  run bash -c "bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  sf="$(ls "$PROJ/.memory-bank/session/"*.md)"
  bl="$(grep '^- ' "$sf" | tail -1)"
  # ends with the ellipsis (truncation happened), prefix contract preserved
  case "$bl" in *…) : ;; *) false ;; esac
  case "$bl" in '- '*'User: "'*) : ;; *) false ;; esac
  # the pre-ellipsis body is EXACTLY the cap (measured with bash's own unit, so this holds
  # whether the cut was char- or byte-based — same measure the hook uses to slice)
  stripped="${bl%…}"
  [ "$bl" != "$stripped" ]
  [ "${#stripped}" -eq 600 ]
}

@test "A2: caps are opt-out via MB_SESSION_MAX_FILES / MB_SESSION_BULLET_MAX" {
  _make_files_jsonl 25 "/Users/fockus/Apps/proj/src/module/component/verylongfilename_" "short"
  _payload_mf
  run bash -c "MB_SESSION_MAX_FILES=999 MB_SESSION_BULLET_MAX=99999 bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  sf="$(ls "$PROJ/.memory-bank/session/"*.md)"
  bl="$(grep '^- ' "$sf" | tail -1)"
  # all 25 files present, no truncation, no '+K more'
  printf '%s' "$bl" | grep -q 'verylongfilename_24.ts'
  if printf '%s' "$bl" | grep -q ' more'; then false; fi
  if printf '%s' "$bl" | grep -q '…'; then false; fi
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

@test "stub guard: contentless first turn creates NO session file (Stage 4)" {
  : > "$TMP/empty.jsonl"
  printf '{"cwd":"%s","session_id":"af0a3685-3ee9-4db8","transcript_path":"%s","stop_hook_active":false}' \
    "$PROJ" "$TMP/empty.jsonl" > "$TMP/ine.json"
  run bash -c "bash '$HOOK' < '$TMP/ine.json'"
  [ "$status" -eq 0 ]
  [ -z "$(ls "$PROJ/.memory-bank/session/"*.md 2>/dev/null)" ]
}

@test "stub guard OFF: contentless first turn still creates the file (back-compat)" {
  : > "$TMP/empty.jsonl"
  printf '{"cwd":"%s","session_id":"af0a3685-3ee9-4db8","transcript_path":"%s","stop_hook_active":false}' \
    "$PROJ" "$TMP/empty.jsonl" > "$TMP/ine.json"
  run bash -c "MB_SESSION_STUB_GUARD=off bash '$HOOK' < '$TMP/ine.json'"
  [ "$status" -eq 0 ]
  sf="$(ls "$PROJ/.memory-bank/session/"*.md)"
  [ -f "$sf" ]
}

@test "stub guard: substantive first turn DOES create the file" {
  _payload false
  run bash -c "bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]
  sf="$(ls "$PROJ/.memory-bank/session/"*.md)"
  [ -f "$sf" ]
  grep -q 'User: "second request please"' "$sf"
}
