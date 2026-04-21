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

@test "tests: prompt invokes mb-metrics.sh --run for test execution" {
  grep -Fq 'mb-metrics.sh --run' "$PROMPT"
}

@test "tests: prompt parses test_status=pass|fail from metrics output" {
  grep -Eq 'test_status=(pass\|fail|pass/fail)|test_status' "$PROMPT"
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
