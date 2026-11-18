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

@test "work_resolve: substring matches the plan file name, not its parent directories" {
  # A TMPDIR like /var/folders/vj/d87hwmp15j1... contains "p1": every plan under
  # it used to match the target "p1", making it ambiguous.
  local bank="$SANDBOX/p1-home/bank"
  mkdir -p "$bank/plans"
  printf '# plan\n' > "$bank/plans/p1.md"
  printf '# plan\n' > "$bank/plans/p2.md"
  cd "$WORKDIR" || exit 1
  run bash "$RESOLVE" p1 --mb "$bank"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/plans/p1.md" ]]
}

# ── OpenSpec change as a work target (master-completion Stage 10) ───

_make_change() {
  local dir="$1"
  mkdir -p "$dir/specs/widgets"
  printf '## Why\n\nSlow.\n\n## What Changes\n\n- Cache.\n' > "$dir/proposal.md"
  printf '## ADDED Requirements\n\n### Requirement: Widget Cache\nThe system SHALL cache widgets.\n\n#### Scenario: Hit\n- **WHEN** requested twice\n- **THEN** served from memory\n' > "$dir/specs/widgets/spec.md"
  printf '## 1. Build\n\n- [ ] 1.1 Implement cache\n' > "$dir/tasks.md"
}

_openspec_repo() {
  REPO="$SANDBOX/repo"
  mkdir -p "$REPO/.memory-bank"
  OSBANK="$REPO/.memory-bank"
  _make_change "$REPO/openspec/changes/add-widget-cache"
}

@test "work_resolve: openspec change id imports then resolves to the synced triple" {
  _openspec_repo
  cd "$REPO" || exit 1
  run bash "$RESOLVE" add-widget-cache --mb "$OSBANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/specs/add-widget-cache/tasks.md" ]]
  [ -f "$OSBANK/specs/add-widget-cache/requirements.md" ]
}

@test "work_resolve: openspec change path resolves and re-run syncs OpenSpec edits" {
  _openspec_repo
  cd "$WORKDIR" || exit 1
  run bash "$RESOLVE" "$REPO/openspec/changes/add-widget-cache" --mb "$OSBANK"
  [ "$status" -eq 0 ]
  sed -i.bak 's/cache widgets\./cache widgets for an hour./' "$REPO/openspec/changes/add-widget-cache/specs/widgets/spec.md"
  rm -f "$REPO/openspec/changes/add-widget-cache/specs/widgets/spec.md.bak"
  run bash "$RESOLVE" "$REPO/openspec/changes/add-widget-cache" --mb "$OSBANK"
  [ "$status" -eq 0 ]
  grep -q "for an hour" "$OSBANK/specs/add-widget-cache/requirements.md"
}

@test "work_resolve: unknown openspec change id fails with a clear message" {
  _openspec_repo
  cd "$REPO" || exit 1
  run bash "$RESOLVE" no-such-change --mb "$OSBANK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
  [[ "$output" == *"OpenSpec"* ]]
}

@test "work_resolve: native topic still resolves as before when a same-named change is absent" {
  _openspec_repo
  mkdir -p "$OSBANK/specs/native-topic"
  printf '# tasks\n' > "$OSBANK/specs/native-topic/tasks.md"
  cd "$REPO" || exit 1
  run bash "$RESOLVE" native-topic --mb "$OSBANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/specs/native-topic/tasks.md" ]]
}

@test "work_resolve: conflicting openspec change stops before any work" {
  _openspec_repo
  cd "$REPO" || exit 1
  run bash "$RESOLVE" add-widget-cache --mb "$OSBANK"
  [ "$status" -eq 0 ]
  sed -i.bak 's/cache widgets\./cache widgets in OpenSpec./' "$REPO/openspec/changes/add-widget-cache/specs/widgets/spec.md"
  rm -f "$REPO/openspec/changes/add-widget-cache/specs/widgets/spec.md.bak"
  sed -i.bak 's/cache widgets\./cache widgets in the bank./' "$OSBANK/specs/add-widget-cache/requirements.md"
  rm -f "$OSBANK/specs/add-widget-cache/requirements.md.bak"
  run bash "$RESOLVE" add-widget-cache --mb "$OSBANK"
  [ "$status" -ne 0 ]
  [[ "$output" == *"conflict"* ]]
  [[ "$output" != *"/tasks.md" ]]
}

@test "work_resolve: explicit openspec target never resolves to a native topic of the same name" {
  _openspec_repo
  mkdir -p "$OSBANK/specs/add-widget-cache"
  printf '# tasks\n' > "$OSBANK/specs/add-widget-cache/tasks.md"
  cd "$REPO" || exit 1
  run bash "$RESOLVE" add-widget-cache --mb "$OSBANK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"native"* ]]
  [[ "$output" != *"/tasks.md" ]]
}

@test "work_resolve: topic linked to a different change is not synced against this one" {
  _openspec_repo
  _make_change "$REPO/openspec/changes/other-change"
  cd "$REPO" || exit 1
  run bash "$RESOLVE" other-change --mb "$OSBANK"
  [ "$status" -eq 0 ]
  mv "$OSBANK/specs/other-change" "$OSBANK/specs/add-widget-cache"
  run bash "$RESOLVE" add-widget-cache --mb "$OSBANK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"different change"* ]]
}

@test "work_resolve: symlinked, archived and foreign change dirs are rejected" {
  _openspec_repo
  mkdir -p "$SANDBOX/elsewhere"
  _make_change "$SANDBOX/elsewhere/evil"
  ln -s "$SANDBOX/elsewhere/evil" "$REPO/openspec/changes/linked"
  mkdir -p "$REPO/openspec/changes/archive"
  _make_change "$REPO/openspec/changes/archive/old-change"
  cd "$REPO" || exit 1
  run bash "$RESOLVE" linked --mb "$OSBANK"
  [ "$status" -ne 0 ]
  run bash "$RESOLVE" "$REPO/openspec/changes/archive/old-change" --mb "$OSBANK"
  [ "$status" -ne 0 ]
  run bash "$RESOLVE" "$SANDBOX/elsewhere/evil" --mb "$OSBANK"
  [ "$status" -ne 0 ]
  [ ! -d "$OSBANK/specs/evil" ]
  [ ! -d "$OSBANK/specs/linked" ]
}

@test "work_resolve: openspec change dir without --mb is a target, not the bank" {
  _openspec_repo
  cd "$REPO" || exit 1
  run bash "$RESOLVE" "openspec/changes/add-widget-cache"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/specs/add-widget-cache/tasks.md" ]]
}

@test "work_resolve: bare id naming a change and a plan substring is ambiguous, nothing synced" {
  _openspec_repo
  _make_change "$REPO/openspec/changes/auth"
  mkdir -p "$OSBANK/plans"
  printf '# plan\n' > "$OSBANK/plans/2026-01-01_feature_auth-refactor.md"
  cd "$REPO" || exit 1
  run bash "$RESOLVE" auth --mb "$OSBANK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ambiguous"* ]]
  [[ "$output" == *"openspec/changes/auth"* ]]
  [[ "$output" == *"auth-refactor.md"* ]]
  [ ! -d "$OSBANK/specs" ]
  run bash "$RESOLVE" openspec/changes/auth --mb "$OSBANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/specs/auth/tasks.md" ]]
}
