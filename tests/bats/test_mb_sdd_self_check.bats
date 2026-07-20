#!/usr/bin/env bats
# self_check: — svp-sdd-core C8a deterministic battery executor
# (scripts/mb-sdd-self-check.sh, REQ-054).
#
# Name convention (X-05): every @test starts with `self_check: ` so the Eval
# red-anchor `not ok [0-9]+ self_check: ` is a positive named prefix — a run
# against a missing script yields a differently-named bats failure, never a
# false green.
#
# Each test builds a spec triple under $SPECS/<topic>/ that PASSES
# mb-spec-validate.sh (structural battery), then varies exactly one thing:
# either the behavioural Eval outcome (target present/absent, green/red, missing
# runner) or a single structural mutation (cycle / role / scenario markers).

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

# ── fixture helpers ──────────────────────────────────────────────────────────

_reqs() {  # $1 = spec dir
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

_tasks1() {  # $1 = spec dir, $2 = eval cmd, $3 = role
  cat >"$1/tasks.md" <<EOF
# Tasks: demo

<!-- mb-task:1 -->
## Task 1: persist work items

**Covers:** REQ-001
**Role:** $3
**Eval:** $2 ${DASH} red: demo assertion fails; exit: 1; output~: $ORE

**What to do:**
- persist to disk.

**Testing (TDD — tests BEFORE implementation):**
- round-trip test.

**DoD:**
- [ ] persist works.
<!-- /mb-task:1 -->
EOF
}

_design1() {  # $1 = spec dir, $2 = eval cmd
  cat >"$1/design.md" <<EOF
# Design: demo

## Contract

**Seams:**
- the persistence boundary

## Eval declarations

- **T1** ${DASH} persist work items:
  **Eval:** $2 ${DASH} red: demo assertion fails; exit: 1; output~: $ORE
EOF
}

# mk1 <topic> <eval-cmd> [role]  → prints spec dir; builds a valid single-task triple.
mk1() {
  local dir="$SPECS/$1"
  mkdir -p "$dir"
  _reqs "$dir"; _tasks1 "$dir" "$2" "${3:-backend}"; _design1 "$dir" "$2"
  printf '%s\n' "$dir"
}

# materialise a red-producing target script under the run root.
mk_red_target()   { printf '#!/usr/bin/env bash\necho "not ok 1 demo_persist"\nexit 1\n' >"$ROOT/$1"; chmod +x "$ROOT/$1"; }
mk_green_target() { printf '#!/usr/bin/env bash\necho "ok 1 demo_persist"\nexit 0\n'      >"$ROOT/$1"; chmod +x "$ROOT/$1"; }

# ── behavioural Eval preflight (C8.4) ────────────────────────────────────────

@test "self_check: target exists and produces the declared red → ready, exit 0" {
  local dir; dir="$(mk1 demo 'bash tests/sh/red.sh')"
  mk_red_target tests/sh/red.sh
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "self_check=ready" ]
  [[ "$output" == *"eval.1=ready"* ]]
}

@test "self_check: existing green target with a SPACE in its path → invalid, not pending (major #12)" {
  # shell-aware tokenisation: a quoted target path with a space really exists and
  # runs green — must be caught as invalid, never mis-read as missing.
  mkdir -p "$ROOT/tests/with space"
  local dir; dir="$(mk1 demo 'bash "tests/with space/green.sh"')"
  printf '#!/usr/bin/env bash\necho "ok"\nexit 0\n' > "$ROOT/tests/with space/green.sh"
  chmod +x "$ROOT/tests/with space/green.sh"
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "self_check=invalid" ]
  [[ "$output" == *"eval.1=invalid"* ]]
}

@test "self_check: target absent → pending_materialization, self_check stays ready, exit 0" {
  local dir; dir="$(mk1 demo 'bash tests/sh/red.sh')"
  # do NOT create the target
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "self_check=ready" ]
  [[ "$output" == *"eval.1=pending_materialization"* ]]
}

@test "self_check: target exists but command is already green → invalid, exit 1" {
  local dir; dir="$(mk1 demo 'bash tests/sh/red.sh')"
  mk_green_target tests/sh/red.sh
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "self_check=invalid" ]
  [[ "$output" == *"eval.1=invalid"* ]]
}

@test "self_check: A/B behavioural rule — absent target no red, real matched red → ready" {
  # (A) absent → not observed red
  local dir; dir="$(mk1 abs 'bash tests/sh/red.sh')"
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [[ "$output" == *"eval.1=pending_materialization"* ]]
  # (B) present + declared red → ready
  mk_red_target tests/sh/red.sh
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [[ "$output" == *"eval.1=ready"* ]]
}

# ── structural delegation to mb-spec-validate.sh (C8.1–C8.3, C8.5) ───────────

@test "self_check: Blocked-by self-cycle → structural violation, exit 1" {
  local dir; dir="$(mk1 demo 'bash tests/sh/red.sh')"
  mk_red_target tests/sh/red.sh   # behaviourally ready, but a cycle must still fail
  # inject a self-cycle on task 1
  perl -0pi -e 's/(\*\*Role:\*\* backend\n)/$1**Blocked-by:** 1\n/' "$dir/tasks.md" 2>/dev/null \
    || sed -i.bak 's/^\*\*Role:\*\* backend$/&\n**Blocked-by:** 1/' "$dir/tasks.md"
  rm -f "$dir/tasks.md.bak"
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "self_check=invalid" ]
}

@test "self_check: prefixed Role (mb-backend) → role collision, exit 1" {
  local dir; dir="$(mk1 demo 'bash tests/sh/red.sh' 'mb-backend')"
  mk_red_target tests/sh/red.sh
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "self_check=invalid" ]
}

@test "self_check: markerless scenario header → parity violation, exit 1" {
  local dir; dir="$(mk1 demo 'bash tests/sh/red.sh')"
  mk_red_target tests/sh/red.sh
  # add a second Scenario header WITHOUT mb-scenario markers → header/block parity break
  cat >>"$dir/requirements.md" <<'EOF'

### Scenario: unmarked extra
**Covers:** REQ-001
- GIVEN x
- WHEN y
- THEN z
EOF
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 1 ]
}

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
  [ "${lines[0]}" = "self_check=ready" ]
  [ "${lines[1]}" = "eval.1=pending_materialization" ]
  [ "${lines[2]}" = "eval.2=pending_materialization" ]
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
  [ "${lines[0]}" = "self_check=invalid" ]
  [ "${lines[1]}" = "eval.1=pending_materialization" ]
  [ "${lines[2]}" = "eval.2=invalid" ]
  [ "${lines[3]}" = "eval.3=ready" ]
}

@test "self_check: unresolvable topic → exit 2" {
  run --separate-stderr "$SELFCHECK" --spec no-such-topic --mb "$TMPDIR/nobank"
  [ "$status" -eq 2 ]
}

@test "self_check: missing --spec argument → usage exit 2" {
  run --separate-stderr "$SELFCHECK"
  [ "$status" -eq 2 ]
}

@test "self_check: shellcheck (style) clean" {
  if ! command -v shellcheck >/dev/null 2>&1; then skip "shellcheck not installed"; fi
  run shellcheck -S style "$SELFCHECK"
  [ "$status" -eq 0 ]
}
