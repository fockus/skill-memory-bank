#!/usr/bin/env bats
# Background-dispatched MB subagents must be able to report back upward:
# they need the SendMessage tool plus the standardized report-delivery
# sentinel, or a finished background run silently stalls the orchestrator.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  AGENTS_DIR="$REPO_ROOT/agents"
}

_report_role_agents() {
  echo "mb-analyst.md mb-android.md mb-devops.md mb-ios.md mb-reviewer-lead.md mb-reviewer-logic.md mb-reviewer-quality.md mb-reviewer-scalability.md mb-reviewer-security.md mb-reviewer-tests.md mb-rules-enforcer.md mb-test-runner.md mb-doctor.md mb-research.md mb-researcher.md"
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

@test "engineering-core carries the silent-finish rationalization row" {
  run grep -F "SendMessage to the dispatcher, or it didn't happen" "$AGENTS_DIR/mb-engineering-core.md"
  [ "$status" -eq 0 ] || { echo "missing silent-finish rationalization row in mb-engineering-core.md"; return 1; }
}
