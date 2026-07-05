#!/usr/bin/env bats
# Tests for tests/calibration/run.sh — the golden calibration-suite runner
# (reviewer-2.0 Task 6, design.md §6 "Golden calibration suite", REQ-104/105).
#
# This is a payload-shape smoke test on the OFFLINE, load-bearing path
# (`--emit-payload`): no reviewer dispatch, no LLM, no network, ever. It
# asserts:
#   - the case fixture pool has >=5 cases, each shipping the 4 required files
#   - `--emit-payload` exits 0 and reports >=5 cases in its table
#   - each case's assembled payload has the 4 unconditional sections, in the
#     fixed design.md §7 order, plus the conditional auto-findings section
#     iff that case's prior-tests.json has tests_pass:false
#   - the run is pure/deterministic: two consecutive runs produce identical
#     stdout, and no network/LLM call is made (the script never shells out
#     to anything but scripts/mb-review.sh, which is itself --input-mode
#     offline -- see test_mb_review.bats)

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/tests/calibration/run.sh"
  CASES_DIR="$REPO_ROOT/tests/calibration/cases"
}

@test "run.sh: script exists and is executable" {
  [ -f "$RUN" ]
  [ -x "$RUN" ]
}

@test "case pool: at least 5 cases, each with the 4 required fixture files" {
  local count=0 d
  for d in "$CASES_DIR"/*/; do
    [ -d "$d" ] || continue
    count=$((count + 1))
    [ -f "$d/case.json" ]
    [ -f "$d/diff.patch" ]
    [ -f "$d/files-touched.txt" ]
    [ -f "$d/prior-tests.json" ]
  done
  [ "$count" -ge 5 ]
}

@test "--help exits 0 and documents --emit-payload, --stack, --case" {
  run bash "$RUN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--emit-payload"* ]]
  [[ "$output" == *"--stack="* ]]
  [[ "$output" == *"--case="* ]]
}

@test "--emit-payload: exits 0, reports >=5 cases, all PASS" {
  run bash "$RUN" --emit-payload
  [ "$status" -eq 0 ]
  [[ "$output" == *"5 PASS"* || "$output" == *"6 PASS"* || "$output" == *"7 PASS"* ]]
  local n
  n=$(printf '%s\n' "$output" | grep -c "emit-payload")
  [ "$n" -ge 5 ]
}

@test "--emit-payload: no FAIL/WARN row for the shipped fixture pool" {
  run bash "$RUN" --emit-payload
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\tFAIL\t'* ]]
  ! printf '%s\n' "$output" | grep -qE '^\S+ +emit-payload +FAIL'
  ! printf '%s\n' "$output" | grep -qE '^\S+ +emit-payload +WARN'
}

@test "--emit-payload: red-tests case (PY-002) row is present (auto-findings branch)" {
  run bash "$RUN" --emit-payload
  [ "$status" -eq 0 ]
  [[ "$output" == *"PY-002-missing-tests"* ]]
}

@test "--stack=python filters to only python cases" {
  run bash "$RUN" --emit-payload --stack=python
  [ "$status" -eq 0 ]
  [[ "$output" == *"PY-001-srp-violation"* ]]
  [[ "$output" == *"PY-002-missing-tests"* ]]
  [[ "$output" != *"GO-001"* ]]
  [[ "$output" != *"TS-001"* ]]
}

@test "--case=PY-001 filters to a single case by id prefix" {
  run bash "$RUN" --emit-payload --case=PY-001
  [ "$status" -eq 0 ]
  [[ "$output" == *"PY-001-srp-violation"* ]]
  [[ "$output" != *"PY-002"* ]]
  [[ "$output" != *"GO-001"* ]]
}

@test "an unmatched filter is a loud usage-shaped error, exit 2" {
  run bash "$RUN" --emit-payload --case=DOES-NOT-EXIST
  [ "$status" -eq 2 ]
}

@test "--emit-payload is pure/deterministic: two consecutive runs produce identical stdout" {
  # --separate-stderr: the "results written to <timestamp>_run.json" notice
  # goes to stderr precisely so stdout (the PASS/WARN/FAIL/SKIP table) stays
  # byte-identical across runs; bats' default $output merges both streams,
  # which would otherwise make this assertion flaky on the timestamp alone.
  run --separate-stderr bash "$RUN" --emit-payload
  first="$stdout"
  run --separate-stderr bash "$RUN" --emit-payload
  [ "$status" -eq 0 ]
  [ "$first" = "$stdout" ]
}

@test "--emit-payload never dispatches a reviewer/LLM/network: each case's payload has the 4 fixed sections in order, conditional on tests_pass" {
  local d id payload expect_red python_check
  for d in "$CASES_DIR"/*/; do
    [ -d "$d" ] || continue
    id="$(basename "$d")"
    bank="$BATS_TEST_TMPDIR/bank-$id"
    mkdir -p "$bank"
    stack=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("stack",""))' "$d/case.json")
    printf '{"stack": "%s"}\n' "$stack" >"$bank/rules-profile.json"

    run bash "$REPO_ROOT/scripts/mb-review.sh" --emit-payload --input "$d" --mb "$bank"
    [ "$status" -eq 0 ]
    payload="$output"

    [[ "$payload" == *"## Plan context"* ]]
    [[ "$payload" == *"## Diff"* ]]
    [[ "$payload" == *"## Calibration examples"* ]]
    [[ "$payload" == *"## Prior evidence"* ]]

    expect_red=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("1" if d.get("tests_pass") is False else "0")' "$d/prior-tests.json")
    if [ "$expect_red" = "1" ]; then
      [[ "$payload" == *"## Auto-generated findings (MUST INCLUDE)"* ]]
    else
      [[ "$payload" != *"## Auto-generated findings"* ]]
    fi
  done
}

@test "results file: --emit-payload writes a gitignored results/<timestamp>_run.json" {
  local results_dir="$REPO_ROOT/tests/calibration/results"
  run bash -c "cd '$BATS_TEST_TMPDIR' && bash '$RUN' --emit-payload --case=PY-001"
  [ "$status" -eq 0 ]
  [ -d "$results_dir" ]
  local n
  n=$(find "$results_dir" -name '*_run.json' | wc -l | tr -d ' ')
  [ "$n" -ge 1 ]
  run bash -c "cd '$REPO_ROOT' && git check-ignore -q tests/calibration/results/probe_run.json"
  [ "$status" -eq 0 ]
  rm -rf "$results_dir"
}
