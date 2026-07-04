#!/usr/bin/env bats
# mb-session-start.sh — SessionStart context injection: _recent.md hard-cap (A5).

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$BIN/mb-session-start.sh"
  TMP="$(mktemp -d)"; PROJ="$TMP/proj"
  mkdir -p "$PROJ/.memory-bank/session"
}
teardown() { rm -rf "$TMP"; }

# Run the hook and echo the injected additionalContext (cheatsheet + semantic off for isolation).
_ctx() {
  CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=off MB_SESSION_CHEATSHEET=off bash "$HOOK" \
    | jq -r '.hookSpecificOutput.additionalContext // empty'
}

@test "A5: bloated _recent.md injection is byte-capped + truncation marker" {
  head -c 20000 /dev/zero | tr '\0' 'x' > "$PROJ/.memory-bank/session/_recent.md"
  ctx="$(_ctx)"
  printf '%s' "$ctx" | grep -q '…\[recent truncated\]…'
  # bounded: 4000 cap + header + marker stays well under 4200 bytes
  [ "$(printf '%s' "$ctx" | wc -c)" -le 4200 ]
}

@test "A5: small _recent.md injected verbatim, no marker" {
  printf 'tiny recent log line\n' > "$PROJ/.memory-bank/session/_recent.md"
  ctx="$(_ctx)"
  printf '%s' "$ctx" | grep -q 'tiny recent log line'
  if printf '%s' "$ctx" | grep -q 'recent truncated'; then false; fi
}

@test "A5: MB_RECENT_MAX_BYTES override honoured" {
  head -c 20000 /dev/zero | tr '\0' 'y' > "$PROJ/.memory-bank/session/_recent.md"
  ctx="$(CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=off MB_SESSION_CHEATSHEET=off \
        MB_RECENT_MAX_BYTES=100 bash "$HOOK" | jq -r '.hookSpecificOutput.additionalContext // empty')"
  # cap 100 + header + marker → far below the default cap
  [ "$(printf '%s' "$ctx" | wc -c)" -le 400 ]
  printf '%s' "$ctx" | grep -q '…\[recent truncated\]…'
}
