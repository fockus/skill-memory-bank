#!/usr/bin/env bats
# Stage 7 — `mb-drift.sh` gains `drift_check_terminology` that warns when the
# active project surface contains Cyrillic planning terms outside the
# whitelisted archive paths. Frozen `plans/done/` must NOT trigger.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DRIFT="$REPO_ROOT/scripts/mb-drift.sh"
  TMP="$(mktemp -d)"
  cd "$TMP"
  mkdir -p .memory-bank/plans/done commands references rules
  # Minimal valid bank so other checks don't hard-fail.
  : > .memory-bank/roadmap.md
  : > .memory-bank/checklist.md
  : > .memory-bank/status.md
  : > .memory-bank/backlog.md
}

teardown() {
  cd /
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

@test "drift[terminology]: clean repo emits ok" {
  run bash "$DRIFT" .
  [[ "$output" == *"drift_check_terminology=ok"* ]]
}

@test "drift[terminology]: cyrillic in commands/ → warn" {
  echo "## Этап 1: foo" > commands/local.md
  run bash "$DRIFT" .
  [[ "$output" == *"drift_check_terminology=warn"* ]]
}

@test "drift[terminology]: cyrillic only inside plans/done/ does NOT warn" {
  echo "## Этап legacy" > .memory-bank/plans/done/2024-01-01_legacy.md
  run bash "$DRIFT" .
  [[ "$output" == *"drift_check_terminology=ok"* ]]
}

@test "drift[terminology]: cyrillic in references/templates.md (SSoT) does NOT warn" {
  echo '"Этап" is accepted historically' > references/templates.md
  run bash "$DRIFT" .
  [[ "$output" == *"drift_check_terminology=ok"* ]]
}
