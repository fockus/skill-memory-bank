#!/usr/bin/env bats
# Security: file-change-log must not echo secret values to stderr.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME:-$(dirname "$BATS_TEST_FILENAME")}/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/file-change-log.sh"
  TMP="$(mktemp -d)"
  export HOME="$TMP"
  mkdir -p "$TMP/.claude"
  TARGET="$TMP/leak.py"
  command -v jq >/dev/null 2>&1 || skip "jq required"
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

@test "file_change_log: redacts secret value on stderr" {
  cat > "$TARGET" <<'PY'
api_key = "supersecretvalue12345"
PY
  run bash -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TARGET\"}}' | bash '$HOOK' 2>&1"
  [[ "$output" == *"[REDACTED]"* ]]
  [[ ! "$output" == *"supersecretvalue12345"* ]]
}

@test "file_change_log: still warns on secret presence" {
  cat > "$TARGET" <<'PY'
api_key = "supersecretvalue12345"
PY
  run bash -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TARGET\"}}' | bash '$HOOK' 2>&1"
  [[ "$output" == *"WARNING"* ]]
  [[ "$output" == *"api_key"* ]]
}
