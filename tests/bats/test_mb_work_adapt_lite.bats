#!/usr/bin/env bats
# adapt-lite Stage 2 — ADaPT in /mb work (references/adapt.md § "/mb work handling").
#
# Scriptable part only (no LLM): an implementer report with a complexity_escalation
# block or a verify guard opens the fork; `mb-work-state.sh split` stores the
# sub-items in the run state; the parent stays open until every sub-item is done;
# depth is bounded by adapt.max_depth; `--no-adapt` / `adapt.enabled: false` keep
# today's halt.

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export PATH="$REPO_ROOT/.venv/bin:${PATH}"
  command -v jq >/dev/null || skip "jq required"
  WS="$REPO_ROOT/scripts/mb-work-state.sh"
  ADAPT="$REPO_ROOT/scripts/mb_work_adapt.py"
  TMP="$(mktemp -d)"
  BANK="$TMP/.memory-bank"
  mkdir -p "$BANK/plans"
  printf '# Progress\n' >"$BANK/progress.md"
  PLAN="$BANK/plans/2026-01-01_feature_demo.md"
  printf -- '---\ntype: feature\n---\n# Plan\n\n<!-- mb-stage:1 -->\n### Stage 1: big\n\n**DoD:**\n- [ ] done\n' >"$PLAN"
  bash "$WS" init plan 1 --source-path "$PLAN" --source-topic demo --mb "$BANK" >/dev/null
  TWO='[{"title":"refresh module","Files":"src/a.py, tests/test_a.py"},{"title":"wire client","Files":["src/b.py"]}]'
}

teardown() { rm -rf "$TMP"; }

report_with() {  # <subitems yaml lines...> → report file path
  local f="$TMP/report.md"
  {
    printf 'STATUS: BLOCKED\n\n```yaml\ncomplexity_escalation:\n  reason: "needs a refresh subsystem"\n  estimate: "~3x the item"\n  proposed_subitems:\n'
    printf '%s\n' "$@"
    printf '```\n'
  } >"$f"
  printf '%s' "$f"
}

@test "adapt: implementer signal parses into 2 sub-items with files" {
  f=$(report_with '    - title: "Token refresh module"' '      Files: src/auth/refresh.py, tests/test_refresh.py' \
    '    - title: "Wire refresh"' '      Files: src/http/client.py')
  run python3 "$ADAPT" parse --file "$f"
  [ "$status" -eq 0 ]
  jq -e '(.proposed_subitems | length) == 2 and .proposed_subitems[0].files == ["src/auth/refresh.py","tests/test_refresh.py"]' <<<"$output"
}

@test "adapt: report without a block is no signal (exit 1)" {
  printf 'STATUS: DONE\n' >"$TMP/r.md"
  run python3 "$ADAPT" parse --file "$TMP/r.md"
  [ "$status" -eq 1 ]
}

@test "adapt: invalid block (1 sub-item) is rejected with a reason" {
  f=$(report_with '    - title: "only one"' '      Files: src/a.py')
  run python3 "$ADAPT" parse --file "$f"
  [ "$status" -eq 3 ]
  assert_substring "$output" "2-5 sub-items"
}

@test "adapt: invalid block (sub-item without Files) is rejected with a reason" {
  f=$(report_with '    - title: "one"' '      Files: src/a.py' '    - title: "two"')
  run python3 "$ADAPT" parse --file "$f"
  [ "$status" -eq 3 ]
  assert_substring "$output" "Files"
}

@test "adapt: split stores sub-items in state, writes a progress line, parent stays open" {
  run bash "$WS" split 1 --subitems "$TWO" --mb "$BANK"
  [ "$status" -eq 0 ]
  st=$(bash "$WS" status --mb "$BANK")
  jq -e '[.adapt.subitems[] | .id] == ["1.1","1.2"] and all(.adapt.subitems[]; .phase == "open" and .depth == 1)' <<<"$st"
  assert_substring "$(cat "$BANK/progress.md")" "ADaPT: item 1 split into 1.1, 1.2"
  # Disjoint Files → one wave.
  jq -e '[.[] | .wave] == [1,1]' <<<"$output"
  run bash "$WS" "done" --mb "$BANK"
  [ "$status" -eq 6 ]
  assert_substring "$output" "open sub-items: 1.1, 1.2"
  bash "$WS" sub-done 1.1 --mb "$BANK"
  run bash "$WS" "done" --mb "$BANK"
  [ "$status" -eq 6 ]
  bash "$WS" sub-done 1.2 --mb "$BANK"
  run bash "$WS" "done" --mb "$BANK"
  [ "$status" -eq 0 ]
  [ "$(bash "$WS" status --mb "$BANK" | jq -r .phase)" = "done" ]
}

@test "adapt: verify failed 3 times triggers the guard, 2 times does not" {
  bash "$WS" step verify_fail --mb "$BANK"
  bash "$WS" step verify_fail --mb "$BANK"
  run bash "$WS" adapt-check --mb "$BANK"
  [ "$status" -eq 0 ]
  jq -e '.trigger == false' <<<"$output"
  bash "$WS" step verify_fail --mb "$BANK"
  run bash "$WS" adapt-check --mb "$BANK"
  jq -e '.trigger == true and (.reasons | index("verify_fail_cycles")) != null' <<<"$output"
}

@test "adapt: token guard fires only when item_token_budget is set and exceeded" {
  run bash "$WS" adapt-check --item-tokens 999999 --mb "$BANK"
  jq -e '.trigger == false' <<<"$output"
  printf 'version: 1\nadapt: {enabled: true, item_token_budget: 1000}\n' >"$BANK/pipeline.yaml"
  run bash "$WS" adapt-check --item-tokens 1001 --mb "$BANK"
  jq -e '.trigger == true and .reasons == ["item_token_budget"]' <<<"$output"
}

@test "adapt: --no-adapt → no trigger and split refused (halt as before)" {
  for _ in 1 2 3; do bash "$WS" step verify_fail --mb "$BANK"; done
  run bash "$WS" adapt-check --no-adapt --mb "$BANK"
  jq -e '.trigger == false and .enabled == false' <<<"$output"
  run bash "$WS" split 1 --subitems "$TWO" --no-adapt --mb "$BANK"
  [ "$status" -eq 6 ]
  assert_substring "$output" "ADaPT disabled"
  [ "$(bash "$WS" status --mb "$BANK" | jq -r '.adapt // "none"')" = "none" ]
}

@test "adapt: adapt.enabled false in pipeline.yaml → unchanged (no trigger, no split)" {
  printf 'version: 1\nadapt: {enabled: false}\n' >"$BANK/pipeline.yaml"
  for _ in 1 2 3; do bash "$WS" step verify_fail --mb "$BANK"; done
  run bash "$WS" adapt-check --mb "$BANK"
  jq -e '.trigger == false' <<<"$output"
  run bash "$WS" split 1 --subitems "$TWO" --mb "$BANK"
  [ "$status" -eq 6 ]
  run bash "$WS" "done" --mb "$BANK"
  [ "$status" -eq 0 ]
}

@test "adapt: depth 3 is refused with a message; depth 2 allowed" {
  bash "$WS" split 1 --subitems "$TWO" --mb "$BANK" >/dev/null
  run bash "$WS" split 1.1 --subitems "$TWO" --mb "$BANK"
  [ "$status" -eq 0 ]
  jq -e '[.[] | .id] == ["1.1.1","1.1.2"] and .[0].depth == 2' <<<"$output"
  run bash "$WS" split 1.1.1 --subitems "$TWO" --mb "$BANK"
  [ "$status" -eq 6 ]
  assert_substring "$output" "max_depth 2"
  # A split sub-item closes only after its own children.
  run bash "$WS" sub-done 1.1 --mb "$BANK"
  [ "$status" -eq 6 ]
}

@test "adapt: split rejects an invalid sub-item list (1 entry)" {
  run bash "$WS" split 1 --subitems '[{"title":"x","Files":"a.py"}]' --mb "$BANK"
  [ "$status" -eq 2 ]
  assert_substring "$output" "2-5 sub-items"
}

@test "adapt: re-arming init on the same open item keeps its sub-items (resume)" {
  bash "$WS" split 1 --subitems "$TWO" --mb "$BANK" >/dev/null
  bash "$WS" init plan 1 --source-path "$PLAN" --source-topic demo --mb "$BANK" >/dev/null
  jq -e '(.adapt.subitems | length) == 2' <<<"$(bash "$WS" status --mb "$BANK")"
}

@test "adapt: mb-workflow.sh JSON carries the adapt block once per run; --no-adapt disables it" {
  python3 -c "import yaml" 2>/dev/null || skip "PyYAML required"
  run bash "$REPO_ROOT/scripts/mb-workflow.sh" --mb "$BANK" --json
  [ "$status" -eq 0 ]
  jq -e '.adapt == {"enabled":true,"verify_fail_cycles":3,"item_token_budget":null,"max_depth":2}' <<<"$output"
  run bash "$REPO_ROOT/scripts/mb-workflow.sh" --mb "$BANK" --no-adapt --json
  jq -e '.adapt.enabled == false' <<<"$output"
}
