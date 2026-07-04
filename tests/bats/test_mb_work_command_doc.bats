#!/usr/bin/env bats
# Doc contract: commands/work.md describes Sprint 2 work-engine behavior.
#
# Every assertion here must be satisfied by the current state of commands/work.md.
# If a test fails, the doc is out of date with the spec.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DOC="$REPO_ROOT/commands/work.md"
  [ -f "$DOC" ] || skip "commands/work.md missing"
}

@test "doc mentions specs/<topic>/tasks.md as executable" {
  run grep -E "specs/.*tasks\.md" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc mentions linked_spec frontmatter for plan-as-wrapper" {
  run grep -q "linked_spec" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc mentions mb-task marker format" {
  run grep -q "mb-task" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc documents the 5 target resolution forms" {
  run grep -qi "topic" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qiE "freeform|active plan|empty target" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc does not claim plan-only execution" {
  run grep -qi "plan-only execution" "$DOC"
  [ "$status" -ne 0 ]
  run grep -qi "tasks.md is human-only" "$DOC"
  [ "$status" -ne 0 ]
  run grep -qi "tasks.md is a scaffold" "$DOC"
  [ "$status" -ne 0 ]
}

@test "doc includes source and kind fields in JSON schema" {
  run grep -q '"source"' "$DOC"
  [ "$status" -eq 0 ]
  run grep -q '"kind"' "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc includes covers field in JSON schema" {
  run grep -q '"covers"' "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc includes item_no as alias for stage_no" {
  run grep -q '"item_no"' "$DOC"
  [ "$status" -eq 0 ]
}

# ── I-093 S3: durable loop-state + budget run_id wiring ────────────────────

@test "doc mentions mb-work-state.sh and .work-state.json" {
  run grep -q "mb-work-state.sh" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q ".work-state.json" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc states 5f calls mb-work-state.sh cycle and halts on exit 3" {
  run grep -q "mb-work-state.sh cycle" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "exit 3" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "cycle budget exhausted" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc's Hard-stops table lists the cycle-exhausted trigger via mb-work-state.sh cycle" {
  run grep -qi "cycle-exhausted" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q "mb-work-state.sh cycle" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc threads budget init/check with --run-id from mb-work-state.sh init" {
  run grep -q -- "--run-id" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q "RUN_ID=\$(bash scripts/mb-work-state.sh init" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc describes resume path trusting work-state phase over checkboxes" {
  run grep -q "mb-work-state.sh status" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "phase.*in-progress" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "mid-flight" "$DOC"
  [ "$status" -eq 0 ]
}

# ── I-093 S5: checkbox flip discipline ──────────────────────────────────────

@test "doc's implement prompt bans agents from editing DoD checkboxes" {
  run grep -qi "do not edit dod checkboxes" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q "mb-work-checkbox.sh" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc's 5g sequences mb-work-state.sh done then mb-work-checkbox.sh flip, refusal means gate not passed" {
  run grep -q "mb-work-checkbox.sh flip" "$DOC"
  [ "$status" -eq 0 ]
  done_line=$(grep -n "mb-work-state.sh done" "$DOC" | head -1 | cut -d: -f1)
  flip_line=$(grep -n "mb-work-checkbox.sh flip" "$DOC" | head -1 | cut -d: -f1)
  [ -n "$done_line" ]
  [ -n "$flip_line" ]
  [ "$done_line" -lt "$flip_line" ]
  run grep -qi "refused flip\|refused.*exit 1\|exit 1.*refus" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc's resume note names .work-state.json phase as the source of truth for completion" {
  run grep -qi "source of truth" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q ".work-state.json" "$DOC"
  [ "$status" -eq 0 ]
}
