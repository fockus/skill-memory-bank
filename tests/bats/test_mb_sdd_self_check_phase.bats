#!/usr/bin/env bats
# self_check_phase: — AGR-037 (phase) + I-172 (a reason for every `invalid`)
# for the C8a battery executor (scripts/mb-sdd-self-check.sh).
#
# AGR-037. The battery required every Eval to be RED, and C7 made its exit 0 the
# only route to `status: ready`. So `ready` was reachable only while the spec was
# UNIMPLEMENTED: the moment the code lands, every Eval turns green and the gate
# closes forever — the exact opposite of what the word means. Measured on the
# spec that defines the gate: `eval.1=invalid … eval.9=invalid` while
# `pytest tests/pytest/test_work_items_v2.py` reported `33 passed`.
#
#   --phase generation : the declared red must be observable (a task that
#                        changes nothing cannot pass)
#   --phase done       : the Eval must actually be green
#
# I-172. `invalid` had at least four distinguishable causes and the battery
# emitted ZERO stderr lines for nine of them — four source-reading steps instead
# of one line of output. Every non-obvious verdict now carries a reason.
#
# Name convention (X-05): every @test starts with `self_check_phase: `.

bats_require_minimum_version 1.5.0

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SELFCHECK="$REPO_ROOT/scripts/mb-sdd-self-check.sh"
  TMPDIR="$(mktemp -d)"
  SPECS="$TMPDIR/specs"
  ROOT="$TMPDIR/root"
  mkdir -p "$SPECS" "$ROOT/tests/sh"
  export LC_ALL=C
  DASH=$'\xe2\x80\x94'
  ORE='not ok [0-9]+ demo_persist'
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

# ── fixtures ────────────────────────────────────────────────────────────────

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

# mk1 <topic> <eval-cmd> <anchors> → a valid single-task (gated) triple.
mk1() {
  local dir="$SPECS/$1"
  mkdir -p "$dir"
  _reqs "$dir"
  cat >"$dir/tasks.md" <<EOF
# Tasks: demo

<!-- mb-task:1 -->
## Task 1: persist work items

**Covers:** REQ-001
**Role:** backend
**Eval:** $2 ${DASH} red: demo assertion fails$3

**What to do:**
- persist to disk.

**Testing (TDD — tests BEFORE implementation):**
- round-trip test.

**DoD:**
- [ ] persist works.
<!-- /mb-task:1 -->
EOF
  cat >"$dir/design.md" <<EOF
# Design: demo

## Contract

**Seams:**
- the persistence boundary

## Eval declarations

- **T1** ${DASH} persist work items:
  **Eval:** $2 ${DASH} red: demo assertion fails$3
EOF
  printf '%s\n' "$dir"
}

# mk_waiver <topic> → gated task 1 (absent target) + non-gated task 2 with a waiver.
mk_waiver() {
  local dir; dir="$(mk1 "$1" 'bash tests/sh/absent.sh' "; exit: 1; output~: $ORE")"
  cat >>"$dir/tasks.md" <<EOF

<!-- mb-task:2 -->
## Task 2: docs only

**Covers:** REQ-100
**Role:** developer
**Scope:** docs/**
**Eval:** none ${DASH} waiver: pure documentation, no runtime surface

**Testing:** none needed.

**DoD:**
- [ ] docs updated.
<!-- /mb-task:2 -->
EOF
  # No **T2** entry in design §Eval declarations on purpose: a waived task
  # declares no Eval, and the CPR-D byte-identity gate rejects a design line
  # whose task has none — the validator is right, the fixture must match it.
  printf '%s\n' "$dir"
}

mk_red_target()   { printf '#!/usr/bin/env bash\necho "not ok 1 demo_persist"\nexit 1\n' >"$ROOT/$1"; chmod +x "$ROOT/$1"; }
mk_green_target() { printf '#!/usr/bin/env bash\necho "ok 1 demo_persist"\nexit 0\n'      >"$ROOT/$1"; chmod +x "$ROOT/$1"; }

_run() { run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" "$@"; }

# ── the phase exists, and the verdict cannot be read without it ─────────────

@test "self_check_phase: the verdict line names the phase it was reached in" {
  # A bare `self_check=invalid` is unreadable: red-is-required and green-is-
  # required produce the same word for opposite facts.
  local dir; dir="$(mk1 demo 'bash tests/sh/red.sh' "; exit: 1; output~: $ORE")"
  mk_red_target tests/sh/red.sh
  _run --spec "$dir"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "self_check=ready phase=generation" ] \
    || { echo "verdict line does not carry the phase: ${lines[0]}"; false; }
}

@test "self_check_phase: the default phase is named in --help/usage text" {
  # A default nobody can see is a default nobody can audit.
  assert_grep -qE 'phase.*(generation|done)' "$SELFCHECK"
  assert_grep -qE 'default.*generation|generation.*default' "$SELFCHECK" \
    || { echo "the script does not document its default phase"; false; }
}

@test "self_check_phase: an unknown phase is a usage error, not a silent default" {
  local dir; dir="$(mk1 demo 'bash tests/sh/red.sh' "; exit: 1; output~: $ORE")"
  mk_red_target tests/sh/red.sh
  _run --spec "$dir" --phase bogus
  [ "$status" -eq 2 ] || { echo "unknown phase accepted (rc=$status)"; false; }
}

# ── phase=done: green is what passes ────────────────────────────────────────

@test "self_check_phase: [AGR-037] an implemented (green) Eval passes phase=done" {
  # The defect this closes: with the code written, this same fixture is
  # `invalid` in the only phase that used to exist.
  local dir; dir="$(mk1 demo 'bash tests/sh/e.sh' "; exit: 1; output~: $ORE")"
  mk_green_target tests/sh/e.sh
  _run --spec "$dir" --phase done
  [ "$status" -eq 0 ] || { echo "green Eval rejected in phase=done (rc=$status): $output"; false; }
  [ "${lines[0]}" = "self_check=ready phase=done" ]
  assert_substring "$output" "eval.1=ready"
}

@test "self_check_phase: [AGR-037] a still-red Eval FAILS phase=done with a reason" {
  local dir; dir="$(mk1 demo 'bash tests/sh/e.sh' "; exit: 1; output~: $ORE")"
  mk_red_target tests/sh/e.sh
  _run --spec "$dir" --phase done
  [ "$status" -eq 1 ]
  assert_substring "$output" "eval.1=invalid"
  assert_substring "$output" "eval.1.reason=not_green"
}

@test "self_check_phase: [AGR-037] a missing target in phase=done is a FAILURE, never pending" {
  # After implementation "the target does not exist yet" is not an honest
  # state — it is a task that never materialised its own contract.
  local dir; dir="$(mk1 demo 'bash tests/sh/absent.sh' "; exit: 1; output~: $ORE")"
  _run --spec "$dir" --phase done
  [ "$status" -eq 1 ] || { echo "missing target passed phase=done (rc=$status)"; false; }
  assert_substring "$output" "eval.1=invalid"
  assert_substring "$output" "eval.1.reason=target_missing"
  refute_substring "$output" "pending_materialization" \
    || { echo "pending_materialization leaked into phase=done: $output"; false; }
}

# ── phase=generation keeps its old meaning ─────────────────────────────────

@test "self_check_phase: phase=generation still demands the declared red" {
  local dir; dir="$(mk1 demo 'bash tests/sh/e.sh' "; exit: 1; output~: $ORE")"
  mk_red_target tests/sh/e.sh
  _run --spec "$dir" --phase generation
  [ "$status" -eq 0 ]
  assert_substring "$output" "eval.1=ready"
}

@test "self_check_phase: phase=generation still rejects an already-green command" {
  local dir; dir="$(mk1 demo 'bash tests/sh/e.sh' "; exit: 1; output~: $ORE")"
  mk_green_target tests/sh/e.sh
  _run --spec "$dir" --phase generation
  [ "$status" -eq 1 ]
  assert_substring "$output" "eval.1=invalid"
  assert_substring "$output" "eval.1.reason=already_green"
}

@test "self_check_phase: phase=generation keeps pending_materialization honest" {
  local dir; dir="$(mk1 demo 'bash tests/sh/absent.sh' "; exit: 1; output~: $ORE")"
  _run --spec "$dir" --phase generation
  [ "$status" -eq 0 ]
  assert_substring "$output" "eval.1=pending_materialization"
  assert_substring "$output" "eval.1.reason=target_absent"
}

# ── I-172: every `invalid` says why ────────────────────────────────────────

@test "self_check_phase: [I-172] an anchor mismatch names itself" {
  local dir; dir="$(mk1 demo 'bash tests/sh/e.sh' "; exit: 1; output~: $ORE")"
  printf '#!/usr/bin/env bash\necho "boom"\nexit 1\n' >"$ROOT/tests/sh/e.sh"
  chmod +x "$ROOT/tests/sh/e.sh"
  _run --spec "$dir" --phase generation
  [ "$status" -eq 1 ]
  assert_substring "$output" "eval.1.reason=anchor_mismatch" \
    || { echo "no attributable reason for a foreign failure: $output"; false; }
}

@test "self_check_phase: [I-172] a declared 'exit: 0' names itself" {
  local dir; dir="$(mk1 demo 'bash tests/sh/e.sh' "; exit: 0; output~: $ORE")"
  mk_red_target tests/sh/e.sh
  _run --spec "$dir" --phase generation
  [ "$status" -eq 1 ]
  assert_substring "$output" "eval.1.reason=exit_zero_declared"
}

@test "self_check_phase: [I-172] every invalid line has a reason line, in BOTH phases" {
  # The class assertion: not "this one case explains itself" but "no invalid
  # is emitted bare". Nine bare `invalid`s is what made this necessary.
  local dir; dir="$(mk1 demo 'bash tests/sh/e.sh' "; exit: 1; output~: $ORE")"
  mk_green_target tests/sh/e.sh          # invalid in generation (already green)
  local phase
  for phase in generation done; do
    _run --spec "$dir" --phase "$phase"
    local id
    for id in $(printf '%s\n' "$output" | sed -n 's/^eval\.\([0-9]*\)=invalid$/\1/p'); do
      assert_substring "$output" "eval.$id.reason=" \
        || { echo "bare invalid without a reason (phase=$phase, task $id): $output"; false; }
    done
  done
  # …and the fixture really did produce an invalid in at least one phase,
  # so the loop above is not vacuously green.
  _run --spec "$dir" --phase generation
  assert_substring "$output" "eval.1=invalid"
}

# ── a waiver is not a pending materialisation ──────────────────────────────

@test "self_check_phase: a validated waiver is reported as such in both phases" {
  local dir; dir="$(mk_waiver demo)"
  local phase
  for phase in generation done; do
    _run --spec "$dir" --phase "$phase"
    assert_substring "$output" "eval.2=ready" \
      || { echo "waived task not reported ready (phase=$phase): $output $stderr"; false; }
    assert_substring "$output" "eval.2.reason=waived" \
      || { echo "waived task indistinguishable from a run (phase=$phase): $output"; false; }
  done
}
