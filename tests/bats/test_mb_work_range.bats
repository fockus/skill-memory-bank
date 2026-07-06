#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RANGE="$REPO_ROOT/scripts/mb-work-range.sh"
  GAP_PLAN="$REPO_ROOT/tests/bats/fixtures/gap-plan.md"
}

@test "range: explicit gap index exits nonzero with diagnostic" {
  run bash "$RANGE" "$GAP_PLAN" --range 3
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "no existing stage"
}

@test "range: explicit in-bounds present index emits only that index" {
  run bash "$RANGE" "$GAP_PLAN" --range 2
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "range: omitted range emits all present indices" {
  run bash "$RANGE" "$GAP_PLAN"
  [ "$status" -eq 0 ]
  [ "$output" = $'1\n2\n4' ]
}
