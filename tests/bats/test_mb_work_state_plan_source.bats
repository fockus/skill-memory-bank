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

# I-196 — a resolved `tasks.md` IS the declaration surface. Whatever state it
# is in, the gate is bound to it: empty, marker-mangled or unparseable, the
# binding is broken and `done` must refuse — never certify
# `unverified:no_declaration_surface`, which means "there was nothing to gate".

@test "work_state_plan: an empty spec tasks.md is a broken surface — done refused" {
  : >"$BANK/specs/demo/tasks.md"
  run bash "$WS" init spec 1 --source-path "$BANK/specs/demo/tasks.md" --source-topic demo --mb "$BANK"
  [ "$status" -eq 0 ] || { echo "init failed: $output"; false; }
  run bash "$WS" done --mb "$BANK"
  [ "$status" -eq 5 ] || { echo "empty tasks.md certified (rc=$status): $output"; false; }
  run bash "$WS" status --mb "$BANK"
  [[ "$output" != *"unverified:no_declaration_surface"* ]] \
    || { echo "broken surface recorded as 'nothing to gate': $output"; false; }
}

@test "work_state_plan: a spec tasks.md with mangled markers is a broken surface — done refused" {
  printf '# Tasks: demo\n\nprose only, and a typo marker\n\n<!-- mbtask:1 -->\n## Task 1: x\n' \
    >"$BANK/specs/demo/tasks.md"
  run bash "$WS" init spec 1 --source-path "$BANK/specs/demo/tasks.md" --source-topic demo --mb "$BANK"
  [ "$status" -eq 0 ] || { echo "init failed: $output"; false; }
  run bash "$WS" done --mb "$BANK"
  [ "$status" -eq 5 ] || { echo "mangled tasks.md certified (rc=$status): $output"; false; }
}

@test "work_state_plan: a spec tasks.md the parser rejects is a broken surface — done refused" {
  printf '# Tasks: demo\n\n<!-- mb-stage:1 -->\n### Stage 1: s\n\n<!-- mb-task:1 -->\n## Task 1: t\n' \
    >"$BANK/specs/demo/tasks.md"
  run bash "$WS" init spec 1 --source-path "$BANK/specs/demo/tasks.md" --source-topic demo --mb "$BANK"
  [ "$status" -eq 0 ] || { echo "init failed: $output"; false; }
  run bash "$WS" done --mb "$BANK"
  [ "$status" -eq 5 ] || { echo "unparseable tasks.md certified (rc=$status): $output"; false; }
}

# A stage-marker PLAN that a legacy locator resolves at the `tasks.md` path is
# still a plan: the surface test must look at what the file CONTAINS, not at
# what it is called (I-208 / A).

@test "work_state_plan: a stage-marker plan resolved at tasks.md is a plan, not a task surface" {
  mkdir -p "$TMP/work"
  cp "$PLAN" "$TMP/work/tasks.md"
  # The legacy locator `work` resolves the directory to `work/tasks.md`
  # relative to the init caller's cwd — so the call must be made from there.
  run bash -c 'cd "$1" && bash "$2" init work 1 --mb "$3"' _ "$TMP" "$WS" "$BANK"
  [ "$status" -eq 0 ] || { echo "init failed: $output"; false; }
  run bash -c 'cd "$1" && bash "$2" done --mb "$3"' _ "$TMP" "$WS" "$BANK"
  [ "$status" -eq 0 ] || { echo "done refused a plan at tasks.md (rc=$status): $output"; false; }
  run bash "$WS" status --mb "$BANK"
  [[ "$output" == *'"verdict": "NOFILE"'* ]] \
    || { echo "plan at tasks.md classified as a declaration surface: $output"; false; }
}
