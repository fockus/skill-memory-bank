#!/usr/bin/env bats
# Stage 6 — `hooks/file-change-log.sh` writes to `$HOME/.claude/file-changes.log`.
# That log can contain paths to files the user is editing, so it must be
# owner-only (mode 600). The same goes for rotated log copies.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/file-change-log.sh"
  TMP="$(mktemp -d)"
  export HOME="$TMP"
  mkdir -p "$TMP/.claude"
  TARGET="$TMP/some-file.py"
  echo "x = 1" > "$TARGET"
  command -v jq >/dev/null 2>&1 || skip "jq required"
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

_perm() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
}

@test "file-change-log: created log has owner-only perms (600)" {
  echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TARGET\"}}" \
    | bash "$HOOK"
  [ -f "$HOME/.claude/file-changes.log" ]
  perm=$(_perm "$HOME/.claude/file-changes.log")
  [ "$perm" = "600" ]
}

@test "file-change-log: rotated copies inherit 600 perms" {
  # Pre-create an oversized log to force rotation on next call.
  LOG="$HOME/.claude/file-changes.log"
  : > "$LOG"
  # 11 MB > 10 MB threshold
  dd if=/dev/zero of="$LOG" bs=1024 count=11264 status=none 2>/dev/null
  chmod 644 "$LOG"  # simulate pre-fix legacy state

  echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TARGET\"}}" \
    | bash "$HOOK"

  [ -f "$LOG.1" ]
  perm_main=$(_perm "$LOG")
  perm_rot=$(_perm "$LOG.1")
  [ "$perm_main" = "600" ]
  [ "$perm_rot" = "600" ]
}
