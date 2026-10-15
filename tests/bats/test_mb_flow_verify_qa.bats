#!/usr/bin/env bats
# The `qa` firewall check of scripts/mb-flow-verify.sh: open critical/major bugs in
# <bank>/qa/bugs.md block closure as a blocker; a bank without the registry is unaffected.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  VERIFY="$REPO_ROOT/scripts/mb-flow-verify.sh"
  QA="$REPO_ROOT/scripts/mb-qa-bug.sh"
  TMPROOT="$(mktemp -d)"
  TMPBANK="$TMPROOT/.memory-bank"
  mkdir -p "$TMPBANK"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && rm -rf "$TMPROOT"
}

# Only the default `qa` command runs, so the verdict depends on the registry alone.
run_qa_only() {
  run bash "$VERIFY" "$TMPBANK" --skip tests,lint,no_todo,diff_scope,acceptance
}

qa_field() {
  # `run` mixes stderr breach lines into $output; the summary is the JSON line.
  printf '%s\n' "$output" | grep '^{"phase"' | python3 -c "import json,sys; c=[c for c in json.loads(sys.stdin.read())['checks'] if c['name']=='qa'][0]; print(json.dumps(c['$1']))"
}

@test "qa: no registry → check skipped, firewall passes" {
  run_qa_only
  [ "$status" -eq 0 ]
  [ "$(qa_field status)" = '"skip"' ]
  [ "$(qa_field ok)" = "null" ]
}

@test "qa: one open critical → qa fails as blocker, firewall exit 1" {
  bash "$QA" --mb "$TMPBANK" add critical "Checkout crashes" </dev/null
  run_qa_only
  [ "$status" -eq 1 ]
  [ "$(qa_field severity)" = '"blocker"' ]
  [ "$(qa_field findings)" = '["BUG-001 critical Checkout crashes"]' ]
}

@test "qa: one open major → qa fails as blocker, firewall exit 1" {
  bash "$QA" --mb "$TMPBANK" add major "Search ignores filters" </dev/null
  run_qa_only
  [ "$status" -eq 1 ]
  [ "$(qa_field severity)" = '"blocker"' ]
  [ "$(qa_field findings)" = '["BUG-001 major Search ignores filters"]' ]
}

@test "qa: only medium/low open → qa ok" {
  bash "$QA" --mb "$TMPBANK" add medium "Button misaligned" </dev/null
  bash "$QA" --mb "$TMPBANK" add low "Typo in footer" </dev/null
  run_qa_only
  [ "$status" -eq 0 ]
  [ "$(qa_field ok)" = "true" ]
}

@test "qa: fixed critical → qa ok" {
  bash "$QA" --mb "$TMPBANK" add critical "Checkout crashes" </dev/null
  bash "$QA" --mb "$TMPBANK" set BUG-001 fixed
  run_qa_only
  [ "$status" -eq 0 ]
  [ "$(qa_field ok)" = "true" ]
}
