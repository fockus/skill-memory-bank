#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "parallel pipeline: Cursor dispatch doc exists" {
  [ -f "$REPO_ROOT/adapters/cursor/dispatch.md" ]
  grep -q 'Task' "$REPO_ROOT/adapters/cursor/dispatch.md"
}

@test "parallel pipeline: design matrix lists Cursor as supported" {
  local design="$REPO_ROOT/.memory-bank/specs/parallel-pipeline/design.md"
  grep -Fq "| **Cursor** |" "$design"
  grep -q 'adapters/cursor/dispatch.md' "$design"
  ! grep -q '| **Cursor / Windsurf' "$design"
}
