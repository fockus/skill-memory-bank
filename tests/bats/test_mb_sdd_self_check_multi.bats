#!/usr/bin/env bats
# self_check: — MULTI-TASK fixtures of the C8a battery (scripts/mb-sdd-self-check.sh).
#
# Split out of test_mb_sdd_self_check.bats, which crossed the S2 zone's 400-line
# contract (AGR-035) when the phase/reason work landed. The cut is at a seam,
# not at the line number: everything here builds a triple with SEVERAL tasks and
# asserts what only several tasks can show — ascending task-id ORDER of the eval
# lines, and one fixture carrying all three verdicts at once (§20). The base
# file keeps the single-task behavioural and structural cases.
#
# Name convention (X-05) is shared with the base file: every @test starts with
# `self_check: `, so the declared red anchor of Task 9 matches both files.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SELFCHECK="$REPO_ROOT/scripts/mb-sdd-self-check.sh"
  TMPDIR="$(mktemp -d)"
  SPECS="$TMPDIR/specs"
  ROOT="$TMPDIR/root"           # behavioural run root (Eval targets live here)
  mkdir -p "$SPECS" "$ROOT/tests/sh"
  export LC_ALL=C
  DASH=$'\xe2\x80\x94'          # em dash used by the Eval grammar
  ORE='not ok [0-9]+ demo_persist'
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

# Target builders (the only fixture helpers these multi-task cases need — each
# builds its own triple inline, since the point of the fixtures is that they are
# NOT the single-task shape the base file's mk1 produces).
mk_red_target()   { printf '#!/usr/bin/env bash\necho "not ok 1 demo_persist"\nexit 1\n' >"$ROOT/$1"; chmod +x "$ROOT/$1"; }
mk_green_target() { printf '#!/usr/bin/env bash\necho "ok 1 demo_persist"\nexit 0\n'      >"$ROOT/$1"; chmod +x "$ROOT/$1"; }

# ── ordering + resolver ──────────────────────────────────────────────────────

@test "self_check: eval lines are emitted in ascending task-id order" {
  local dir="$SPECS/order"; mkdir -p "$dir"
  cat >"$dir/requirements.md" <<EOF
# Requirements: order

## Requirements (EARS)

- **REQ-001** (ubiquitous): The system shall A.
- **REQ-002** (ubiquitous): The system shall B.

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: a
**Covers:** REQ-001
- GIVEN a
- WHEN a
- THEN a
<!-- /mb-scenario:1 -->
<!-- mb-scenario:2 -->
### Scenario: b
**Covers:** REQ-002
- GIVEN b
- WHEN b
- THEN b
<!-- /mb-scenario:2 -->
EOF
  # author task 2 BEFORE task 1 in file order → the helper must still sort by id.
  cat >"$dir/tasks.md" <<EOF
# Tasks: order

<!-- mb-task:2 -->
## Task 2: B
**Covers:** REQ-002
**Role:** backend
**Eval:** bash tests/sh/b.sh ${DASH} red: b fails; exit: 1; output~: $ORE

**Testing:** t.

**DoD:**
- [ ] b.
<!-- /mb-task:2 -->
<!-- mb-task:1 -->
## Task 1: A
**Covers:** REQ-001
**Role:** backend
**Eval:** bash tests/sh/a.sh ${DASH} red: a fails; exit: 1; output~: $ORE

**Testing:** t.

**DoD:**
- [ ] a.
<!-- /mb-task:1 -->
EOF
  cat >"$dir/design.md" <<EOF
# Design: order

## Contract

**Seams:**
- the seam

## Eval declarations

- **T1** ${DASH} A:
  **Eval:** bash tests/sh/a.sh ${DASH} red: a fails; exit: 1; output~: $ORE
- **T2** ${DASH} B:
  **Eval:** bash tests/sh/b.sh ${DASH} red: b fails; exit: 1; output~: $ORE
EOF
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "self_check=ready phase=generation" ]
  # Reason lines (I-172) now interleave with the status lines, so the ORDER is
  # pinned on the sequence of status lines rather than on absolute indices — an
  # index assertion would have been re-satisfied by any accidental reshuffle
  # that happened to keep the count.
  local order
  order="$(printf '%s\n' "$output" | sed -n 's/^\(eval\.[0-9]*\)=.*/\1/p' | tr '\n' ' ')"
  [ "$order" = "eval.1 eval.2 " ] || { echo "eval lines out of ascending order: $order"; false; }
  [[ "$output" == *"eval.1=pending_materialization"* ]]
  [[ "$output" == *"eval.2=pending_materialization"* ]]
}

@test "self_check: three-task fixture (§20) — pending, invalid(green), ready(red)" {
  local dir="$SPECS/s20"; mkdir -p "$dir"
  cat >"$dir/requirements.md" <<EOF
# Requirements: s20

## Requirements (EARS)

- **REQ-001** (ubiquitous): The system shall A.
- **REQ-002** (ubiquitous): The system shall B.
- **REQ-003** (ubiquitous): The system shall C.

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: a
**Covers:** REQ-001
- GIVEN a
- WHEN a
- THEN a
<!-- /mb-scenario:1 -->
<!-- mb-scenario:2 -->
### Scenario: b
**Covers:** REQ-002
- GIVEN b
- WHEN b
- THEN b
<!-- /mb-scenario:2 -->
<!-- mb-scenario:3 -->
### Scenario: c
**Covers:** REQ-003
- GIVEN c
- WHEN c
- THEN c
<!-- /mb-scenario:3 -->
EOF
  cat >"$dir/tasks.md" <<EOF
# Tasks: s20

<!-- mb-task:1 -->
## Task 1: A (absent target)
**Covers:** REQ-001
**Role:** backend
**Eval:** bash tests/sh/absent.sh ${DASH} red: a fails; exit: 1; output~: $ORE

**Testing:** t.

**DoD:**
- [ ] a.
<!-- /mb-task:1 -->
<!-- mb-task:2 -->
## Task 2: B (green)
**Covers:** REQ-002
**Role:** backend
**Eval:** bash tests/sh/green.sh ${DASH} red: b fails; exit: 1; output~: $ORE

**Testing:** t.

**DoD:**
- [ ] b.
<!-- /mb-task:2 -->
<!-- mb-task:3 -->
## Task 3: C (red)
**Covers:** REQ-003
**Role:** backend
**Eval:** bash tests/sh/red.sh ${DASH} red: c fails; exit: 1; output~: $ORE

**Testing:** t.

**DoD:**
- [ ] c.
<!-- /mb-task:3 -->
EOF
  cat >"$dir/design.md" <<EOF
# Design: s20

## Contract

**Seams:**
- the seam

## Eval declarations

- **T1** ${DASH} A:
  **Eval:** bash tests/sh/absent.sh ${DASH} red: a fails; exit: 1; output~: $ORE
- **T2** ${DASH} B:
  **Eval:** bash tests/sh/green.sh ${DASH} red: b fails; exit: 1; output~: $ORE
- **T3** ${DASH} C:
  **Eval:** bash tests/sh/red.sh ${DASH} red: c fails; exit: 1; output~: $ORE
EOF
  mk_green_target tests/sh/green.sh
  mk_red_target tests/sh/red.sh
  # absent.sh intentionally NOT created
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "self_check=invalid phase=generation" ]
  # Status lines only (reason lines interleave since I-172); the §20 fixture
  # pins one of each verdict, in id order.
  local seq
  seq="$(printf '%s\n' "$output" | grep -E '^eval\.[0-9]+=' | tr '\n' '|')"
  [ "$seq" = "eval.1=pending_materialization|eval.2=invalid|eval.3=ready|" ] \
    || { echo "unexpected verdict sequence: $seq"; false; }
  # …and each invalid says why (I-172).
  [[ "$output" == *"eval.2.reason=already_green"* ]]
}
