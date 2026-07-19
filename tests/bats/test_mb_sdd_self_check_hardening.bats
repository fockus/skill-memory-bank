#!/usr/bin/env bats
# self_check: — round-1 S2 review hardening cases for the C8a battery executor
# (scripts/mb-sdd-self-check.sh), split out of test_mb_sdd_self_check.bats,
# which had grown to 489 lines — over the 400-line zone limit that
# tests/pytest/test_s2_file_size_contract.py now enforces for zone tests too
# (round-2 review [21]).
#
# Name convention (X-05) is preserved: every @test still starts with
# `self_check: `, so the Eval red-anchor `not ok [0-9]+ self_check: ` keeps
# matching across both files.

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

# ── S2 review hardening: [8] [9] [10] [21] ───────────────────────────────────

# mk1_noexit <topic> <eval-cmd> — a triple whose Eval declares output~ but NO exit:.
mk1_noexit() {
  local dir="$SPECS/$1"
  mkdir -p "$dir"
  _reqs "$dir"
  sed "s#; exit: 1;#;#" /dev/null 2>/dev/null || true
  cat >"$dir/tasks.md" <<EOF
# Tasks: demo

<!-- mb-task:1 -->
## Task 1: persist work items

**Covers:** REQ-001
**Role:** backend
**Eval:** $2 ${DASH} red: demo assertion fails; output~: $ORE

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
  **Eval:** $2 ${DASH} red: demo assertion fails; output~: $ORE
EOF
  printf '%s\n' "$dir"
}

@test "self_check: an output-only Eval (no exit:) is evaluated, not mangled by field parsing (review [10])" {
  local dir; dir="$(mk1_noexit demo 'bash tests/sh/red.sh')"
  mk_red_target tests/sh/red.sh
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; echo "$stderr"; false; }
  [[ "$output" == *"eval.1=ready"* ]]
}

@test "self_check: an output~: ERE starting with '-' is accepted like the validator does (review [21])" {
  ORE='-FAIL demo_persist'
  local dir; dir="$(mk1 demo 'bash tests/sh/red.sh')"
  printf '#!/usr/bin/env bash\necho "-FAIL demo_persist"\nexit 1\n' >"$ROOT/tests/sh/red.sh"
  chmod +x "$ROOT/tests/sh/red.sh"
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; echo "$stderr"; false; }
  [[ "$output" == *"eval.1=ready"* ]]
}

@test "self_check: a non-adjacent (global) bank resolves the real checkout (review [9])" {
  local gbank="$TMPDIR/global-bank"
  mkdir -p "$gbank/specs"
  ( cd "$ROOT" && git init -q . && git config user.email t@t && git config user.name t )
  SPECS="$gbank/specs" mk1 demo 'bash tests/sh/red.sh' >/dev/null
  mk_red_target tests/sh/red.sh
  cd "$ROOT" || return 1
  # No MB_REPO_ROOT override: the helper must find the checkout itself.
  run --separate-stderr "$SELFCHECK" --spec "$gbank/specs/demo" --mb "$gbank"
  [ "$status" -eq 0 ] || { echo "$output"; echo "$stderr"; false; }
  [[ "$output" == *"eval.1=ready"* ]]
}

@test "self_check: a gated spec with zero GWT scenarios is invalid (review [8], REQ-006)" {
  local dir; dir="$(mk1 demo 'bash tests/sh/red.sh')"
  mk_red_target tests/sh/red.sh
  # strip the whole Scenarios section — REQ-001 keeps its SHALL modal.
  python3 - "$dir" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / "requirements.md"
txt = p.read_text(encoding="utf-8")
p.write_text(txt.split("## Scenarios")[0], encoding="utf-8")
PY
  run --separate-stderr env MB_REPO_ROOT="$ROOT" "$SELFCHECK" --spec "$dir"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "self_check=invalid" ]
}
