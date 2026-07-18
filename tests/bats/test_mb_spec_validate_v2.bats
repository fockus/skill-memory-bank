#!/usr/bin/env bats

# Task 2 (svp-sdd-core) — v2 / C8 gates in mb-spec-validate.sh.
#
# Each test builds a spec triple under $SPECS/<topic>/ and runs the validator on
# the directory. The baseline triple is fully valid (has_eval → gates active);
# every negative test mutates exactly ONE thing so the failure is attributable.
# Legacy specs (no **Eval:** fields) must gain ZERO new violations (D-26).

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

# ── fixture helpers ──────────────────────────────────────────────────────────

DASH=$'—'  # em-dash used by the Eval grammar

write_req() {
  # $1 = spec dir
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

write_tasks() {
  # $1 = spec dir
  cat >"$1/tasks.md" <<EOF
# Tasks: demo

<!-- mb-task:1 -->
## Task 1: persist work items

**Covers:** REQ-001
**Role:** backend
**Eval:** bats tests/bats/test_demo.bats ${DASH} red: demo assertion fails; exit: 1; output~: not ok [0-9]+ demo_persist

**What to do:**
- persist to disk.

**Testing (TDD — tests BEFORE implementation):**
- round-trip test.

**DoD:**
- [ ] persist works.
<!-- /mb-task:1 -->
EOF
}

write_design() {
  # $1 = spec dir
  cat >"$1/design.md" <<EOF
# Design: demo

## Contract

**Seams:**
- the persistence boundary

## Eval declarations

- **T1** ${DASH} persist work items:
  **Eval:** \`bats tests/bats/test_demo.bats\` ${DASH} red: demo assertion fails; exit: 1; output~: \`not ok [0-9]+ demo_persist\`
EOF
}

mkbase() {
  # $1 = topic → returns spec dir on stdout
  local dir="$SPECS/$1"
  mkdir -p "$dir"
  write_req "$dir"; write_tasks "$dir"; write_design "$dir"
  printf '%s\n' "$dir"
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
  sed -i.bak "s#output~: not ok \[0-9\]+ demo_persist#output~: not ok [0-9+ demo_persist#" "$dir/tasks.md" && rm -f "$dir/tasks.md.bak"
  # keep design byte-identity aligned so only the ERE gate fires
  sed -i.bak "s#output~: \`not ok \[0-9\]+ demo_persist\`#output~: \`not ok [0-9+ demo_persist\`#" "$dir/design.md" && rm -f "$dir/design.md.bak"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "ERE\|output~\|regex"
}

# ── REQ-051 seam rationale (C9) ──────────────────────────────────────────────

@test "seam_rationale: two seams without a rationale fail" {
  dir="$(mkbase demo)"
  cat >"$dir/design.md" <<EOF
# Design: demo

## Contract

**Seams:**
- the persistence boundary
- the checklist boundary

## Eval declarations

- **T1** ${DASH} persist work items:
  **Eval:** \`bats tests/bats/test_demo.bats\` ${DASH} red: demo assertion fails; exit: 1; output~: \`not ok [0-9]+ demo_persist\`
EOF
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "REQ-051\|seam"
}

@test "seam_rationale: two seams WITH a rationale pass" {
  dir="$(mkbase demo)"
  cat >"$dir/design.md" <<EOF
# Design: demo

## Contract

**Seams:**
- the persistence boundary
- the checklist boundary
**Seam rationale:** two independent boundaries cannot be collapsed

## Eval declarations

- **T1** ${DASH} persist work items:
  **Eval:** \`bats tests/bats/test_demo.bats\` ${DASH} red: demo assertion fails; exit: 1; output~: \`not ok [0-9]+ demo_persist\`
EOF
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "seam_rationale: a single seam without a rationale passes" {
  dir="$(mkbase demo)"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# ── REQ-052 Blocked-by cycle ─────────────────────────────────────────────────

@test "blocked_by_cycle: a self-cycle fails with the ordered path" {
  dir="$(mkbase demo)"
  sed -i.bak "s#^\*\*Covers:\*\* REQ-001#**Covers:** REQ-001\n**Blocked-by:** 1#" "$dir/tasks.md" && rm -f "$dir/tasks.md.bak"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "1 -> 1"
}

@test "blocked_by_cycle: a two-node cycle prints the full path" {
  dir="$SPECS/cyc"
  mkdir -p "$dir"; write_design "$dir"
  cat >"$dir/requirements.md" <<EOF
# Requirements: cyc

## Requirements (EARS)

- **REQ-001** (ubiquitous): The system shall persist work items to disk.
- **REQ-002** (event-driven): When a stage completes, the system shall update the checklist.
EOF
  cat >"$dir/tasks.md" <<EOF
# Tasks: cyc

<!-- mb-task:2 -->
## Task 2: alpha

**Covers:** REQ-001
**Role:** backend
**Blocked-by:** 3
**Eval:** bats tests/bats/test_demo.bats ${DASH} red: fails; exit: 1; output~: not ok [0-9]+ demo_persist

**Testing:** t.

**DoD:**
- [ ] a.
<!-- /mb-task:2 -->
<!-- mb-task:3 -->
## Task 3: beta

**Covers:** REQ-002
**Role:** backend
**Blocked-by:** 2
**Eval:** bats tests/bats/test_demo2.bats ${DASH} red: fails; exit: 1; output~: not ok [0-9]+ demo_check

**Testing:** t.

**DoD:**
- [ ] b.
<!-- /mb-task:3 -->
EOF
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "2 -> 3 -> 2"
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

# ── C8.2 scenario parity + ASCII names ───────────────────────────────────────

@test "scenario_markerless: a heading without a marker fails parity" {
  dir="$(mkbase demo)"
  cat >>"$dir/requirements.md" <<EOF

### Scenario: unmarked extra
**Covers:** REQ-001

- GIVEN x
- WHEN y
- THEN z
EOF
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "parity\|scenario"
}

@test "scenario_cyrillic: a non-ASCII scenario name fails" {
  dir="$(mkbase demo)"
  # replace the ASCII scenario name with a Cyrillic one
  python3 - "$dir/requirements.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text(encoding="utf-8").replace("persist round trip", "сохранение туда-обратно"), encoding="utf-8")
PY
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "ASCII\|scenario"
}

# ── C8.3 role resolution ─────────────────────────────────────────────────────

@test "role_prefix: an mb-prefixed Role is rejected with a bare hint" {
  dir="$(mkbase demo)"
  sed -i.bak "s#^\*\*Role:\*\* backend#**Role:** mb-backend#" "$dir/tasks.md" && rm -f "$dir/tasks.md.bak"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "role\|bare"
}

# ── C8.5 cross-spec Blocked-by resolution ────────────────────────────────────

@test "xspec_unknown: an unresolvable cross-spec Blocked-by fails" {
  dir="$(mkbase demo)"
  sed -i.bak "s@^\*\*Covers:\*\* REQ-001@**Covers:** REQ-001\n**Blocked-by:** ghost-topic#9@" "$dir/tasks.md" && rm -f "$dir/tasks.md.bak"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "blocked-by\|ghost-topic\|resolve"
}

# ── D-26 legacy invariant ────────────────────────────────────────────────────

@test "legacy_no_new_errors: a legacy spec without Eval/Seams stays clean" {
  dir="$SPECS/legacy"
  mkdir -p "$dir"
  write_req "$dir"
  cat >"$dir/design.md" <<EOF
# Design: legacy
EOF
  cat >"$dir/tasks.md" <<EOF
# Tasks: legacy

<!-- mb-task:1 -->
## Task 1: legacy

**Covers:** REQ-001
**Role:** developer

**Testing:** unit test.

**DoD:**
- [ ] done.
<!-- /mb-task:1 -->
EOF
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
