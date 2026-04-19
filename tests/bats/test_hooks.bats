#!/usr/bin/env bats
# Tests for hooks/file-change-log.sh and hooks/block-dangerous.sh.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  FC_LOG="$REPO_ROOT/hooks/file-change-log.sh"
  BD="$REPO_ROOT/hooks/block-dangerous.sh"

  TMPHOME="$(mktemp -d)"
  export HOME="$TMPHOME"
  mkdir -p "$HOME/.claude"

  command -v jq >/dev/null || skip "jq required for hooks"
}

teardown() {
  [ -n "${TMPHOME:-}" ] && [ -d "$TMPHOME" ] && rm -rf "$TMPHOME"
}

# Build a PostToolUse JSON payload.
payload_write() {
  local path="$1"
  jq -n --arg p "$path" '{tool_name:"Write",tool_input:{file_path:$p}}'
}

# Build a PreToolUse JSON payload for bash.
payload_bash() {
  local cmd="$1"
  jq -n --arg c "$cmd" '{tool_input:{command:$c}}'
}

# Run a hook, capturing stdout+stderr into $output and exit code into $status.
# The subshell captures its own exit code via echo appended as the last line.
run_hook() {
  local hook="$1" input="$2"
  local raw
  raw=$(printf '%s' "$input" | bash "$hook" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

# ═══════════════════════════════════════════════════════════════
# file-change-log — placeholder detection
# ═══════════════════════════════════════════════════════════════

@test "file-change-log: warns on TODO in code" {
  file="$TMPHOME/sample.py"
  printf 'def foo():\n    # TODO: implement\n    return 1\n' > "$file"
  run_hook "$FC_LOG" "$(payload_write "$file")"
  [[ "$output" == *"TODO"* || "$output" == *"Placeholder"* ]]
}

@test "file-change-log: does NOT warn on bare pass (v1 false-positive)" {
  file="$TMPHOME/empty_impl.py"
  cat > "$file" <<'EOF'
class Foo:
    def __init__(self):
        pass

    def ok(self):
        return True
EOF
  run_hook "$FC_LOG" "$(payload_write "$file")"
  ! [[ "$output" == *"Placeholder"* ]]
}

@test "file-change-log: does NOT warn on TODO inside Python docstring" {
  file="$TMPHOME/doc_only.py"
  cat > "$file" <<'EOF'
def foo():
    """Brief summary.

    TODO(user): not really — just discussed in the doc.
    """
    return 42
EOF
  run_hook "$FC_LOG" "$(payload_write "$file")"
  # TODO in docstring should not trigger a warning
  ! [[ "$output" == *"Placeholder"* ]]
}

@test "file-change-log: still warns on FIXME in trailing comment" {
  file="$TMPHOME/real_code.py"
  cat > "$file" <<'EOF'
def compute():
    result = 0
    result = 999  # FIXME: wire real value
    return result
EOF
  run_hook "$FC_LOG" "$(payload_write "$file")"
  [[ "$output" == *"FIXME"* || "$output" == *"Placeholder"* ]]
}

# ═══════════════════════════════════════════════════════════════
# file-change-log — log rotation
# ═══════════════════════════════════════════════════════════════

@test "file-change-log: rotates log when over 10 MB" {
  log="$HOME/.claude/file-changes.log"
  dd if=/dev/zero of="$log" bs=1048576 count=11 2>/dev/null
  size=$(stat -f%z "$log" 2>/dev/null || stat -c%s "$log")
  [ "$size" -gt 10485760 ]

  file="$TMPHOME/trigger.py"
  echo "x = 1" > "$file"
  run_hook "$FC_LOG" "$(payload_write "$file")"
  [ "$status" -eq 0 ]

  [ -f "$log.1" ]
  new_size=$(stat -f%z "$log" 2>/dev/null || stat -c%s "$log")
  [ "$new_size" -lt 10485760 ]
}

@test "file-change-log: does NOT rotate under 10 MB" {
  log="$HOME/.claude/file-changes.log"
  echo "small log" > "$log"

  file="$TMPHOME/x.py"
  echo "x = 1" > "$file"
  run_hook "$FC_LOG" "$(payload_write "$file")"

  [ ! -f "$log.1" ]
}

# ═══════════════════════════════════════════════════════════════
# block-dangerous — MB_ALLOW_NO_VERIFY bypass
# ═══════════════════════════════════════════════════════════════

@test "block-dangerous: blocks --no-verify by default" {
  run_hook "$BD" "$(payload_bash "git commit --no-verify -m test")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED"* || "$output" == *"--no-verify"* ]]
}

@test "block-dangerous: error message hints at MB_ALLOW_NO_VERIFY" {
  run_hook "$BD" "$(payload_bash "git commit --no-verify -m test")"
  [[ "$output" == *"MB_ALLOW_NO_VERIFY"* ]]
}

@test "block-dangerous: MB_ALLOW_NO_VERIFY=1 allows --no-verify" {
  input="$(payload_bash "git commit --no-verify -m test")"
  raw=$(printf '%s' "$input" | MB_ALLOW_NO_VERIFY=1 bash "$BD" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  [ "$status" -eq 0 ]
}

@test "block-dangerous: still blocks rm -rf / even with bypass" {
  input="$(payload_bash "rm -rf /")"
  raw=$(printf '%s' "$input" | MB_ALLOW_NO_VERIFY=1 bash "$BD" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  [ "$status" -eq 2 ]
}

@test "block-dangerous: plain git commit not blocked" {
  run_hook "$BD" "$(payload_bash "git commit -m message")"
  [ "$status" -eq 0 ]
}
