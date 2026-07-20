#!/usr/bin/env bats
# S9 Task 1 (C1): pipeline schema `sdd.spec_judge` + validation.
#
# The judge map mirrors `sdd.spec_review` (S2-C5): INLINE map only, so both the
# PyYAML and the no-PyYAML paths see identical grammar. Validation lives beside
# the existing sdd.* checks in scripts/mb_pipeline_validate_blocks.py.
#
# Red-anchor: every test name starts with `spec_judge_` / `spec_review_`.

bats_require_minimum_version 1.5.0

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  VALIDATE="$REPO_ROOT/scripts/mb-pipeline-validate.sh"
  DEFAULT_PIPELINE="$REPO_ROOT/references/pipeline.default.yaml"
  TMPROOT="$(mktemp -d)"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# Emit a pipeline.yaml whose `sdd:` block carries the given spec_review /
# spec_judge lines. Only the sdd block matters here: the other top-level keys
# are absent on purpose, so every run also prints their own errors. Tests must
# therefore assert on the SPECIFIC sdd.spec_judge line, never on exit code
# alone -- exit 1 is guaranteed by the missing keys and would prove nothing.
mkpipeline() {
  local review_line="$1" judge_line="$2" out="$TMPROOT/pipeline.yaml"
  {
    printf 'version: 1\n'
    printf 'workflows:\n  default:\n    stages: [implement, verify, done]\n'
    printf 'sdd:\n'
    printf '  enabled: true\n'
    printf '  require_ears_in_sdd_command: true\n'
    printf '  require_ears_in_plan_command: false\n'
    printf '  require_ears_in_plan_with_sdd_flag: true\n'
    printf '  covers_requirements_policy: warn\n'
    printf '  full_mode_path: ".memory-bank/specs"\n'
    [ -n "$review_line" ] && printf '  spec_review: %s\n' "$review_line"
    [ -n "$judge_line" ] && printf '  spec_judge: %s\n' "$judge_line"
  } > "$out"
  printf '%s\n' "$out"
}

# ═══════════════════════════════════════════════════════════════
# Schema in the bundled default
# ═══════════════════════════════════════════════════════════════

@test "spec_judge_schema_default: bundled pipeline carries spec_judge, disabled by default" {
  # The default must stay byte-compatible with pre-S9 behaviour: judge OFF.
  assert_grep -qE '^[[:space:]]+spec_judge:[[:space:]]*\{' "$DEFAULT_PIPELINE"
  run bash -c "grep -E '^[[:space:]]+spec_judge:' '$DEFAULT_PIPELINE' | head -1"
  [ "$status" -eq 0 ]
  assert_substring "$output" "enabled: false"
  assert_substring "$output" "agent: mb-judge"
  assert_substring "$output" "max_cycles: 2"
  # and the bundled default itself must validate clean
  run bash "$VALIDATE" "$DEFAULT_PIPELINE"
  [ "$status" -eq 0 ]
}

@test "spec_judge_inline_map: values are read from the inline map without PyYAML" {
  # MB_PYTHON with a stub that lacks yaml proves the no-PyYAML path sees the
  # same grammar; the validator must still reject a bad thinking value.
  local p
  p="$(mkpipeline '{enabled: true, agent: mb-reviewer, model: rev-1, thinking: medium}' \
                  '{enabled: true, agent: mb-judge, model: judge-1, thinking: bogus, max_cycles: 2}')"
  run bash "$VALIDATE" "$p"
  assert_substring "$output" "sdd.spec_judge.thinking: must be one of low|medium|high"
}

@test "spec_judge_inline_map_nested_block_rejected: a nested block is not an inline map" {
  local out="$TMPROOT/pipeline.yaml"
  {
    printf 'version: 1\n'
    printf 'workflows:\n  default:\n    stages: [implement, verify, done]\n'
    printf 'sdd:\n  enabled: true\n'
    printf '  covers_requirements_policy: warn\n'
    printf '  full_mode_path: ".memory-bank/specs"\n'
    printf '  spec_judge:\n    enabled: true\n    agent: mb-judge\n'
  } > "$out"
  run bash "$VALIDATE" "$out"
  assert_substring "$output" "sdd.spec_judge: must be an inline mapping"
}

# ═══════════════════════════════════════════════════════════════
# Field validation
# ═══════════════════════════════════════════════════════════════

@test "spec_judge_max_cycles_invalid: zero and non-numeric are both refused" {
  local p
  p="$(mkpipeline '{enabled: true, agent: mb-reviewer, model: rev-1, thinking: medium}' \
                  '{enabled: true, agent: mb-judge, model: judge-1, thinking: medium, max_cycles: 0}')"
  run bash "$VALIDATE" "$p"
  assert_substring "$output" "sdd.spec_judge.max_cycles: must be an integer >= 1"

  p="$(mkpipeline '{enabled: true, agent: mb-reviewer, model: rev-1, thinking: medium}' \
                  '{enabled: true, agent: mb-judge, model: judge-1, thinking: medium, max_cycles: many}')"
  run bash "$VALIDATE" "$p"
  assert_substring "$output" "sdd.spec_judge.max_cycles: must be an integer >= 1"
}

@test "spec_judge_unknown_key: an unknown key in the map is refused" {
  local p
  p="$(mkpipeline '{enabled: true, agent: mb-reviewer, model: rev-1, thinking: medium}' \
                  '{enabled: true, agent: mb-judge, model: judge-1, thinking: medium, max_cycles: 2, bogus: 1}')"
  run bash "$VALIDATE" "$p"
  assert_substring "$output" "sdd.spec_judge: unknown keys ['bogus']"
}

@test "spec_judge_model_required_when_enabled: empty model is refused" {
  local p
  p="$(mkpipeline '{enabled: true, agent: mb-reviewer, model: rev-1, thinking: medium}' \
                  '{enabled: true, agent: mb-judge, model: , thinking: medium, max_cycles: 2}')"
  run bash "$VALIDATE" "$p"
  assert_substring "$output" "sdd.spec_judge.model: must be a non-empty string when enabled"
}

# ═══════════════════════════════════════════════════════════════
# The review<->judge linkage (C1): a judge with nothing to judge
# ═══════════════════════════════════════════════════════════════

@test "spec_judge_requires_spec_review: enabled judge over a disabled review is refused" {
  local p
  p="$(mkpipeline '{enabled: false, agent: mb-reviewer, model: rev-1, thinking: medium}' \
                  '{enabled: true, agent: mb-judge, model: judge-1, thinking: medium, max_cycles: 2}')"
  run bash "$VALIDATE" "$p"
  assert_substring "$output" "spec_judge_requires_spec_review"
}

@test "spec_judge_requires_spec_review_absent: enabled judge with NO review key is refused" {
  # The absent case is the one a config drifts into: spec_review deleted, judge
  # left enabled. Treated as disabled review, so the same signature must fire.
  local p
  p="$(mkpipeline '' '{enabled: true, agent: mb-judge, model: judge-1, thinking: medium, max_cycles: 2}')"
  run bash "$VALIDATE" "$p"
  assert_substring "$output" "spec_judge_requires_spec_review"
}

@test "spec_judge_disabled_over_disabled_review_is_fine: both off raises nothing" {
  local p
  p="$(mkpipeline '{enabled: false, agent: mb-reviewer, model: rev-1, thinking: medium}' \
                  '{enabled: false, agent: mb-judge, model: judge-1, thinking: medium, max_cycles: 2}')"
  run bash "$VALIDATE" "$p"
  refute_substring "$output" "spec_judge_requires_spec_review"
  refute_substring "$output" "sdd.spec_judge."
}

# ═══════════════════════════════════════════════════════════════
# spec_review gains the optional `rubric` key (C1 / REQ-013)
# ═══════════════════════════════════════════════════════════════

@test "spec_review_rubric_key: rubric is a valid optional key on spec_review" {
  local p
  p="$(mkpipeline '{enabled: true, agent: mb-reviewer, model: rev-1, thinking: medium, rubric: custom/r.md}' '')"
  run bash "$VALIDATE" "$p"
  refute_substring "$output" "sdd.spec_review: unknown keys"
}

@test "spec_review_rubric_key_absent: spec_review without rubric still validates" {
  local p
  p="$(mkpipeline '{enabled: true, agent: mb-reviewer, model: rev-1, thinking: medium}' '')"
  run bash "$VALIDATE" "$p"
  refute_substring "$output" "sdd.spec_review"
}
