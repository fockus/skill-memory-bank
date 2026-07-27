#!/usr/bin/env bats
# self_check_r4: — svp-sdd-core round-4 review findings [1] and [7] on the C8a
# battery executor (scripts/mb-sdd-self-check.sh).
#
#   [1] BLOCKER — the battery ran the user-supplied Eval command AFTER the
#       structural checks had already failed. A spec known to be malformed is
#       not a spec to execute code against: the verdict cannot change, and an
#       unreviewed command from a rejected artifact still got to run.
#   [7] MAJOR   — a valid ANCHORLESS Eval (C1: anchors are optional for a
#       non-gated task, red = `exit != 0`) was reported `invalid`, so a correct
#       declaration blocked draft→ready.
#
# Name convention (X-05): every @test starts with `self_check_r4: `.
#
# Every "did not happen" assertion here goes through tests/bats/lib/assert.bash
# — a bare `! cmd` is exempt from `set -e` unless it is the last command in the
# body, which is how a decorative assertion gets written by accident (I-147).

bats_require_minimum_version 1.5.0

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SELFCHECK="$REPO_ROOT/scripts/mb-sdd-self-check.sh"
  TMPDIR="$(mktemp -d)"            # private to this test — never a shared dir
  SPECS="$TMPDIR/specs"
  ROOT="$TMPDIR/root"              # behavioural run root (Eval targets live here)
  RAN="$TMPDIR/eval-ran.marker"    # the target touches this IF it is executed
  mkdir -p "$SPECS" "$ROOT/tests/sh"
  export LC_ALL=C
  DASH=$'\xe2\x80\x94'
  ORE='not ok [0-9]+ demo_persist'
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

# ── fixtures ────────────────────────────────────────────────────────────────
#
# Every EARS-valid requirement carries `shall`, so a requirement is ALWAYS
# gated; the non-gated case is a task covering a REQ this spec does not define
# (`REQ-100`) — the same shape the validator suite uses for its waiver fixtures.
_reqs() {
  cat >"$1/requirements.md" <<EOF
# Requirements: demo

## Requirements (EARS)

- **REQ-001** (ubiquitous): The system shall persist work items to disk.

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: persist round trip
**Covers:** REQ-001

- GIVEN a work item
- WHEN it is persisted
- THEN it round-trips
<!-- /mb-scenario:1 -->
EOF
}

# _tasks1 <dir> <eval-cmd> <anchors> [extra-field-line]
_tasks1() {
  cat >"$1/tasks.md" <<EOF
# Tasks: demo

<!-- mb-task:1 -->
## Task 1: persist work items

**Covers:** REQ-001
**Role:** backend
${4:+$4
}**Eval:** $2 ${DASH} red: demo assertion fails$3

**What to do:**
- persist to disk.

**Testing (TDD — tests BEFORE implementation):**
- round-trip test.

**DoD:**
- [ ] persist works.
<!-- /mb-task:1 -->
EOF
}

_design1() {
  cat >"$1/design.md" <<EOF
# Design: demo

## Contract

**Seams:**
- the persistence boundary

## Eval declarations

- **T1** ${DASH} persist work items:
  **Eval:** $2 ${DASH} red: demo assertion fails$3
EOF
}

# mk1 <topic> <eval-cmd> <anchors> [extra-task-field] → prints spec dir
mk1() {
  local dir="$SPECS/$1"
  mkdir -p "$dir"
  _reqs "$dir"
  _tasks1 "$dir" "$2" "$3" "${4:-}"
  _design1 "$dir" "$2" "$3"
  printf '%s\n' "$dir"
}

# mk2 <topic> <task2-eval-cmd> → prints spec dir.
# Task 1 stays the gated, fully anchored task (its target is deliberately absent
# → pending_materialization, which is not a failure); task 2 covers an
# undefined REQ, i.e. is NON-GATED, and carries an ANCHORLESS Eval — exactly the
# declaration C1 permits and review [7] is about.
mk2() {
  local dir="$SPECS/$1"
  mkdir -p "$dir"
  _reqs "$dir"
  _tasks1 "$dir" 'bash tests/sh/absent.sh' "; exit: 1; output~: $ORE"
  cat >>"$dir/tasks.md" <<EOF

<!-- mb-task:2 -->
## Task 2: docs only

**Covers:** REQ-100
**Role:** developer
**Eval:** $2 ${DASH} red: the doc section is absent

**Testing:** structural check only.

**DoD:**
- [ ] docs updated.
<!-- /mb-task:2 -->
EOF
  _design1 "$dir" 'bash tests/sh/absent.sh' "; exit: 1; output~: $ORE"
  cat >>"$dir/design.md" <<EOF
- **T2** ${DASH} docs only:
  **Eval:** $2 ${DASH} red: the doc section is absent
EOF
  printf '%s\n' "$dir"
}

# A target that RECORDS its own execution, then produces the declared red.
mk_marking_red_target() {
  printf '#!/usr/bin/env bash\n: > %s\necho "not ok 1 demo_persist"\nexit 1\n' "$RAN" >"$ROOT/$1"
  chmod +x "$ROOT/$1"
}

# ── [1] a structural failure short-circuits the battery ─────────────────────

@test "self_check_r4: [1] a structural failure executes NO Eval command" {
  # The Eval target is present and would produce a perfectly good red — the
  # point is that a spec already known malformed must not get to run it.
  local dir; dir="$(mk1 demo 'bash tests/sh/red.sh' "; exit: 1; output~: $ORE" '**Blocked-by:** 1')"
  mk_marking_red_target tests/sh/red.sh
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "self_check=invalid" ]
  refute_file "$RAN" \
    || { echo "the Eval command ran despite a structural failure"; false; }
  # …and no behavioural verdict is invented for a battery that never ran.
  refute_substring "$output" "eval.1=" \
    || { echo "a behavioural eval line was emitted after a structural failure: $output"; false; }
}

@test "self_check_r4: [1] the short-circuit still says WHY the spec is structural-invalid" {
  # Silently dropping the eval lines would be a regression in diagnosability:
  # the structural violation itself has to reach the caller.
  local dir; dir="$(mk1 demo 'bash tests/sh/red.sh' "; exit: 1; output~: $ORE" '**Blocked-by:** 1')"
  mk_marking_red_target tests/sh/red.sh
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 1 ]
  assert_substring "$stderr" "REQ-052" \
    || { echo "structural violations are swallowed: stderr=$stderr"; false; }
}

@test "self_check_r4: [1] a structurally clean spec still runs its Eval command" {
  # Guards the over-correction: the short-circuit must not disable the battery.
  local dir; dir="$(mk1 demo 'bash tests/sh/red.sh' "; exit: 1; output~: $ORE")"
  mk_marking_red_target tests/sh/red.sh
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "self_check=ready" ]
  assert_substring "$output" "eval.1=ready"
  [ -f "$RAN" ] || { echo "the Eval command was not executed on a clean spec"; false; }
}

# ── [7] anchorless Eval (non-gated) — red is `exit != 0` per C1 ─────────────

@test "self_check_r4: [7] an anchorless Eval that actually fails is a red → ready" {
  # C1: «Для non-gated якоря опциональны; тогда red считается по exit != 0».
  # The helper reported `invalid`, i.e. a correct declaration blocked ready.
  local dir; dir="$(mk2 demo 'bash tests/sh/red.sh')"
  mk_marking_red_target tests/sh/red.sh
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 0 ] || { echo "anchorless red rejected (rc=$status): $output $stderr"; false; }
  assert_substring "$output" "eval.2=ready" \
    || { echo "a valid anchorless red was not reported ready: $output"; false; }
}

@test "self_check_r4: [7] an anchorless Eval that is already green stays invalid" {
  # The complement: dropping the anchor requirement must not license a green
  # command as a red — that is the [6] defect, and it is still closed.
  local dir; dir="$(mk2 demo 'bash tests/sh/green.sh')"
  printf '#!/usr/bin/env bash\necho "ok 1 demo_persist"\nexit 0\n' >"$ROOT/tests/sh/green.sh"
  chmod +x "$ROOT/tests/sh/green.sh"
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 1 ]
  assert_substring "$output" "eval.2=invalid"
}
