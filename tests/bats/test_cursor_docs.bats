#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "cursor docs: cross-agent-setup mentions ten hooks and skill bundle" {
  local doc="$REPO_ROOT/docs/cross-agent-setup.md"
  grep -q 'sessionStart' "$doc"
  grep -q 'preToolUse' "$doc"
  grep -q 'memory-bank/hooks' "$doc"
  ! grep -q 'self-contained copies of our hook scripts' "$doc"
}

@test "cursor docs: dispatch protocol documented" {
  [ -f "$REPO_ROOT/adapters/cursor/dispatch.md" ]
  grep -q 'Task' "$REPO_ROOT/adapters/cursor/dispatch.md"
}
