#!/usr/bin/env bats
# qa_catalog: — planning-qa-sources Task 2. Regression case on `mb-qa-bug.sh set <id> fixed` (design C3)
# and the prompt clauses for the case catalog (C2): template fields, live selection, runner Not verified.
# Name convention: every @test starts with `qa_catalog: `.

bats_require_minimum_version 1.5.0
load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  BUG="$REPO_ROOT/scripts/mb-qa-bug.sh"
  QA_MD="$REPO_ROOT/commands/qa.md"
  RUNNER="$REPO_ROOT/agents/mb-qa-runner.md"
  MB="$BATS_TEST_TMPDIR/.memory-bank"
  mkdir -p "$MB/qa/test_cases/checkout"
  cat >"$MB/qa/test_cases/checkout/pay.md" <<'CASE'
---
tags: [checkout, smoke]
driver: browser
covers: [REQ-002]
---
# Pay
CASE
  MB_DISCUSS_CLAUSES=()
  MB_DISCUSS_CLAUSES+=("tpl-origin|mb_section|.new <name>.|origin:.*regression|origin:|s/regression/other/|REQ-007")
  MB_DISCUSS_CLAUSES+=("tpl-proof|mb_section|.new <name>.|proof:.*both|proof:|s/both/other/|REQ-007")
  MB_DISCUSS_CLAUSES+=("tpl-needs-spec|mb_section|.new <name>.|status: needs_spec.*not derivable|needs_spec|s/not derivable/known/|REQ-008")
  MB_DISCUSS_CLAUSES+=("run-filter|mb_section|.run .*|Drop cases with .status: needs_spec. or .proof: test.*not_run|needs_spec|s/Drop cases/Keep cases/|REQ-008")
  MB_DISCUSS_CLAUSES+=("runner-not-verified|mb_section|Report|not run: needs_spec.*not run: proof test.*never as Results rows|not run: needs_spec|s/never as Results rows/as SKIP rows/|REQ-008")
}

add_bug() { # <severity> <scenario-line-or-empty>
  local body="- Steps: pay with a card
- Expected: order is paid"
  [ -z "$2" ] || body="$2
$body"
  printf '%s\n' "$body" | bash "$BUG" --mb "$MB" add "$1" "Bug $1"
}

@test "qa_catalog: major bug fixed writes the regression case with copied fields" {
  id="$(add_bug major '- Scenario: qa/test_cases/checkout/pay.md, step 2')"
  run bash "$BUG" --mb "$MB" set "$id" fixed
  [ "$status" -eq 0 ]
  [ "$output" = "regression_case=qa/test_cases/checkout/reg-bug-001.md" ]
  f="$MB/qa/test_cases/checkout/reg-bug-001.md"
  grep -qx 'id: reg-bug-001' "$f"
  grep -qx 'tags: \[checkout, smoke\]' "$f"
  grep -qx 'driver: browser' "$f"
  grep -qx 'covers: \[REQ-002\]' "$f"
  grep -qx 'origin: regression' "$f"
  grep -qx 'proof: both' "$f"
  grep -q 'pay with a card' "$f"
  grep -q 'order is paid' "$f"
}

@test "qa_catalog: critical bug fixed writes a case, a source without covers gets an empty list" {
  sed -i.bak '/^covers:/d' "$MB/qa/test_cases/checkout/pay.md"
  id="$(add_bug critical '- Scenario: qa/test_cases/checkout/pay.md, step 1')"
  run bash "$BUG" --mb "$MB" set "$id" fixed
  [ "$status" -eq 0 ]
  grep -qx 'covers: \[\]' "$MB/qa/test_cases/checkout/reg-bug-001.md"
}

@test "qa_catalog: an existing regression case is not overwritten" {
  id="$(add_bug major '- Scenario: qa/test_cases/checkout/pay.md, step 2')"
  printf 'keep me\n' >"$MB/qa/test_cases/checkout/reg-bug-001.md"
  run bash "$BUG" --mb "$MB" set "$id" fixed
  [ "$status" -eq 0 ]
  [ "$output" = "regression_case=qa/test_cases/checkout/reg-bug-001.md exists" ]
  [ "$(cat "$MB/qa/test_cases/checkout/reg-bug-001.md")" = "keep me" ]
}

@test "qa_catalog: medium bug fixed writes no case and prints nothing" {
  id="$(add_bug medium '- Scenario: qa/test_cases/checkout/pay.md, step 2')"
  run bash "$BUG" --mb "$MB" set "$id" fixed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$MB/qa/test_cases/checkout/reg-bug-001.md" ]
}

@test "qa_catalog: a major bug set to wontfix writes no case" {
  id="$(add_bug major '- Scenario: qa/test_cases/checkout/pay.md, step 2')"
  run bash "$BUG" --mb "$MB" set "$id" wontfix
  [ -z "$output" ]
  [ ! -e "$MB/qa/test_cases/checkout/reg-bug-001.md" ]
}

@test "qa_catalog: no Scenario line gives regression_case=none reason=no_scenario" {
  id="$(add_bug major '')"
  run bash "$BUG" --mb "$MB" set "$id" fixed
  [ "$status" -eq 0 ]
  [ "$output" = "regression_case=none reason=no_scenario" ]
}

@test "qa_catalog: a Scenario naming a missing case gives regression_case=none" {
  id="$(add_bug major '- Scenario: qa/test_cases/nope.md, step 1')"
  run bash "$BUG" --mb "$MB" set "$id" fixed
  [ "$output" = "regression_case=none reason=no_scenario" ]
}

@test "qa_catalog: qa.md template carries origin, proof and the needs_spec rule" {
  for c in tpl-origin tpl-proof tpl-needs-spec; do
    assert_clause "$QA_MD" "$c"
    assert_clause_load_bearing "$QA_MD" "$c"
  done
}

@test "qa_catalog: qa.md run drops needs_spec and proof test cases as not_run" {
  assert_clause "$QA_MD" run-filter
  assert_clause_load_bearing "$QA_MD" run-filter
}

@test "qa_catalog: runner lists not_run cases under Not verified, never as Results rows" {
  assert_clause "$RUNNER" runner-not-verified
  assert_clause_load_bearing "$RUNNER" runner-not-verified
}
