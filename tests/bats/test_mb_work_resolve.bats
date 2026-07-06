#!/usr/bin/env bats
# Bank-relative target resolution for mb-work-resolve.sh (I-085 Stage 6).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RESOLVE="$REPO_ROOT/scripts/mb-work-resolve.sh"
  SANDBOX="$(mktemp -d)"
  BANK="$SANDBOX/bank"
  mkdir -p "$BANK/specs/dynamic-flow" "$BANK/plans"
  printf '# tasks\n' > "$BANK/specs/dynamic-flow/tasks.md"
  printf '# plan\n' > "$BANK/plans/sample-plan.md"
  WORKDIR="$SANDBOX/work"
  mkdir -p "$WORKDIR"
}

teardown() {
  [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ] && rm -rf "$SANDBOX"
}

@test "work_resolve: bank-relative spec tasks resolves from non-bank CWD" {
  cd "$WORKDIR" || exit 1
  run bash "$RESOLVE" "specs/dynamic-flow/tasks.md" --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/specs/dynamic-flow/tasks.md" ]]
}

@test "work_resolve: bank-relative plan resolves from non-bank CWD" {
  cd "$WORKDIR" || exit 1
  run bash "$RESOLVE" "plans/sample-plan.md" --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/plans/sample-plan.md" ]]
}

@test "work_resolve: bank-relative traversal rejected" {
  cd "$WORKDIR" || exit 1
  run bash "$RESOLVE" "specs/../../etc/passwd" --mb "$BANK"
  [ "$status" -ne 0 ]
  [[ "$output" != /etc/passwd ]]
  [[ "$output" != /private/etc/passwd ]]
}
