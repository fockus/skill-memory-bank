#!/usr/bin/env bats

# Task 2 (svp-sdd-core) — C8 battery gates in mb-spec-validate.sh: seam
# rationale (C9), Blocked-by cycle (REQ-052), scenario parity + ASCII names
# (C8.2), role resolution (C8.3), cross-spec Blocked-by (C8.5), and the D-26
# legacy invariant. Eval/waiver/anchor/byte-identity/scope gates live in
# test_mb_spec_validate_v2.bats. Fixture helpers shared via
# lib/spec_validate_fixture.bash.

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
