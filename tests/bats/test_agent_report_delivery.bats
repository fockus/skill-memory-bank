#!/usr/bin/env bats
# Background-dispatched MB subagents must be able to report back upward:
# they need the SendMessage tool plus the standardized report-delivery
# sentinel, or a finished background run silently stalls the orchestrator.

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  AGENTS_DIR="$REPO_ROOT/agents"
}

_report_role_agents() {
  echo "mb-analyst.md mb-android.md mb-devops.md mb-ios.md mb-reviewer-lead.md mb-reviewer-logic.md mb-reviewer-quality.md mb-reviewer-scalability.md mb-reviewer-security.md mb-reviewer-tests.md mb-rules-enforcer.md mb-test-runner.md mb-doctor.md mb-research.md mb-researcher.md mb-qa-runner.md"
}

@test "every report-role agent declares SendMessage in tools" {
  for f in $(_report_role_agents); do
    run grep -E '^tools:.*SendMessage' "$AGENTS_DIR/$f"
    [ "$status" -eq 0 ] || { echo "missing SendMessage in tools: line of $f"; return 1; }
  done
}

@test "every report-role agent carries the report-delivery sentinel" {
  for f in $(_report_role_agents); do
    run grep -F "## Report delivery (background runs)" "$AGENTS_DIR/$f"
    [ "$status" -eq 0 ] || { echo "missing report-delivery sentinel in $f"; return 1; }
  done
}

@test "strict discipline partial carries the silent-finish rationalization row" {
  local strict
  strict="$(cat "$AGENTS_DIR/mb-discipline-strict.md")"
  assert_substring "$strict" "Codex delivers the final response automatically"
  assert_substring "$strict" "hosts that only notify on idle need \`SendMessage\`"
}

@test "engineering-core tells a background run to SendMessage its report" {
  local core
  core="$(cat "$AGENTS_DIR/mb-engineering-core.md")"
  assert_substring "$core" "## 12. Report delivery"
  assert_substring "$core" "Codex subagents deliver their final response to the parent automatically"
  assert_substring "$core" "dispatcher with \`SendMessage\` before your final turn ends"
}
