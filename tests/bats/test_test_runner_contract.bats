#!/usr/bin/env bats
# Contract tests for scripts/mb-test-run.sh + agents/mb-test-runner.md.
#
# Covers:
#   - Unknown-stack edge: tests_pass MUST be null (never false — that would
#     be a silent "tests passed" on projects with no runner).
#   - JSON schema shape and required keys.
#   - Agent prompt frontmatter + invocation of the script + schema presence.
#   - plan-verifier.md now invokes mb-test-runner (delegation wiring).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-test-run.sh"
  PROMPT="$REPO_ROOT/agents/mb-test-runner.md"
  PV="$REPO_ROOT/agents/plan-verifier.md"
  command -v jq >/dev/null || skip "jq required"
}

@test "contract: mb-test-run.sh exists" {
  [ -f "$RUN" ]
}

@test "contract: --help exits 0 and mentions --dir + --out" {
  run bash "$RUN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dir"* ]]
  [[ "$output" == *"--out"* ]]
}

@test "contract: unknown stack (empty dir) → tests_pass=null, tests_total=0, stack=unknown" {
  TMPROOT="$(mktemp -d)"
  run bash "$RUN" --dir "$TMPROOT" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.stack == "unknown"'
  echo "$output" | jq -e '.tests_pass == null'
  echo "$output" | jq -e '.tests_total == 0'
  rm -rf "$TMPROOT"
}

@test "contract: JSON has all required top-level keys" {
  TMPROOT="$(mktemp -d)"
  run bash "$RUN" --dir "$TMPROOT" --out json
  [ "$status" -eq 0 ]
  # Required keys, regardless of stack.
  for key in stack tests_pass tests_total tests_failed failures coverage duration_ms; do
    echo "$output" | jq -e "has(\"$key\")"
  done
  rm -rf "$TMPROOT"
}

@test "contract: failures[] is always an array" {
  TMPROOT="$(mktemp -d)"
  run bash "$RUN" --dir "$TMPROOT" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.failures | type == "array"'
  rm -rf "$TMPROOT"
}

@test "contract: human output mentions stack and pass/fail status" {
  TMPROOT="$(mktemp -d)"
  run bash "$RUN" --dir "$TMPROOT" --out human
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack"* ]] || [[ "$output" == *"unknown"* ]]
  rm -rf "$TMPROOT"
}

@test "prompt: agents/mb-test-runner.md exists with frontmatter" {
  [ -f "$PROMPT" ]
  head -n 20 "$PROMPT" | grep -q '^name: mb-test-runner$'
  head -n 20 "$PROMPT" | grep -q '^description: '
  head -n 20 "$PROMPT" | grep -q '^tools: '
  head -n 20 "$PROMPT" | grep -q '^color: '
}

@test "prompt: references scripts/mb-test-run.sh" {
  grep -Fq 'scripts/mb-test-run.sh' "$PROMPT"
}

@test "prompt: documents JSON schema fields" {
  grep -Fq 'tests_pass' "$PROMPT"
  grep -Fq 'tests_total' "$PROMPT"
  grep -Fq 'tests_failed' "$PROMPT"
  grep -Fq 'failures' "$PROMPT"
  grep -Fq 'coverage' "$PROMPT"
  grep -Fq 'duration_ms' "$PROMPT"
}

@test "delegation: plan-verifier.md Step 3.5 invokes mb-test-runner" {
  [ -f "$PV" ]
  # Must reference the agent by name — replaces or augments the earlier
  # direct `mb-metrics.sh --run` call.
  grep -Fq 'mb-test-runner' "$PV"
}
