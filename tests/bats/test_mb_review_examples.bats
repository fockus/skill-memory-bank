#!/usr/bin/env bats
# Tests for scripts/mb-review-examples.sh — the layered rubric-examples
# loader (reviewer-2.0 Task 2: REQ-101, design.md §4 "Few-shot examples —
# format and resolution").
#
# Layered precedence (highest wins on example_id collision):
#   1. .memory-bank/rubric-examples/<stack>.md   (project override, per stack)
#   2. .memory-bank/rubric-examples/common.md    (project override, cross-stack)
#   3. references/rubric-examples/<stack>.md     (skill baseline, per stack)
#   4. references/rubric-examples/common.md      (skill baseline, cross-stack)
#
# MB_REVIEW_EXAMPLES_BUNDLED_DIR overrides the "skill baseline" directory so
# these tests stay hermetic and do not depend on the real shipped content of
# references/rubric-examples/*.md (a test-only fixture hook, same pattern as
# MB_CAPS_FIXTURE in mb-agent-caps.sh).

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-review-examples.sh"
  BANK="$BATS_TEST_TMPDIR/bank"
  BUNDLED="$BATS_TEST_TMPDIR/bundled"
  mkdir -p "$BANK" "$BUNDLED"
}

example_block() {
  # $1=example_id $2=stack $3=category $4=severity $5=bad-marker $6=verdict-marker [$7=good-marker]
  local id="$1" stack="$2" cat="$3" sev="$4" bad="$5" verdict="$6" good="${7:-}"
  printf -- '---\n'
  printf 'example_id: %s\n' "$id"
  printf 'stack: %s\n' "$stack"
  printf 'category: %s\n' "$cat"
  printf 'severity: %s\n' "$sev"
  printf -- '---\n\n'
  printf '### Bad\n\n```python\n%s\n```\n\n' "$bad"
  if [ -n "$good" ]; then
    printf '### Good\n\n```python\n%s\n```\n\n' "$good"
  fi
  printf '### Expected verdict fragment\n\n```json\n{"message": "%s"}\n```\n\n' "$verdict"
  printf -- '---\n\n'
}

@test "mb-review-examples.sh: script exists" {
  [ -f "$RUN" ]
}

@test "--help exits 0 and documents render, --stack, --max, --rotation" {
  run bash "$RUN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"render"* ]]
  [[ "$output" == *"--stack"* ]]
  [[ "$output" == *"--max"* ]]
  [[ "$output" == *"--rotation"* ]]
}

@test "render: no example files resolve -> header + empty body, exit 0" {
  # BUNDLED is an empty tmp dir (no common.md/<stack>.md in it) and BANK has
  # no rubric-examples/ override -- neither layer resolves any file.
  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK" --stack nostack
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Calibration examples (reference patterns — not part of current diff)"* ]]
  [[ "$output" == *"(no calibration examples available)"* ]]
  [[ "$output" != *"### "* ]]
}

@test "render: project override replaces bundled block on example_id collision" {
  example_block "EX-001" "python" "logic" "minor" "BUNDLED_BAD_MARKER" "bundled version" \
    > "$BUNDLED/common.md"

  mkdir -p "$BANK/rubric-examples"
  example_block "EX-001" "python" "logic" "minor" "PROJECT_BAD_MARKER" "project version" \
    > "$BANK/rubric-examples/common.md"

  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK" --stack nostack
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROJECT_BAD_MARKER"* ]]
  [[ "$output" != *"BUNDLED_BAD_MARKER"* ]]
}

@test "render: --max truncates to at most N examples" {
  {
    example_block "EX-A" "common" "logic" "minor" "BAD-A" "verdict-a"
    example_block "EX-B" "common" "code_rules" "major" "BAD-B" "verdict-b"
    example_block "EX-C" "common" "security" "blocker" "BAD-C" "verdict-c"
    example_block "EX-D" "common" "scalability" "minor" "BAD-D" "verdict-d"
    example_block "EX-E" "common" "tests" "major" "BAD-E" "verdict-e"
  } > "$BUNDLED/common.md"

  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK" --stack nostack --max 3
  [ "$status" -eq 0 ]
  local count
  count=$(printf '%s\n' "$output" | grep -c '^### EX-')
  [ "$count" -eq 3 ]
}

@test "render: hash_run_id rotation is deterministic across two runs" {
  {
    example_block "EX-A" "common" "logic" "minor" "BAD-A" "verdict-a"
    example_block "EX-B" "common" "code_rules" "major" "BAD-B" "verdict-b"
    example_block "EX-C" "common" "security" "blocker" "BAD-C" "verdict-c"
    example_block "EX-D" "common" "scalability" "minor" "BAD-D" "verdict-d"
    example_block "EX-E" "common" "tests" "major" "BAD-E" "verdict-e"
  } > "$BUNDLED/common.md"

  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK" --stack nostack \
    --max 3 --rotation hash_run_id --run-id RUN-X-42
  [ "$status" -eq 0 ]
  local first="$output"

  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK" --stack nostack \
    --max 3 --rotation hash_run_id --run-id RUN-X-42
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
}

@test "render: only ### Bad + verdict fragment injected, no Good snippet" {
  example_block "EX-001" "python" "logic" "minor" "BAD_SNIPPET_MARKER" "verdict text" "GOOD_SNIPPET_MARKER" \
    > "$BUNDLED/common.md"

  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK" --stack nostack
  [ "$status" -eq 0 ]
  [[ "$output" == *"BAD_SNIPPET_MARKER"* ]]
  [[ "$output" != *"GOOD_SNIPPET_MARKER"* ]]
}

@test "render: stack auto-resolves from .memory-bank/rules-profile.json when --stack omitted" {
  example_block "EX-GO-001" "go" "code_rules" "major" "GO_STACK_BAD_MARKER" "go verdict" \
    > "$BUNDLED/go.md"
  example_block "EX-COMMON-001" "common" "logic" "minor" "COMMON_BAD_MARKER" "common verdict" \
    > "$BUNDLED/common.md"

  cat > "$BANK/rules-profile.json" <<'JSON'
{"schema_version": 1, "scope": "project", "stack": "go"}
JSON

  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GO_STACK_BAD_MARKER"* ]]
  [[ "$output" == *"COMMON_BAD_MARKER"* ]]
}

@test "render: invalid category is skipped without crashing the loader" {
  {
    printf -- '---\n'
    printf 'example_id: EX-BAD\n'
    printf 'stack: common\n'
    printf 'category: not_a_real_category\n'
    printf 'severity: minor\n'
    printf -- '---\n\n'
    printf '### Bad\n\n```python\nSHOULD_NOT_APPEAR\n```\n\n'
    printf '### Expected verdict fragment\n\n```json\n{"message": "x"}\n```\n\n'
    printf -- '---\n\n'
  } > "$BUNDLED/common.md"

  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK" --stack nostack
  [ "$status" -eq 0 ]
  [[ "$output" != *"SHOULD_NOT_APPEAR"* ]]
}

@test "render: unknown rotation value is a usage error, exit 2" {
  run bash "$RUN" render --mb "$BANK" --rotation bogus
  [ "$status" -eq 2 ]
}

@test "render: --max 0 is rejected as not a positive integer, exit 2" {
  run bash "$RUN" render --mb "$BANK" --max 0
  [ "$status" -eq 2 ]
  [[ "$output" == *"positive integer"* ]]
}

@test "render: a value-taking flag as the last arg with no value -> loud exit 2" {
  run bash "$RUN" render --mb "$BANK" --max
  [ "$status" -eq 2 ]
}

@test "render: invalid severity is skipped without crashing the loader" {
  {
    printf -- '---\n'
    printf 'example_id: EX-BADSEV\n'
    printf 'stack: common\n'
    printf 'category: logic\n'
    printf 'severity: catastrophic\n'
    printf -- '---\n\n'
    printf '### Bad\n\n```python\nSHOULD_NOT_APPEAR_SEV\n```\n\n'
    printf '### Expected verdict fragment\n\n```json\n{"message": "x"}\n```\n\n'
    printf -- '---\n\n'
  } > "$BUNDLED/common.md"

  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK" --stack nostack
  [ "$status" -eq 0 ]
  [[ "$output" != *"SHOULD_NOT_APPEAR_SEV"* ]]
}

@test "render: a bare --- inside a fenced ### Bad snippet does not split the block" {
  {
    printf -- '---\n'
    printf 'example_id: EX-FENCE\n'
    printf 'stack: common\n'
    printf 'category: code_rules\n'
    printf 'severity: minor\n'
    printf -- '---\n\n'
    printf '### Bad\n\n```yaml\nfoo: bar\n---\nbaz: qux\n```\n\n'
    printf '### Expected verdict fragment\n\n```json\n{"message": "FENCE_VERDICT_MARKER"}\n```\n\n'
    printf -- '---\n\n'
  } > "$BUNDLED/common.md"

  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK" --stack nostack
  [ "$status" -eq 0 ]
  [[ "$output" == *"EX-FENCE"* ]]
  [[ "$output" == *"foo: bar"* ]]
  [[ "$output" == *"baz: qux"* ]]
  [[ "$output" == *"FENCE_VERDICT_MARKER"* ]]
}

@test "render: literal '### Bad' text inside a fenced snippet doesn't corrupt section parsing" {
  {
    printf -- '---\n'
    printf 'example_id: EX-HEADERTEXT\n'
    printf 'stack: common\n'
    printf 'category: code_rules\n'
    printf 'severity: minor\n'
    printf -- '---\n\n'
    printf '### Bad\n\n```markdown\nREAL_BAD_MARKER\n### Bad\nFAKE_HEADER_INSIDE_FENCE\n```\n\n'
    printf '### Expected verdict fragment\n\n```json\n{"message": "HEADERTEXT_VERDICT"}\n```\n\n'
    printf -- '---\n\n'
  } > "$BUNDLED/common.md"

  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK" --stack nostack
  [ "$status" -eq 0 ]
  [[ "$output" == *"REAL_BAD_MARKER"* ]]
  [[ "$output" == *"FAKE_HEADER_INSIDE_FENCE"* ]]
  [[ "$output" == *"HEADERTEXT_VERDICT"* ]]
}

@test "render: --stack path traversal is rejected, never reads outside the rubric roots" {
  # A validly-formatted example block living OUTSIDE both bundled/project
  # roots -- if the traversal ever resolved, its Bad snippet would render.
  mkdir -p "$BATS_TEST_TMPDIR/outside"
  example_block "EX-SECRET" "whatever" "logic" "minor" "SECRET_OUTSIDE_MARKER" "leak" \
    > "$BATS_TEST_TMPDIR/outside/passwd.md"

  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK" \
    --stack "../outside/passwd"
  [ "$status" -eq 0 ]
  [[ "$output" != *"SECRET_OUTSIDE_MARKER"* ]]
}

@test "render: a symlinked <stack>.md escaping the project rubric root is not read" {
  # Validly-formatted example block living OUTSIDE any rubric root -- if the
  # symlink were followed, its Bad snippet would render.
  example_block "EX-SYMLINK" "python" "logic" "minor" "SYMLINK_SECRET_MARKER" "leak" \
    > "$BATS_TEST_TMPDIR/outside-secret.md"

  mkdir -p "$BANK/rubric-examples"
  ln -s "$BATS_TEST_TMPDIR/outside-secret.md" "$BANK/rubric-examples/python.md"

  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK" --stack python
  [ "$status" -eq 0 ]
  [[ "$output" != *"SYMLINK_SECRET_MARKER"* ]]
}

@test "render: 4-layer precedence -- project/<stack> wins over project/common, skill/<stack>, skill/common" {
  mkdir -p "$BANK/rubric-examples"

  example_block "EX-LAYER" "python" "logic" "minor" "SKILL_COMMON_MARKER" "skill-common" \
    > "$BUNDLED/common.md"
  example_block "EX-LAYER" "python" "logic" "minor" "SKILL_STACK_MARKER" "skill-stack" \
    > "$BUNDLED/python.md"
  example_block "EX-LAYER" "python" "logic" "minor" "PROJECT_COMMON_MARKER" "project-common" \
    > "$BANK/rubric-examples/common.md"
  example_block "EX-LAYER" "python" "logic" "minor" "PROJECT_STACK_MARKER" "project-stack" \
    > "$BANK/rubric-examples/python.md"

  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK" --stack python
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROJECT_STACK_MARKER"* ]]
  [[ "$output" != *"PROJECT_COMMON_MARKER"* ]]
  [[ "$output" != *"SKILL_STACK_MARKER"* ]]
  [[ "$output" != *"SKILL_COMMON_MARKER"* ]]
}

@test "render: full 4-layer order revealed by stripping the winning layer each time" {
  mkdir -p "$BANK/rubric-examples"

  example_block "EX-LAYER" "python" "logic" "minor" "SKILL_COMMON_MARKER" "skill-common" \
    > "$BUNDLED/common.md"
  example_block "EX-LAYER" "python" "logic" "minor" "SKILL_STACK_MARKER" "skill-stack" \
    > "$BUNDLED/python.md"
  example_block "EX-LAYER" "python" "logic" "minor" "PROJECT_COMMON_MARKER" "project-common" \
    > "$BANK/rubric-examples/common.md"

  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK" --stack python
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROJECT_COMMON_MARKER"* ]]

  rm "$BANK/rubric-examples/common.md"
  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK" --stack python
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKILL_STACK_MARKER"* ]]

  rm "$BUNDLED/python.md"
  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK" --stack python
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKILL_COMMON_MARKER"* ]]
}

@test "render: unclosed block at EOF is dropped with a warning, never a crash" {
  {
    printf -- '---\n'
    printf 'example_id: EX-UNCLOSED\n'
    printf 'stack: common\n'
    printf 'category: logic\n'
    printf 'severity: minor\n'
    printf -- '---\n\n'
    printf '### Bad\n\n```python\nUNCLOSED_MARKER\n```\n\n'
    # file ends abruptly -- missing the block's closing --- line
  } > "$BUNDLED/common.md"

  run env MB_REVIEW_EXAMPLES_BUNDLED_DIR="$BUNDLED" bash "$RUN" render --mb "$BANK" --stack nostack
  [ "$status" -eq 0 ]
  [[ "$output" != *"UNCLOSED_MARKER"* ]]
}

@test "mb-review.sh: examples-loader failure degrades gracefully, other sections stay intact" {
  # --input <case-dir> keeps this hermetic (no real git diff / repo state
  # leaking in -- see test_mb_review.bats for the same pattern).
  local mb_review="$REPO_ROOT/scripts/mb-review.sh"
  local stub="$BATS_TEST_TMPDIR/failing-loader.sh"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$stub"
  chmod +x "$stub"

  local case_dir="$BATS_TEST_TMPDIR/case"
  mkdir -p "$case_dir"
  printf '{"case_id": "STUB-001", "description": "loader-failure smoke case"}' > "$case_dir/case.json"
  printf 'diff --git a/x b/x\n' > "$case_dir/diff.patch"
  printf '{"tests_pass": true, "counts": {"passed": 1, "failed": 0, "skipped": 0}}' > "$case_dir/prior-tests.json"

  run env MB_REVIEW_EXAMPLES_SH="$stub" bash "$mb_review" --emit-payload --input "$case_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Plan context"* ]]
  [[ "$output" == *"## Diff"* ]]
  [[ "$output" == *"## Calibration examples (reference patterns — not part of current diff)"* ]]
  [[ "$output" == *"(examples loader unavailable)"* ]]
  [[ "$output" == *"## Prior evidence (from mb-test-runner)"* ]]
}
