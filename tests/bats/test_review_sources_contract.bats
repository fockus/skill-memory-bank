#!/usr/bin/env bats
# review_sources: — planning-qa-sources C6, Task 3. The payload's `## Sources`
# section (deterministic, mb-review.sh) and the verifier / reviewer / judge
# prompt clauses (through the S1-C9 harness).

bats_require_minimum_version 1.5.0
load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-review.sh"
  BANK="$BATS_TEST_TMPDIR/bank"
  CASE="$BATS_TEST_TMPDIR/case"
  mkdir -p "$BANK" "$CASE" "$BATS_TEST_TMPDIR/spec/topic"
  echo "- **REQ-001**: spec requirement text" > "$BATS_TEST_TMPDIR/spec/topic/requirements.md"
  echo "design text must not leak" > "$BATS_TEST_TMPDIR/spec/topic/design.md"
  printf 'wrapper DoD line\n' > "$BATS_TEST_TMPDIR/wrapper.md"
  printf 'QA report body\n' > "$BATS_TEST_TMPDIR/report.md"

  V="$REPO_ROOT/agents/plan-verifier.md"
  R="$REPO_ROOT/agents/mb-reviewer.md"
  J="$REPO_ROOT/agents/mb-judge.md"
  MB_DISCUSS_CLAUSES+=("rs-verifier-lines|mb_section|Invocation|Spec:.*Plan wrapper:.*QA cases:.*QA report:.*none|Plan wrapper:|s/QA report:/QA log:/|REQ-013")
  MB_DISCUSS_CLAUSES+=("rs-verifier-separate|mb_section|Sources, coverage and divergence|### Plan DoD.*### Spec REQ coverage.*separate sections|Plan DoD|s/separate sections/one merged section/|REQ-014")
  MB_DISCUSS_CLAUSES+=("rs-verifier-divergence|mb_section|Sources, coverage and divergence|CRITICAL .plan-spec divergence.*Covers:.*tasks: A-B|plan-spec divergence|s/CRITICAL/INFO/|REQ-015")
  MB_DISCUSS_CLAUSES+=("rs-verifier-coverage|mb_section|Sources, coverage and divergence|### QA coverage.*REQ.*Case.*Origin.*Proof.*Live.*Test|QA coverage|s/Origin/Source/|REQ-016")
  MB_DISCUSS_CLAUSES+=("rs-verifier-nothing|mb_section|Sources, coverage and divergence|NOTHING TO VERIFY.*no REQ.*no DoD item.*no case|NOTHING TO VERIFY|s/no DoD item/no stage/|REQ-017")
  MB_DISCUSS_CLAUSES+=("rs-reviewer-sources|mb_section|Inputs .*payload.*|## Sources.*optional.*last section.*REQs.*wrapper DoD|## Sources|s/last section/first section/|REQ-013")
  MB_DISCUSS_CLAUSES+=("rs-judge-input|mb_section|Inputs|## Sources. section, the same bytes|## Sources|s/the same bytes/a summary/|REQ-013")
  MB_DISCUSS_CLAUSES+=("rs-judge-divergence|mb_section|Decision policy|plan-spec divergence.*unmet acceptance criterion.*NO_GO|plan-spec divergence|s/unmet acceptance criterion/backlog item/|REQ-015")
}

payload() { bash "$RUN" --emit-payload --input "$CASE" --mb "$BANK" "$@"; }

@test "review_sources: payload ends with Sources holding spec, wrapper and QA report" {
  run payload --source "$BATS_TEST_TMPDIR/spec/topic" --source "$BATS_TEST_TMPDIR/wrapper.md" --source "$BATS_TEST_TMPDIR/report.md"
  [ "$status" -eq 0 ]
  tail_part="${output#*$'\n## Sources\n'}"
  [ "$tail_part" != "$output" ]
  [[ "$tail_part" == *"### $BATS_TEST_TMPDIR/spec/topic"* ]]
  [[ "$tail_part" == *"spec requirement text"* ]]
  [[ "$tail_part" != *"design text must not leak"* ]]
  [[ "$tail_part" == *"wrapper DoD line"* ]]
  [[ "$tail_part" == *"QA report body"* ]]
  [ "$(printf '%s\n' "$output" | grep -c '^## Sources$')" -eq 1 ]
}

@test "review_sources: Sources follows Quality DoD" {
  printf '## Quality DoD\nrubric\n' > "$BATS_TEST_TMPDIR/dod.md"
  run payload --quality-dod "$BATS_TEST_TMPDIR/dod.md" --source "$BATS_TEST_TMPDIR/wrapper.md"
  [ "$status" -eq 0 ]
  d=$(printf '%s\n' "$output" | grep -n '^## Quality DoD$' | cut -d: -f1)
  s=$(printf '%s\n' "$output" | grep -n '^## Sources$' | cut -d: -f1)
  [ "$d" -lt "$s" ]
}

@test "review_sources: no --source leaves the payload without a Sources section and unchanged as a prefix" {
  run payload
  [ "$status" -eq 0 ]
  base="$output"
  [[ "$base" != *"## Sources"* ]]
  run payload --source "$BATS_TEST_TMPDIR/wrapper.md"
  [ "$status" -eq 0 ]
  [ "${output:0:${#base}}" = "$base" ]
}

@test "review_sources: missing source exits 2 and prints no payload" {
  run --separate-stderr payload --source "$BATS_TEST_TMPDIR/nope.md"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"source not found"* ]]
}

@test "review_sources: verifier clauses — invocation lines, separate sections, divergence, coverage table, nothing to verify" {
  for id in rs-verifier-lines rs-verifier-separate rs-verifier-divergence rs-verifier-coverage rs-verifier-nothing; do
    run assert_clause "$V" "$id"; [ "$status" -eq 0 ]
    run assert_clause_load_bearing "$V" "$id"; [ "$status" -eq 0 ]
  done
}

@test "review_sources: reviewer clause — Sources is the optional last section" {
  run assert_clause "$R" rs-reviewer-sources; [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$R" rs-reviewer-sources; [ "$status" -eq 0 ]
}

@test "review_sources: judge clauses — Sources input and divergence is NO_GO" {
  for id in rs-judge-input rs-judge-divergence; do
    run assert_clause "$J" "$id"; [ "$status" -eq 0 ]
    run assert_clause_load_bearing "$J" "$id"; [ "$status" -eq 0 ]
  done
}
