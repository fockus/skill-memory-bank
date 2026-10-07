#!/usr/bin/env bats
# pipeline-presets-cost-tiers Stages 1-2 — verifier cadence (AGR-075) and
# complexity presets + effort_tiers (AGR-074, AGR-067).

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  WORKFLOW="$REPO_ROOT/scripts/mb-workflow.sh"
  WORK_PLAN="$REPO_ROOT/scripts/mb-work-plan.sh"
  VALIDATE="$REPO_ROOT/scripts/mb-pipeline-validate.sh"
  DEFAULT="$REPO_ROOT/references/pipeline.default.yaml"
  export PATH="$REPO_ROOT/.venv/bin:${PATH}"
  python3 -c "import yaml" 2>/dev/null || skip "PyYAML required"
  MB="$BATS_TEST_TMPDIR/.memory-bank"
  mkdir -p "$MB/plans/done" "$MB/specs"
  printf '# Checklist\n' > "$MB/checklist.md"
  printf '# Roadmap\n\n<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n' > "$MB/roadmap.md"
  cp "$DEFAULT" "$MB/pipeline.yaml"
  _plan p1
  _plan p2
}

_plan() {  # <name> → three-stage plan in the bank
  {
    printf -- '---\ntype: feature\ntopic: %s\nstatus: in-progress\n---\n\n# Plan %s\n\n' "$1" "$1"
    for n in 1 2 3; do
      printf '<!-- mb-stage:%s -->\n## Stage %s: step %s\n\n- ⬜ DoD bit\n\n' "$n" "$n" "$n"
    done
  } > "$MB/plans/$1.md"
}

_items() {  # extra args → JSON Lines on $output
  run bash "$WORK_PLAN" --mb "$MB" "$@"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

_count() {  # <needle> → occurrences in $output
  printf '%s\n' "$output" | grep -c -- "$1" || true
}

# ── Stage 1: cadence ────────────────────────────────────────────────────────

@test "cadence stage: every item gets a verify, the last one is final" {
  _items --target "$MB/plans/p1.md" --verify=stage
  [ "$(_count '"verify": true')" -eq 3 ]
  [ "$(_count '"final_verify": true')" -eq 1 ]
  assert_substring "$(printf '%s\n' "$output" | tail -1)" '"final_verify": true'
}

@test "cadence plan (default medium): only the last item verifies" {
  _items --target "$MB/plans/p1.md"
  [ "$(_count '"verify": true')" -eq 1 ]
  local last; last="$(printf '%s\n' "$output" | tail -1)"
  assert_substring "$last" '"verify": true'
  assert_substring "$last" '"final_verify": true'
}

@test "cadence off: no item verifies" {
  _items --target "$MB/plans/p1.md" --verify=off
  [ "$(_count '"verify": true')" -eq 0 ]
  [ "$(_count '"final_verify": true')" -eq 0 ]
  [ "$(_count '"verify": false')" -eq 3 ]
}

@test "cadence run over two plans: one verify, at the very end" {
  _items --target "$MB/plans/p1.md" --target "$MB/plans/p2.md" --verify=run
  [ "$(_count '"stage_no"')" -eq 6 ]
  [ "$(_count '"verify": true')" -eq 1 ]
  local last; last="$(printf '%s\n' "$output" | tail -1)"
  assert_substring "$last" '"plan": "p2.md"'
  assert_substring "$last" '"final_verify": true'
}

@test "cadence plan over two plans: one verify per plan end" {
  _items --target "$MB/plans/p1.md" --target "$MB/plans/p2.md" --verify=plan
  [ "$(_count '"verify": true')" -eq 2 ]
}

@test "several targets with --range are refused" {
  run bash "$WORK_PLAN" --mb "$MB" --target "$MB/plans/p1.md" --target "$MB/plans/p2.md" --range 1
  [ "$status" -eq 2 ]
}

@test "CLI --verify beats pipeline.yaml cadence" {
  run bash "$WORKFLOW" --mb "$MB" --json
  assert_substring "$output" '"verify_cadence": "plan"'
  run bash "$WORKFLOW" --mb "$MB" --verify=stage --json
  assert_substring "$output" '"verify_cadence": "stage"'
  run bash "$WORKFLOW" --mb "$MB" --verify off --json
  assert_substring "$output" '"verify_cadence": "off"'
}

@test "unknown --verify value is a usage error" {
  run bash "$WORKFLOW" --mb "$MB" --verify=weekly --json
  [ "$status" -eq 2 ]
  assert_substring "$output" "weekly"
}

@test "validate rejects an unknown cadence in pipeline.yaml" {
  sed -i.bak 's/cadence: plan/cadence: weekly/' "$MB/pipeline.yaml"
  run bash "$VALIDATE" "$MB/pipeline.yaml"
  [ "$status" -eq 1 ]
  assert_substring "$output" "cadence"
}

@test "a project workflow without cadence verifies once at plan end (AGR-075)" {
  run bash "$WORKFLOW" --mb "$REPO_ROOT/.memory-bank" --json
  [ "$status" -eq 0 ]
  assert_substring "$output" '"name": "execution"'
  assert_substring "$output" '"verify_cadence": "plan"'
  run bash "$WORKFLOW" --mb "$REPO_ROOT/.memory-bank" --workflow codex-governed --json
  assert_substring "$output" '"verify_cadence": "plan"'
}

@test "explicit cadence stage in config still wins over the plan fallback" {
  run bash "$WORKFLOW" --mb "$MB" --workflow implement-only --json
  assert_substring "$output" '"verify_cadence": "plan"'
  sed -i.bak 's/verify: {cadence: plan}/verify: {cadence: stage}/' "$MB/pipeline.yaml"
  run bash "$WORKFLOW" --mb "$MB" --workflow medium --json
  assert_substring "$output" '"verify_cadence": "stage"'
}

@test "work-plan without resolvable workflow config falls back to plan cadence" {
  printf 'version: 1\nworkflows: [broken\n' > "$MB/pipeline.yaml"
  _items --target "$MB/plans/p1.md"
  [ "$(_count '"verify": true')" -eq 1 ]
}

# ── Stage 2: presets + effort tiers ─────────────────────────────────────────

@test "each preset resolves to its steps" {
  run bash "$WORKFLOW" --mb "$MB" --workflow simple --json
  assert_substring "$output" '"steps": ["implement", "done"]'
  assert_substring "$output" '"self_verify": true'
  assert_substring "$output" '"verify_cadence": "off"'
  run bash "$WORKFLOW" --mb "$MB" --workflow medium --json
  assert_substring "$output" '"steps": ["implement", "verify", "done"]'
  assert_substring "$output" '"self_verify": false'
  run bash "$WORKFLOW" --mb "$MB" --workflow complex --json
  assert_substring "$output" '"steps": ["implement", "verify", "review", "fix", "done"]'
  assert_substring "$output" '"max_cycles": 2'
  run bash "$WORKFLOW" --mb "$MB" --workflow governed --json
  assert_substring "$output" '"steps": ["implement", "verify", "review", "judge", "fix", "done"]'
}

@test "default is medium with cadence plan" {
  run bash "$WORKFLOW" --mb "$MB" --json
  assert_substring "$output" '"name": "medium"'
  assert_substring "$output" '"steps": ["implement", "verify", "done"]'
}

@test "legacy names resolve to the new presets" {
  run bash "$WORKFLOW" --mb "$MB" --workflow execution --json
  assert_substring "$output" '"name": "medium"'
  run bash "$WORKFLOW" --mb "$MB" --workflow governed-execution --json
  assert_substring "$output" '"name": "governed"'
  run bash "$WORKFLOW" --mb "$MB" --workflow strict --json
  assert_substring "$output" '"name": "governed"'
  run bash "$WORKFLOW" --mb "$MB" --workflow implement-only --json
  assert_substring "$output" '"steps": ["implement", "verify"]'
}

@test "--tier extra resolves to governed with review and judge" {
  run bash "$WORKFLOW" --mb "$MB" --tier extra --json
  [ "$status" -eq 0 ]
  assert_substring "$output" '"name": "governed"'
  assert_substring "$output" '"review"'
  assert_substring "$output" '"judge"'
}

@test "--tier small resolves to simple with self_verify" {
  run bash "$WORKFLOW" --mb "$MB" --tier small --json
  assert_substring "$output" '"name": "simple"'
  assert_substring "$output" '"self_verify": true'
}

@test "--tier trivial exits 2 with a no-/mb-work hint" {
  run bash "$WORKFLOW" --mb "$MB" --tier trivial --json
  [ "$status" -eq 2 ]
  assert_substring "$output" "no /mb work needed"
}

@test "--tier unknown is a usage error" {
  run bash "$WORKFLOW" --mb "$MB" --tier huge --json
  [ "$status" -eq 2 ]
  assert_substring "$output" "huge"
}

@test "simple items carry no verify" {
  _items --target "$MB/plans/p1.md" --workflow simple
  [ "$(_count '"verify": true')" -eq 0 ]
}

@test "validate rejects an effort tier pointing at an undeclared workflow" {
  sed -i.bak 's/^  large: complex/  large: enormous/' "$MB/pipeline.yaml"
  run bash "$VALIDATE" "$MB/pipeline.yaml"
  [ "$status" -eq 1 ]
  assert_substring "$output" "effort_tiers.large"
}

@test "default and this repo's pipeline.yaml both validate" {
  run bash "$VALIDATE" "$DEFAULT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run bash "$VALIDATE" "$REPO_ROOT/.memory-bank/pipeline.yaml"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "this repo still resolves execution and codex-governed as before" {
  run bash "$WORKFLOW" --mb "$REPO_ROOT/.memory-bank" --steps
  [ "$output" = "$(printf 'implement\nverify\ndone')" ]
  run bash "$WORKFLOW" --mb "$REPO_ROOT/.memory-bank" --workflow codex-governed --steps
  [ "$output" = "$(printf 'implement\nverify\nreview\njudge\nfix\ndone')" ]
}

_legacy_pipeline() {  # a project pipeline.yaml scaffolded before presets existed
  cat > "$MB/pipeline.yaml" <<'YAML'
version: 2
workflow:
  default: execution
workflows:
  execution:
    steps: [implement, verify, review, done]
YAML
}

@test "legacy project pipeline: presets and --tier fall back to the bundled defaults" {
  _legacy_pipeline
  run bash "$WORKFLOW" --mb "$MB" --tier extra --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  assert_substring "$output" '"name": "governed"'
  run bash "$WORKFLOW" --mb "$MB" --workflow simple --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  assert_substring "$output" '"self_verify": true'
}

@test "legacy project pipeline: its own workflow wins over a default alias of the same name" {
  _legacy_pipeline
  run bash "$WORKFLOW" --mb "$MB" --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  assert_substring "$output" '"name": "execution"'
  assert_substring "$output" '"steps": ["implement", "verify", "review", "done"]'
}
