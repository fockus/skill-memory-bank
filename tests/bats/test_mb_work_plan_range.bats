#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PLAN="$REPO_ROOT/scripts/mb-work-plan.sh"
  GAP_PLAN="$REPO_ROOT/tests/bats/fixtures/gap-plan.md"
}

@test "work-plan: gap range does not expand to all" {
  run bash "$PLAN" --target "$GAP_PLAN" --range 3 --dry-run
  [ "$status" -ne 0 ]
  ! echo "$output" | grep -q '"stage_no": 1'
}

@test "work-plan: omitted range emits all stages" {
  run bash "$PLAN" --target "$GAP_PLAN" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"stage_no": 1'
  echo "$output" | grep -q '"stage_no": 2'
  echo "$output" | grep -q '"stage_no": 4'
  ! echo "$output" | grep -q '"stage_no": 3'
}

@test "work-plan: present range emits single stage" {
  run bash "$PLAN" --target "$GAP_PLAN" --range 2 --dry-run
  [ "$status" -eq 0 ]
  count=$(echo "$output" | grep -c '"stage_no": 2' || true)
  [ "$count" -eq 1 ]
  ! echo "$output" | grep -q '"stage_no": 1'
}
