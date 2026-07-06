#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PLAN="$REPO_ROOT/scripts/mb-work-plan.sh"
  FIXTURE_MB="$REPO_ROOT/tests/bats/fixtures/wrapper-bank/.memory-bank"
}

@test "work-plan wrapper: tasks with trailing comment limits range" {
  run bash "$PLAN" --target "$FIXTURE_MB/plans/wrapper-comment.md" --mb "$FIXTURE_MB" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"item_no": 1'
  echo "$output" | grep -q '"item_no": 2'
  ! echo "$output" | grep -q '"item_no": 3'
}

@test "work-plan wrapper: double-quoted linked_spec resolves" {
  run bash "$PLAN" --target "$FIXTURE_MB/plans/wrapper-quoted-double.md" --mb "$FIXTURE_MB" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"item_no": 1'
}

@test "work-plan wrapper: single-quoted linked_spec resolves" {
  run bash "$PLAN" --target "$FIXTURE_MB/plans/wrapper-quoted-single.md" --mb "$FIXTURE_MB" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"item_no": 1'
}

@test "work-plan wrapper: no tasks key runs all spec tasks" {
  run bash "$PLAN" --target "$FIXTURE_MB/plans/wrapper-all.md" --mb "$FIXTURE_MB" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"item_no": 5'
}
