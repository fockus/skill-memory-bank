#!/usr/bin/env bats
# source_bundle: — planning-qa-sources C4/C5/C6, Task 4. Work items carry
# spec_path/plan_path (spec-sourced only) and commands/work.md wires the bundle.

bats_require_minimum_version 1.5.0
load 'lib/discuss_contract'

# work.md nests its 5x headings under list item 5 (indented); mb_section needs column 0.
wk_section() {
  sed -E 's/^ +//' "$1" > "$BATS_TEST_TMPDIR/dedent.md"
  mb_section "$BATS_TEST_TMPDIR/dedent.md" "$2"
}

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  WORK_PLAN="$REPO_ROOT/scripts/mb-work-plan.sh"
  WORKFLOW="$REPO_ROOT/scripts/mb-workflow.sh"
  GOLDEN="$REPO_ROOT/tests/bats/fixtures/qa-golden"
  export PATH="$REPO_ROOT/.venv/bin:${PATH}"
  python3 -c "import yaml" 2>/dev/null || skip "PyYAML required"
  TMP="$BATS_TEST_TMPDIR"
  MB="$TMP/.memory-bank"
  mkdir -p "$MB/plans/done" "$MB/specs/demo"
  printf '# Checklist\n' > "$MB/checklist.md"
  printf '# Roadmap\n\n<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n' > "$MB/roadmap.md"
  cp "$REPO_ROOT/references/pipeline.default.yaml" "$MB/pipeline.yaml"
  printf '# Tasks\n\n<!-- mb-task:1 -->\n## Task 1: a\n\n**Eval:** none — waiver: docs\n\n**DoD:**\n- [ ] one\n<!-- /mb-task:1 -->\n' > "$MB/specs/demo/tasks.md"
  _wrapper w1
  W="$REPO_ROOT/commands/work.md"
  MB_DISCUSS_CLAUSES+=("sb-qa-on|mb_rule|1|plan.s .qa: on. declaration counts as .--qa. for both|qa: on|s/counts as/ignores/|REQ-018")
  MB_DISCUSS_CLAUSES+=("sb-select|wk_section|5c2\. QA .*|@<topic>.*QA from the declaration.*cadence .stage. or .plan.|@<topic>|s/QA from the declaration/QA from nothing/|REQ-018")
  MB_DISCUSS_CLAUSES+=("sb-mbcase|wk_section|5c2\. QA .*|regression test for a blocking bug carries .mb:case reg-|mb:case reg-|s/regression test for/test for/|REQ-009")
  MB_DISCUSS_CLAUSES+=("sb-verifier-lines|wk_section|5c\. Verify step .*|Spec: .*Plan wrapper: .*QA cases: .*QA report: |Plan wrapper:|s/QA report: /QA log: /|REQ-013")
  MB_DISCUSS_CLAUSES+=("sb-nothing|wk_section|5c\. Verify step .*|NOTHING TO VERIFY.*halts the item|NOTHING TO VERIFY|s/halts the item/continues/|REQ-017")
  MB_DISCUSS_CLAUSES+=("sb-source-5d|wk_section|5d\. Review step .*|--source. for each present.*spec_path.*plan_path.*QA report|--source|s/for each present/never/|REQ-013")
  MB_DISCUSS_CLAUSES+=("sb-judge|wk_section|5e\. Judge step .*|## Sources. section.*same bytes|## Sources|s/same bytes the reviewer/a summary the reviewer/|REQ-013")
}

_wrapper() {  # <name> [extra frontmatter]
  printf -- '---\ntype: feature\ntopic: demo\nlinked_spec: specs/demo\n%sstatus: in-progress\n---\n\n# Wrapper\n' "${2:-}" > "$MB/plans/$1.md"
}

_key() {  # <key> → value of the first JSON line, empty when absent
  python3 -c 'import json,sys; print(json.loads(sys.stdin.readline()).get(sys.argv[1], ""))' "$1"
}

_norm() { sed "s#$(cd "$TMP" && pwd -P)#@TMP@#g; s#$TMP#@TMP@#g"; }

@test "source_bundle: wrapper target emits spec_path and plan_path" {
  run bash "$WORK_PLAN" --mb "$MB" --target w1
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | _key spec_path)" = "$(cd "$MB/specs/demo" && pwd -P)" ]
  [ "$(printf '%s\n' "$output" | _key plan_path)" = "$(cd "$MB/plans" && pwd -P)/w1.md" ]
}

@test "source_bundle: direct topic target finds its single wrapper" {
  run bash "$WORK_PLAN" --mb "$MB" --target demo
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | _key spec_path)" = "$(cd "$MB/specs/demo" && pwd -P)" ]
  [ "$(printf '%s\n' "$output" | _key plan_path)" = "$(cd "$MB/plans" && pwd -P)/w1.md" ]
}

@test "source_bundle: direct topic target without a wrapper has spec_path only" {
  rm "$MB/plans/w1.md"
  run bash "$WORK_PLAN" --mb "$MB" --target demo
  [ "$status" -eq 0 ]
  [ -n "$(printf '%s\n' "$output" | _key spec_path)" ]
  [ -z "$(printf '%s\n' "$output" | _key plan_path)" ]
}

@test "source_bundle: two wrappers omit plan_path and print one notice" {
  _wrapper w2
  run --separate-stderr bash "$WORK_PLAN" --mb "$MB" --target demo
  [ "$status" -eq 0 ]
  [ -n "$(printf '%s\n' "$output" | _key spec_path)" ]
  [ -z "$(printf '%s\n' "$output" | _key plan_path)" ]
  [ "$(printf '%s\n' "$stderr" | grep -c 'wrappers')" -eq 1 ]
}

@test "source_bundle: plain plan emits neither key and equals the QA-off golden" {
  rm "$MB/plans/w1.md"
  for n in p1 p2; do
    {
      printf -- '---\ntype: feature\ntopic: %s\nstatus: in-progress\n---\n\n# Plan %s\n\n' "$n" "$n"
      for s in 1 2 3; do printf '<!-- mb-stage:%s -->\n## Stage %s: step %s\n\n- ⬜ DoD bit\n\n' "$s" "$s" "$s"; done
    } > "$MB/plans/$n.md"
  done
  bash "$WORK_PLAN" --mb "$MB" --host claude-code --target p1 | _norm > "$TMP/plan.jsonl"
  diff "$GOLDEN/plan.jsonl" "$TMP/plan.jsonl"
  ! grep -q 'spec_path\|plan_path' "$TMP/plan.jsonl"
}

@test "source_bundle: workflow JSON for a plan without qa on equals the QA-off golden" {
  bash "$WORKFLOW" --mb "$MB" --host claude-code --json > "$TMP/wf.json"
  cmp -s "$GOLDEN/workflow.json" "$TMP/wf.json"
}

@test "source_bundle: work.md clause — qa on in the plan counts as --qa" {
  run assert_clause "$W" sb-qa-on; [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$W" sb-qa-on; [ "$status" -eq 0 ]
}

@test "source_bundle: work.md clauses — QA selection and the mb:case rule" {
  for id in sb-select sb-mbcase; do
    run assert_clause "$W" "$id"; [ "$status" -eq 0 ]
    run assert_clause_load_bearing "$W" "$id"; [ "$status" -eq 0 ] || { echo "$output"; false; }
  done
}

@test "source_bundle: work.md clauses — verifier lines and NOTHING TO VERIFY halt" {
  for id in sb-verifier-lines sb-nothing; do
    run assert_clause "$W" "$id"; [ "$status" -eq 0 ]
    run assert_clause_load_bearing "$W" "$id"; [ "$status" -eq 0 ] || { echo "$output"; false; }
  done
}

@test "source_bundle: work.md clauses — review --source and judge Sources bytes" {
  for id in sb-source-5d sb-judge; do
    run assert_clause "$W" "$id"; [ "$status" -eq 0 ]
    run assert_clause_load_bearing "$W" "$id"; [ "$status" -eq 0 ] || { echo "$output"; false; }
  done
}
