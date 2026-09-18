#!/usr/bin/env bats
# A second suite, deliberately about a DIFFERENT script: it must never show up
# as a test of scripts/tool.sh just because it mentions some *.sh path.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "other prints other" {
  run bash "$REPO_ROOT/scripts/other.sh"
  [ "$status" -eq 0 ]
}
