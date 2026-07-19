#!/usr/bin/env bats

# Task 2 (svp-sdd-core) — v2 Eval / waiver / anchor / byte-identity / scope gates
# in mb-spec-validate.sh. Battery gates (seam/cycle/scenario/role/cross-spec/
# legacy) live in test_mb_spec_validate_v2_battery.bats. Fixture helpers are
# shared via lib/spec_validate_fixture.bash.

load 'lib/spec_validate_fixture'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  VALIDATE="$REPO_ROOT/scripts/mb-spec-validate.sh"
  TMPDIR="$(mktemp -d)"
  SPECS="$TMPDIR/specs"
  mkdir -p "$SPECS"
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

# ── baseline ─────────────────────────────────────────────────────────────────

@test "baseline: a well-formed v2 triple passes" {
  dir="$(mkbase demo)"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# ── REQ-007 / REQ-050 waiver ─────────────────────────────────────────────────

@test "eval_none_gated: Eval:none covering a gated req fails" {
  dir="$(mkbase demo)"
  sed -i.bak "s#^\*\*Eval:\*\*.*#**Eval:** none#" "$dir/tasks.md" && rm -f "$dir/tasks.md.bak"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "REQ-007\|Eval: none"
}

@test "eval_none_gated: waiver on a gated task is rejected" {
  dir="$(mkbase demo)"
  sed -i.bak "s#^\*\*Eval:\*\*.*#**Eval:** none ${DASH} waiver: covered elsewhere#" "$dir/tasks.md" && rm -f "$dir/tasks.md.bak"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
}

@test "waiver_empty_reason: none with an empty waiver reason fails" {
  dir="$(mkbase demo)"
  # non-gated docs task with an empty-reason waiver
  cat >>"$dir/tasks.md" <<EOF
<!-- mb-task:2 -->
## Task 2: docs only

**Covers:** REQ-100
**Role:** developer
**Eval:** none ${DASH} waiver:

**Testing:** none needed.

**DoD:**
- [ ] docs updated.
<!-- /mb-task:2 -->
EOF
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "REQ-050\|waiver"
}

@test "waiver_nongated: a non-gated waiver with a reason passes and is listed" {
  dir="$(mkbase demo)"
  cat >>"$dir/tasks.md" <<EOF
<!-- mb-task:2 -->
## Task 2: docs only

**Covers:** REQ-100
**Role:** developer
**Eval:** none ${DASH} waiver: pure documentation, no runtime surface

**Testing:** none needed.

**DoD:**
- [ ] docs updated.
<!-- /mb-task:2 -->
EOF
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -qi "waiver.*pure documentation\|pure documentation"
}

# ── REQ-055 output anchor ─────────────────────────────────────────────────────

@test "gated_no_output_anchor: a gated eval without output~: is rejected" {
  dir="$(mkbase demo)"
  sed -i.bak "s#^\*\*Eval:\*\*.*#**Eval:** bats tests/bats/test_demo.bats ${DASH} red: demo assertion fails; exit: 1#" "$dir/tasks.md" && rm -f "$dir/tasks.md.bak"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "REQ-055\|output~\|anchor"
}

@test "gated_bad_ere: a non-compiling output~: ERE is rejected" {
  dir="$(mkbase demo)"
  sed -i.bak "s#output~: \`not ok \[0-9\]+ demo_persist\`#output~: \`not ok [0-9+ demo_persist\`#" "$dir/tasks.md" && rm -f "$dir/tasks.md.bak"
  # keep design byte-identity aligned so only the ERE gate fires
  sed -i.bak "s#output~: \`not ok \[0-9\]+ demo_persist\`#output~: \`not ok [0-9+ demo_persist\`#" "$dir/design.md" && rm -f "$dir/design.md.bak"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "ERE\|output~\|regex"
}

@test "gated_lookahead_ere: a Python-only regex (?=...) rejected as non-POSIX ERE (major #11)" {
  # `(?=demo)` compiles under Python re but grep -E rejects it (exit 2). The
  # validator must use the SAME portable engine used at execution time.
  dir="$(mkbase demo)"
  sed -i.bak "s#output~: \`not ok \[0-9\]+ demo_persist\`#output~: \`(?=demo)\`#" "$dir/tasks.md" && rm -f "$dir/tasks.md.bak"
  sed -i.bak "s#output~: \`not ok \[0-9\]+ demo_persist\`#output~: \`(?=demo)\`#" "$dir/design.md" && rm -f "$dir/design.md.bak"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "ERE\|output~\|regex"
}

# ── Scope restricted-glob (R3-004) — parser propagates exit 2 ─────────────────

@test "scope_malformed: a forbidden metacharacter makes validation exit 2" {
  dir="$(mkbase demo)"
  sed -i.bak "s#^\*\*Role:\*\* backend#**Role:** backend\n**Scope:** src/?.py#" "$dir/tasks.md" && rm -f "$dir/tasks.md.bak"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 2 ]
}

@test "scope_valid: a restricted-glob scope passes" {
  dir="$(mkbase demo)"
  sed -i.bak "s#^\*\*Role:\*\* backend#**Role:** backend\n**Scope:** scripts/*.sh, tests/fixtures/**#" "$dir/tasks.md" && rm -f "$dir/tasks.md.bak"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# ── CPR-D Eval byte-identity design↔tasks ────────────────────────────────────

@test "byte_identity: a diverging design anchor (backslash-pipe vs pipe) fails" {
  dir="$(mkbase demo)"
  # design ERE uses an escaped pipe, tasks uses a bare pipe → normalized diverge
  cat >"$dir/design.md" <<EOF
# Design: demo

## Contract

**Seams:**
- the persistence boundary

## Eval declarations

- **T1** ${DASH} persist work items:
  **Eval:** \`bats tests/bats/test_demo.bats\` ${DASH} red: demo assertion fails; exit: 1; output~: \`not ok [0-9]+ demo_persist\|other\`
EOF
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "byte-identical\|design.*tasks\|CPR-D\|anchor"
}
