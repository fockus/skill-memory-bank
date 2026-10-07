#!/usr/bin/env bats
# shellcheck disable=SC2016
# Doc contract: the agent-driven gates read the project quality settings
# (plan project-quality-settings Stage 3, AGR-076). The verifier and the
# /mb work implementer prompt are assembled by an agent from these docs, so the
# docs ARE the gate: the source command and each branch must be spelled out.
#
# Script-level gates have their own tests: review rubric →
# test_mb_rules_resolve.bats, architecture presets → test_rules_check_profile.bats,
# `/mb config show` → test_mb_config_hosts.bats.

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  VERIFIER="$(cat "$REPO_ROOT/agents/plan-verifier.md")"
  WORK="$(cat "$REPO_ROOT/commands/work.md")"
  WORK_REF="$(cat "$REPO_ROOT/references/work-reference.md")"
}

@test "verifier: coverage is compared only when coverage.enabled, thresholds from the profile" {
  assert_substring "$VERIFIER" 'mb-profile.sh" quality --json'
  assert_substring "$VERIFIER" "coverage.enabled"
  assert_substring "$VERIFIER" "Coverage: not enabled"
}

@test "verifier: coverage not enabled is not a warning" {
  assert_substring "$VERIFIER" "not a WARNING"
}

@test "work: implementer prompt takes its TDD line from quality.tdd" {
  assert_substring "$WORK" "quality.tdd"
  assert_substring "$WORK" "§ Project quality settings"
  assert_substring "$WORK_REF" "## Project quality settings"
}

@test "work: tdd off removes the RED requirement from the implementer prompt" {
  local off_line
  off_line="$(printf '%s\n' "$WORK_REF" | grep -E '^\| `off` \|')"
  assert_substring "$off_line" "no RED-first requirement"
}

@test "work: small+ on a small-tier run asks for one test per stated behaviour" {
  local line
  line="$(printf '%s\n' "$WORK_REF" | grep -E '^\| `small\+` \|')"
  assert_substring "$line" "one focused test per stated behaviour"
}
