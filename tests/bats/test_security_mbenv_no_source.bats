#!/usr/bin/env bats
# Security: mb-plan-done.sh must not source .mbenv (whitelist parser only).

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME:-$(dirname "$BATS_TEST_FILENAME")}/../.." && pwd)"
  cd "$REPO_ROOT"
  SCRIPTS_DIR="$REPO_ROOT/scripts"
  SANDBOX="$(mktemp -d)"
  MB_PATH="$SANDBOX/.memory-bank"
  mkdir -p "$MB_PATH/plans" "$MB_PATH/plans/done"
  PLAN="$MB_PATH/plans/test-plan.md"
  cat > "$PLAN" <<'PLAN'
---
status: active
---
# Plan: test

## Stages
PLAN
  printf '# Checklist\n' > "$MB_PATH/checklist.md"
  printf '# Roadmap\n<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n' > "$MB_PATH/roadmap.md"
  printf '# Status\n<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n' > "$MB_PATH/status.md"
  printf '# Backlog\n## Ideas\n' > "$MB_PATH/backlog.md"
}

teardown() {
  [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ] && rm -rf "$SANDBOX"
}

_run_plan_done() {
  env MB_PATH="$MB_PATH" bash "$SCRIPTS_DIR/mb-plan-done.sh" "$PLAN" "$MB_PATH" 2>/dev/null || true
}

@test "plan_done: mbenv must not execute arbitrary shell" {
  cat > "$MB_PATH/.mbenv" <<'ENV'
EVIL=$(touch "$BATS_TEST_TMPDIR/PWNED")
; touch "$BATS_TEST_TMPDIR/PWNED2"
ENV
  _run_plan_done
  [ ! -f "$BATS_TEST_TMPDIR/PWNED" ]
  [ ! -f "$BATS_TEST_TMPDIR/PWNED2" ]
}

@test "plan_done: mbenv loads allow-listed MB_TEST_ROOTS" {
  cat > "$MB_PATH/.mbenv" <<'ENV'
MB_TEST_ROOTS=src/tests:lib/tests
ENV
  _run_plan_done
  [ "${MB_TEST_ROOTS:-}" = "src/tests:lib/tests" ] || :
  # Value must be exported during script run — verify via a helper invocation
  run env MB_PATH="$MB_PATH" bash -c '
    # shellcheck source=scripts/_lib.sh
    . "'"$SCRIPTS_DIR"'/_lib.sh"
    mb_load_mbenv "'"$MB_PATH"'"
    printf "%s" "${MB_TEST_ROOTS:-}"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "src/tests:lib/tests" ]
}

@test "plan_done: mbenv rejects non-whitelist keys like PATH" {
  saved_path="$PATH"
  cat > "$MB_PATH/.mbenv" <<'ENV'
PATH=/evil/bin
ENV
  run env MB_PATH="$MB_PATH" PATH="$saved_path" bash -c '
    # shellcheck source=scripts/_lib.sh
    . "'"$SCRIPTS_DIR"'/_lib.sh"
    mb_load_mbenv "'"$MB_PATH"'"
    printf "%s" "$PATH"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "$saved_path" ]
}
