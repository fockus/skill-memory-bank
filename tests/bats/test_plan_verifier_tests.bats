#!/usr/bin/env bats
# Contract tests for the test-running step (3.5) in agents/plan-verifier.md.
#
# Stage 1 requires the prompt to:
#   - Invoke `bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh --run`
#     to detect stack + execute tests.
#   - Parse `test_status=pass|fail` from that output.
#   - Emit a `Tests run:` row in the final report (pass|fail|not-run).
#   - Consume the plan's `**Baseline commit:**` field for git diff (Step 2).
#
# RED-phase target: agents/plan-verifier.md currently uses generic `git diff HEAD~N`
# and does not mention mb-metrics.sh.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PROMPT="$REPO_ROOT/agents/plan-verifier.md"
  [ -f "$PROMPT" ]
}

@test "tests: prompt invokes test execution (mb-metrics.sh --run pre-Stage-3 OR mb-test-runner delegation Stage-3+)" {
  # Stage 1 used mb-metrics.sh --run directly. Stage 3 delegates to the
  # mb-test-runner subagent (which wraps mb-test-run.sh) to avoid double
  # execution. Either wording is an acceptable contract.
  grep -Fq 'mb-metrics.sh --run' "$PROMPT" || grep -Fq 'mb-test-runner' "$PROMPT"
}

@test "tests: prompt parses test verdict — either test_status= (v1) or tests_pass (v2)" {
  # v1: key=value from mb-metrics.sh (`test_status=pass|fail`).
  # v2: JSON field from mb-test-runner (`tests_pass: true|false|null`).
  grep -Eq 'test_status|tests_pass' "$PROMPT"
}

@test "tests: response format declares 'Tests run:' row" {
  grep -Eq '\*\*Tests run:\*\*|Tests run:' "$PROMPT"
}

@test "tests: prompt consumes Baseline commit from the plan header" {
  # Must reference the exact field label the plan emits.
  grep -Fq 'Baseline commit' "$PROMPT"
}

@test "tests: prompt documents the baseline-missing fallback" {
  # If baseline is absent from the plan — fallback to ctime-based lookup
  # or an explicit HEAD~N warning. At minimum the word 'fallback' must appear
  # near the baseline discussion.
  grep -Eiq 'fallback|missing|absent' "$PROMPT"
}
