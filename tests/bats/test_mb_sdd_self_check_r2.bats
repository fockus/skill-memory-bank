#!/usr/bin/env bats
# self_check_r2: — svp-sdd-core round-2 review findings on the C8a battery
# executor (scripts/mb-sdd-self-check.sh).
#
# Split from test_mb_sdd_self_check.bats, which was already over the 400-line
# zone limit (review [21]).
#
#   [6]  an output-only Eval exiting 0 was recorded as a genuine red
#   [16] a leading `NAME=value` env assignment was mistaken for the runner
#   [15] a registered GLOBAL bank was treated as local, so RUN_ROOT pointed at
#        the agent-config parent instead of the checkout
#
# Name convention (X-05): every @test starts with `self_check_r2: `.

bats_require_minimum_version 1.5.0

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

# _tasks1 <dir> <eval-cmd> <role> [anchors]
# `anchors` defaults to the full `exit: 1; output~: ORE` pair; pass a bare
# `output~:` clause to build the output-only declaration finding [6] is about.
_tasks1() {
  local anchors="${4:-exit: 1; output~: $ORE}"
  cat >"$1/tasks.md" <<EOF
# Tasks: demo

<!-- mb-task:1 -->
## Task 1: persist work items

**Covers:** REQ-001
**Role:** $3
**Eval:** $2 ${DASH} red: demo assertion fails; $anchors

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
  local anchors="${3:-exit: 1; output~: $ORE}"
  cat >"$1/design.md" <<EOF
# Design: demo

## Contract

**Seams:**
- the persistence boundary

## Eval declarations

- **T1** ${DASH} persist work items:
  **Eval:** $2 ${DASH} red: demo assertion fails; $anchors
EOF
}

mk1() {
  local dir="$SPECS/$1"
  mkdir -p "$dir"
  _reqs "$dir"; _tasks1 "$dir" "$2" "${3:-backend}" "${4:-}"; _design1 "$dir" "$2" "${4:-}"
  printf '%s\n' "$dir"
}

# ── [6] a red REQUIRES a non-zero exit ──────────────────────────────────────

@test "self_check_r2: [6] output-only Eval that exits 0 is NOT a red" {
  # The target prints the declared anchor but succeeds. Without an `exit:`
  # clause this used to be recorded eval.1=ready — i.e. a green command
  # impersonating a red.
  local dir; dir="$(mk1 demo 'bash tests/sh/fake.sh' backend "output~: $ORE")"
  printf '#!/usr/bin/env bash\necho "not ok 1 demo_persist"\nexit 0\n' >"$ROOT/tests/sh/fake.sh"
  chmod +x "$ROOT/tests/sh/fake.sh"
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [[ "$output" == *"eval.1=invalid"* ]]
  [ "$status" -ne 0 ]
}

@test "self_check_r2: [6] a genuine red (anchor + non-zero exit) is still ready" {
  local dir; dir="$(mk1 demo 'bash tests/sh/red.sh' backend "output~: $ORE")"
  printf '#!/usr/bin/env bash\necho "not ok 1 demo_persist"\nexit 1\n' >"$ROOT/tests/sh/red.sh"
  chmod +x "$ROOT/tests/sh/red.sh"
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [[ "$output" == *"eval.1=ready"* ]]
}

@test "self_check_r2: [6] an explicit 'exit: 0' declaration is rejected structurally" {
  # A red never exits 0, so the declaration itself is contradictory.
  local dir; dir="$(mk1 demo 'bash tests/sh/red.sh' backend "exit: 0; output~: $ORE")"
  printf '#!/usr/bin/env bash\necho "not ok 1 demo_persist"\nexit 0\n' >"$ROOT/tests/sh/red.sh"
  chmod +x "$ROOT/tests/sh/red.sh"
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [[ "$output" == *"eval.1=invalid"* ]]
  [ "$status" -ne 0 ]
}

# ── [16] a leading environment assignment is not the runner ─────────────────

@test "self_check_r2: [16] Eval with a leading NAME=value env assignment runs" {
  # `PYTHONPATH=src bash tests/sh/red.sh`: the runner is bash, not PYTHONPATH=src.
  local dir; dir="$(mk1 demo 'MB_DEMO=1 bash tests/sh/red.sh')"
  printf '#!/usr/bin/env bash\necho "not ok 1 demo_persist"\nexit 1\n' >"$ROOT/tests/sh/red.sh"
  chmod +x "$ROOT/tests/sh/red.sh"
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [[ "$output" == *"eval.1=ready"* ]]
}

@test "self_check_r2: [16] a genuinely missing runner is still invalid" {
  # Guards over-correction: skipping assignments must not skip a real bad tool.
  local dir; dir="$(mk1 demo 'MB_DEMO=1 definitely-not-a-real-tool tests/sh/red.sh')"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$ROOT/tests/sh/red.sh"
  chmod +x "$ROOT/tests/sh/red.sh"
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [[ "$output" == *"eval.1=invalid"* ]]
}
