#!/usr/bin/env bats
# extract-tools-files.sh — user-text cap (A3) + non-human turn filtering (A4).

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  EXTRACT="$BIN/lib/extract-tools-files.sh"
  TMP="$(mktemp -d)"
}
teardown() { rm -rf "$TMP"; }

# Write a transcript whose ONLY user turn is $1 (raw text). Extra records via stdin heredoc.
_one_user_turn() { # $1=text  → $TMP/x.jsonl
  python3 - "$1" > "$TMP/x.jsonl" <<'PY'
import json, sys
print(json.dumps({"type": "user", "uuid": "u-1",
                  "message": {"role": "user", "content": [{"type": "text", "text": sys.argv[1]}]}}))
PY
}
_user_val() { sed -n 's/^user=//p' <<<"$1"; }

# --- A3: user-prompt cap raised to 1000 + ellipsis on truncation ---

@test "A3: user text capped at 1000 chars with trailing … on truncation" {
  _one_user_turn "$(printf 'X%.0s' $(seq 1 5000))"
  out="$(bash "$EXTRACT" "$TMP/x.jsonl")"
  val="$(_user_val "$out")"
  [ "${#val}" -le 1001 ]        # 1000 cap + 1 ellipsis char
  [ "${#val}" -ge 1001 ]        # actually truncated (not left at old 200)
  case "$val" in *…) : ;; *) false ;; esac
}

@test "A3: short prompt under cap is unchanged (no ellipsis)" {
  _one_user_turn "hello world please"
  out="$(bash "$EXTRACT" "$TMP/x.jsonl")"
  val="$(_user_val "$out")"
  [ "$val" = "hello world please" ]
  if printf '%s' "$val" | grep -q '…'; then false; fi
}

@test "A3: MB_SESSION_USER_MAX override honoured" {
  _one_user_turn "$(printf 'Y%.0s' $(seq 1 5000))"
  out="$(MB_SESSION_USER_MAX=50 bash "$EXTRACT" "$TMP/x.jsonl")"
  val="$(_user_val "$out")"
  [ "${#val}" -eq 51 ]          # 50 + ellipsis
  case "$val" in *…) : ;; *) false ;; esac
}

# --- A4: whole-message service wrappers are not real turns ---

@test "A4: pure <task-notification> turn falls back to the previous REAL user message" {
  python3 - > "$TMP/x.jsonl" <<'PY'
import json
recs = [
  {"type":"user","uuid":"u-real","message":{"role":"user","content":[{"type":"text","text":"the real user question"}]}},
  {"type":"assistant","uuid":"a-1","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}},
  {"type":"user","uuid":"u-notif","message":{"role":"user","content":[{"type":"text","text":"<task-notification>a subagent finished</task-notification>"}]}},
]
for r in recs: print(json.dumps(r))
PY
  out="$(bash "$EXTRACT" "$TMP/x.jsonl")"
  [ "$(_user_val "$out")" = "the real user question" ]
  [ "$(sed -n 's/^turn=//p' <<<"$out")" = "u-real" ]
}

@test "A4: bare <system-reminder> only turn is skipped (no real turn)" {
  _one_user_turn "<system-reminder>background context injected by the harness</system-reminder>"
  out="$(bash "$EXTRACT" "$TMP/x.jsonl")"
  [ -z "$(_user_val "$out")" ]
  [ -z "$(sed -n 's/^turn=//p' <<<"$out")" ]
}

@test "A4: human prose that merely mentions the word system-reminder is kept" {
  _one_user_turn "explain how the system-reminder mechanism works in practice"
  out="$(bash "$EXTRACT" "$TMP/x.jsonl")"
  [ "$(_user_val "$out")" = "explain how the system-reminder mechanism works in practice" ]
}

@test "A4: leading command wrapper prefix stripped from otherwise-human text" {
  _one_user_turn "<command-name>/mb</command-name><command-args>work plan.md</command-args> then fix the bug"
  out="$(bash "$EXTRACT" "$TMP/x.jsonl")"
  [ "$(_user_val "$out")" = "then fix the bug" ]
}

@test "A4: filtering is opt-out via MB_SESSION_FILTER_WRAPPERS=off" {
  _one_user_turn "<task-notification>a subagent finished</task-notification>"
  out="$(MB_SESSION_FILTER_WRAPPERS=off bash "$EXTRACT" "$TMP/x.jsonl")"
  # with filtering off the wrapper message is kept as a turn (old behaviour)
  printf '%s' "$(_user_val "$out")" | grep -q 'subagent finished'
}

# --- review-fix: user text is redacted BEFORE the A3 cap (secret never split) ---

@test "A3/sec: a secret in the prompt is redacted before the length cap (no partial leak)" {
  # a cap that would cut through the middle of the token must not leak a raw fragment
  _one_user_turn "PREFIX sk-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA SUFFIX"
  out="$(MB_SESSION_USER_MAX=15 bash "$EXTRACT" "$TMP/x.jsonl")"
  val="$(_user_val "$out")"
  if printf '%s' "$val" | grep -q 'sk-A'; then false; fi   # no raw secret fragment
}
