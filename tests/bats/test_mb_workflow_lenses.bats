#!/usr/bin/env bats
# mb-team Stage 6 (T-ENGINE): `mb-workflow.sh --lenses <csv>` → JSON
# `review_lenses`; without the new flags both engine scripts stay
# byte-identical to the plan baseline (NFR-TEAM-001).

load lib/assert

BASELINE=f050443e9d7c70eadf78cc8f1f5b72e6b01888f8

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  WORKFLOW="$REPO_ROOT/scripts/mb-workflow.sh"
  export PATH="$REPO_ROOT/.venv/bin:${PATH}"
  python3 -c "import yaml" 2>/dev/null || skip "PyYAML required"
  MB="$BATS_TEST_TMPDIR/.memory-bank"
  mkdir -p "$MB/plans/done" "$MB/specs"
  printf '# Checklist\n' > "$MB/checklist.md"
  printf '# Roadmap\n\n<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n' > "$MB/roadmap.md"
  cp "$REPO_ROOT/references/pipeline.default.yaml" "$MB/pipeline.yaml"
  {
    printf -- '---\ntype: feature\ntopic: p1\nstatus: in-progress\n---\n\n# Plan p1\n\n'
    for n in 1 2 3; do
      printf '<!-- mb-stage:%s -->\n## Stage %s: step %s\n\n- ⬜ DoD bit\n\n' "$n" "$n" "$n"
    done
  } > "$MB/plans/p1.md"
}

_lenses() {  # extra args → printed review_lenses (one per line) on $output
  run bash -c 'bash "$1" --mb "$2" --host claude-code "${@:3}" --json |
    python3 -c "import json,sys; print(\"\n\".join(json.load(sys.stdin)[\"review_lenses\"]))"' _ \
    "$WORKFLOW" "$MB" "$@"
}

@test "--lenses logic,security yields exactly those two lenses" {
  _lenses --workflow governed --no-judge --lenses logic,security
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'logic\nsecurity')" ]
}

@test "--lenses maps the quality alias to code_rules and drops duplicates" {
  _lenses --workflow governed --lenses quality,code_rules,tests
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'code_rules\ntests')" ]
}

@test "--lenses with an unknown lens exits 2 naming it" {
  run bash "$WORKFLOW" --mb "$MB" --workflow governed --lenses logic,style --json
  [ "$status" -eq 2 ]
  assert_substring "$output" "style"
}

@test "--lenses on a workflow without an ensemble review exits 2" {
  run bash "$WORKFLOW" --mb "$MB" --workflow medium --lenses logic --json
  [ "$status" -eq 2 ]
  assert_substring "$output" "ensemble"
}

@test "--lenses validates against a project review_ensemble" {
  python3 - "$MB/pipeline.yaml" <<'PY'
import sys, yaml
p = sys.argv[1]
cfg = yaml.safe_load(open(p))
cfg["review_ensemble"]["reviewers"] = [{"role": "reviewer_logic", "focus": "logic"},
                                       {"role": "reviewer_tests", "focus": "tests"}]
yaml.safe_dump(cfg, open(p, "w"), sort_keys=False)
PY
  run bash "$WORKFLOW" --mb "$MB" --workflow governed --lenses security --json
  [ "$status" -eq 2 ]
  assert_substring "$output" "security"
}

@test "without --lenses the JSON carries no review_lenses key" {
  run bash "$WORKFLOW" --mb "$MB" --workflow governed --json
  [ "$status" -eq 0 ]
  refute_substring "$output" "review_lenses"
}

# ── golden: no new flags → byte-identical to the plan baseline ────────────
# ponytail: pinned to the mb-team plan baseline; re-pin or drop once the plan
# is committed and a later change legitimately alters these outputs.

_baseline_tree() {  # → $OLD: a copy of scripts/ + references/ with baseline engine scripts
  git -C "$REPO_ROOT" cat-file -e "$BASELINE^{commit}" 2>/dev/null || skip "baseline commit unavailable"
  OLD="$BATS_TEST_TMPDIR/old"
  mkdir -p "$OLD"
  cp -R "$REPO_ROOT/scripts" "$REPO_ROOT/references" "$OLD/"
  for f in scripts/mb-workflow.sh scripts/mb-work-plan.sh scripts/mb_work_models.py; do
    git -C "$REPO_ROOT" show "$BASELINE:$f" > "$OLD/$f"
  done
}

@test "golden: mb-workflow.sh --json matches the baseline on every preset" {
  _baseline_tree
  for args in "" "--workflow governed" "--workflow complex --verify stage" "--tier large" \
      "--workflow simple" "--workflow governed --no-judge" "--steps --workflow full"; do
    # shellcheck disable=SC2086
    new=$(bash "$WORKFLOW" --mb "$MB" --host claude-code $args)
    # shellcheck disable=SC2086
    old=$(bash "$OLD/scripts/mb-workflow.sh" --mb "$MB" --host claude-code $args)
    [ "$new" = "$old" ] || { echo "differs for: $args"; diff <(echo "$old") <(echo "$new"); false; }
  done
}

@test "golden: mb-work-plan.sh output matches the baseline" {
  _baseline_tree
  for args in "" "--workflow governed --cost premium" "--verify stage --model opus" "--dry-run"; do
    # shellcheck disable=SC2086
    new=$(bash "$REPO_ROOT/scripts/mb-work-plan.sh" --target "$MB/plans/p1.md" --mb "$MB" --host claude-code $args)
    # shellcheck disable=SC2086
    old=$(bash "$OLD/scripts/mb-work-plan.sh" --target "$MB/plans/p1.md" --mb "$MB" --host claude-code $args)
    [ "$new" = "$old" ] || { echo "differs for: $args"; diff <(echo "$old") <(echo "$new"); false; }
  done
}
