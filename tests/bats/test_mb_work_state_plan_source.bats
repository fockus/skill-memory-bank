#!/usr/bin/env bats
# test_mb_work_state_plan_source.bats — the `done` eval gate on a PLAN source.
#
# A plan stage (`<!-- mb-stage:N -->`) has no Eval declaration surface, so the
# design (mb-work-state-eval.sh: NOFILE → allowed) certifies it as
# `unverified:no_declaration_surface`. Regression: eval_declaration treated any
# `.md` --source-path as a tasks.md and, finding no `task`-kind item, answered
# NOITEM — every plan-based /mb work run was refused at `done` (exit 5) and its
# checkboxes could never be flipped through the sanctioned sequence.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  WS="$REPO_ROOT/scripts/mb-work-state.sh"
  export LC_ALL=C
  TMP="$(mktemp -d)"
  BANK="$TMP/.memory-bank"
  mkdir -p "$BANK/plans" "$BANK/specs/demo"
  PLAN="$BANK/plans/2026-01-01_fix_demo.md"
  cat >"$PLAN" <<'PLAN'
---
type: fix
topic: demo
status: in_progress
---
# Plan: fix — demo

## Stages

<!-- mb-stage:1 -->
### Stage 1: the stage

**Role:** developer

**What to do:**
- do the thing

**DoD:**
- [ ] thing done
- [ ] tests pass

---
PLAN
  cat >"$BANK/specs/demo/tasks.md" <<'TASKS'
# Tasks: demo

<!-- mb-task:1 -->
## Task 1: only task

**Covers:** REQ-001
**Role:** backend
**Eval:** none — waiver: docs only

**DoD:**
- [ ] done
<!-- /mb-task:1 -->
TASKS
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

@test "work_state_plan: a plan stage has no declaration surface — done certifies unverified:no_declaration_surface" {
  run bash "$WS" init plan 1 --source-path "$PLAN" --source-topic fix_demo --mb "$BANK"
  [ "$status" -eq 0 ] || { echo "init failed: $output"; false; }
  run bash "$WS" done --mb "$BANK"
  [ "$status" -eq 0 ] || { echo "done refused a plan stage (rc=$status): $output"; false; }
  [[ "$output" == *"eval UNVERIFIED"* ]] || { echo "missing UNVERIFIED notice: $output"; false; }
  run bash "$WS" status --mb "$BANK"
  [[ "$output" == *'"eval_gate": "unverified:no_declaration_surface"'* ]] \
    || { echo "eval_gate not recorded as unverified: $output"; false; }
  [[ "$output" == *'"phase": "done"'* ]] || { echo "phase not done: $output"; false; }
}

@test "work_state_plan: a real tasks.md that lacks the item is still NOITEM — done refused" {
  run bash "$WS" init spec 2 --source-path "$BANK/specs/demo/tasks.md" --source-topic demo --mb "$BANK"
  [ "$status" -eq 0 ] || { echo "init failed: $output"; false; }
  run bash "$WS" done --mb "$BANK"
  [ "$status" -eq 5 ] || { echo "missing task certified (rc=$status): $output"; false; }
}
