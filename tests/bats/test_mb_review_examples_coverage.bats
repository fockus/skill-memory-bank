#!/usr/bin/env bats
# Coverage tests for the bundled rubric-examples baseline shipped under
# references/rubric-examples/*.md (reviewer-2.0 Task 3: REQ-101, design.md
# §9 DoD: "references/rubric-examples/{common,python,go,typescript,
# frontend,mobile,backend}.md each contain >=3 example blocks; across the
# suite all 5 categories (logic, code_rules, security, scalability, tests)
# have >=3 examples each").
#
# Unlike tests/bats/test_mb_review_examples.bats (hermetic loader-logic
# tests that never touch the real shipped files, via
# MB_REVIEW_EXAMPLES_BUNDLED_DIR fixtures), this suite deliberately drives
# the REAL scripts/mb-review-examples.sh loader against the REAL
# references/rubric-examples/ tree -- it is a content/coverage check on the
# shipped baseline itself, not a loader-mechanics test.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-review-examples.sh"
  # Empty bank: no rules-profile.json, no rubric-examples/ override -- the
  # project-override layers resolve to nothing, so only the real bundled
  # (skill baseline) files under references/rubric-examples/ are in play.
  # MB_REVIEW_EXAMPLES_BUNDLED_DIR is deliberately left UNSET so the loader
  # falls back to its real default bundled dir (the shipped tree).
  BANK="$BATS_TEST_TMPDIR/bank"
  mkdir -p "$BANK"
}

# Renders with --stack "$1" (against the REAL bundled tree) and prints only
# the header lines for blocks whose OWN front-matter `stack:` tag is "$1"
# -- i.e. blocks that actually live in "$1".md, excluding blocks pulled in
# from common.md by the same render call. --rotation none + a generous
# --max keep this deterministic and untruncated.
own_stack_headers() {
  local stack="$1"
  run bash "$RUN" render --mb "$BANK" --stack "$stack" --max 100 --rotation none
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -E "^### [A-Za-z0-9_-]+ \($stack / " || true
}

STACKS_WITH_OWN_FILES="typescript frontend mobile backend python go"

@test "coverage: the four new stack files exist (typescript/frontend/mobile/backend)" {
  for stack in typescript frontend mobile backend; do
    [ -f "$REPO_ROOT/references/rubric-examples/$stack.md" ]
  done
}

@test "coverage: every bundled stack file (typescript/frontend/mobile/backend/python/go) loads >= 3 examples through the real loader" {
  for stack in $STACKS_WITH_OWN_FILES; do
    headers="$(own_stack_headers "$stack")"
    count=$(printf '%s\n' "$headers" | grep -c '^### ' || true)
    if [ "$count" -lt 3 ]; then
      echo "stack '$stack' only loaded $count example(s) through the real loader, expected >= 3" >&2
      printf '%s\n' "$headers" >&2
      false
    fi
  done
}

@test "coverage: across the full bundled pool, every reviewer category has >= 3 examples" {
  # common.md is isolated by passing a --stack value that matches no real
  # bundled/project file, so only common.md resolves for that render call.
  common_headers="$(own_stack_headers "no-such-stack-zzz")"

  all_headers="$common_headers"
  for stack in $STACKS_WITH_OWN_FILES; do
    stack_headers="$(own_stack_headers "$stack")"
    all_headers="$all_headers
$stack_headers"
  done

  declare -A totals=([logic]=0 [code_rules]=0 [security]=0 [scalability]=0 [tests]=0)
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    category=$(printf '%s\n' "$line" | sed -E 's/^### [A-Za-z0-9_-]+ \([A-Za-z0-9_-]+ \/ ([a-z_]+) \/ [a-z]+\)$/\1/')
    case "$category" in
      logic|code_rules|security|scalability|tests)
        totals["$category"]=$(( totals["$category"] + 1 ))
        ;;
    esac
  done <<< "$all_headers"

  for category in logic code_rules security scalability tests; do
    if [ "${totals[$category]}" -lt 3 ]; then
      echo "category '$category' only has ${totals[$category]} example(s) across the bundled pool, expected >= 3" >&2
      false
    fi
  done
}
