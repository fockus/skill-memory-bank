#!/usr/bin/env bats
# test_mb_sdd_self_check_r3.bats — svp-sdd-core round-3 review [5] and [6],
# split out of test_mb_sdd_self_check.bats to keep every zone file within the
# 400-line contract (the same reason the _hardening and _r2 suites exist).
#
# [5] the normative C8 `tool_unavailable` reason must actually be emitted, and
#     must not be borrowed by an unrelated `invalid`.
# [6] a repo-relative Eval target exists only under RUN_ROOT, never in the cwd
#     the caller happens to be standing in.

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

@test "self_check: existing target but missing runner tool → invalid tool_unavailable, never ready, exit 1" {
  # r3 review [5]: this asserted only `invalid`, so it passed while the
  # normative C8 reason `tool_unavailable` was not emitted at all. `invalid` has
  # several causes; the test must pin the one it is named after.
  local dir; dir="$(mk1 demo 'madeuptool_xyz tests/sh/red.sh')"
  mk_red_target tests/sh/red.sh   # target exists, runner does not
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"eval.1=invalid"* ]]
  [[ "$output" != *"eval.1=ready"* ]]
  [[ "$output" == *"eval.1.reason=tool_unavailable"* ]] \
    || { echo "no tool_unavailable reason emitted: $output"; false; }
}

@test "self_check: a NON-tool invalid does not claim tool_unavailable" {
  # The reason must be attributable: an already-green command is invalid for a
  # different reason, and must not borrow this one.
  local dir; dir="$(mk1 demo 'bash tests/sh/green.sh')"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$ROOT/tests/sh/green.sh"
  chmod +x "$ROOT/tests/sh/green.sh"
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [[ "$output" == *"eval.1=invalid"* ]]
  [[ "$output" != *"tool_unavailable"* ]] \
    || { echo "unrelated invalid claimed tool_unavailable: $output"; false; }
}

# ─── r3 review [6]: targets resolve under RUN_ROOT, never the caller cwd ────

@test "self_check: a same-named file in the CALLER cwd does not materialise the target" {
  # `os.path.exists(t)` treated a target as present when an identically named
  # path existed in the caller's cwd, flipping pending_materialization into a
  # RUN — and then into `invalid` — for a target that does not exist under the
  # run root the command is actually executed from.
  local dir; dir="$(mk1 demo 'bash tests/sh/ghost.sh')"
  local cwd="$TMPDIR/cwd"; mkdir -p "$cwd/tests/sh"
  printf '#!/usr/bin/env bash
exit 1
' > "$cwd/tests/sh/ghost.sh"
  chmod +x "$cwd/tests/sh/ghost.sh"
  # target absent under $ROOT, present under the cwd we run from
  run --separate-stderr env MB_REPO_ROOT="$ROOT" bash -c "cd '$cwd' && '$SELFCHECK' --spec '$dir'"
  [[ "$output" == *"eval.1=pending_materialization"* ]] \
    || { echo "cwd file materialised an absent target: $output"; false; }
}

