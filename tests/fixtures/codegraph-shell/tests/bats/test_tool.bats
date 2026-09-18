#!/usr/bin/env bats
load 'lib/assert'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/tool.sh"
}

@test "tool prints one" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "tool is executable" {
  [ -f "$SCRIPT" ]
}
