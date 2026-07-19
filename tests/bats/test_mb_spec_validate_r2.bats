#!/usr/bin/env bats
# svp-sdd-core round-2 review — fail-open holes in the v2 spec validators.
#
# Each test starts from the fully valid baseline triple (lib/spec_validate_fixture)
# and mutates exactly ONE thing, so a failure is attributable to the gate under
# test rather than to an unrelated missing section.
#
#   [1] removing every Eval line disabled the ENTIRE v2 gate set
#   [2] a SHALL wrapped onto the next line was not seen as gated
#   [4] a Seams block with zero entries satisfied REQ-051
#   [3] a docs-only product scope was masked as runtime by its test artifacts
#   [5] a transitively missing cross-spec dependency was silently skipped

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

# ── [1] Eval-less v2 artifact must still be gated ───────────────────────────

@test "r2 [1]: baseline is valid (guards the mutations below)" {
  dir="$(mkbase demo)"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "r2 [1]: dropping every Eval does not disable the v2 gates" {
  dir="$(mkbase demo)"
  # A v2 artifact is identified by its v2 fields, not by Eval alone. Mark this
  # task with Stage/Scope/Budget, strip every Eval, and remove the covering
  # scenario: the gated REQ-001 must still be reported. Previously exit 0.
  python3 - "$dir/tasks.md" <<'PY2'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("**Role:** backend",
              "**Role:** backend\n**Stage:** 1\n**Scope:** src/**\n**Budget:** 100000")
open(p, "w", encoding="utf-8").write(s)
PY2
  grep -v '^\*\*Eval:\*\*' "$dir/tasks.md" > "$dir/tasks.tmp" && mv "$dir/tasks.tmp" "$dir/tasks.md"
  grep -v '^\*\*Eval:\*\*' "$dir/design.md" > "$dir/design.tmp" && mv "$dir/design.tmp" "$dir/design.md"
  python3 - "$dir/requirements.md" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r"<!-- mb-scenario:1 -->.*?<!-- /mb-scenario:1 -->", "", s, flags=re.S)
open(p, "w", encoding="utf-8").write(s)
PY
  run bash "$VALIDATE" "$dir"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'REQ-006\|gated\|Eval'
}

@test "r2 [1]: a genuine legacy (pre-v2) spec is still accepted (D-26)" {
  # The fix must not turn legacy specs red. Legacy = no Eval AND no v2 fields;
  # this is the canonical D-26 fixture from the battery suite.
  dir="$SPECS/legacy"; mkdir -p "$dir"
  write_req "$dir"
  printf '# Design: legacy\n' >"$dir/design.md"
  cat >"$dir/tasks.md" <<'EOF'
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

# ── [2] a wrapped SHALL is still a gated requirement ─────────────────────────

@test "r2 [2]: a SHALL continued on the next line still counts as gated" {
  dir="$(mkbase demo)"
  # Same requirement, wrapped across two physical lines, and its scenario
  # removed. The REQ is gated, so the missing GWT must be reported.
  cat >"$dir/requirements.md" <<'EOF'
# Requirements: demo

## Requirements (EARS)

- **REQ-001** (ubiquitous): The system
  shall persist work items to disk.

## Scenarios
EOF
  run bash "$VALIDATE" "$dir"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'REQ-006\|gated\|scenario'
}

@test "r2 [2]: a wrapped SHALL cannot be waived away with Eval:none" {
  dir="$(mkbase demo)"
  cat >"$dir/requirements.md" <<'EOF'
# Requirements: demo

## Requirements (EARS)

- **REQ-001** (ubiquitous): The system
  shall persist work items to disk.

## Scenarios
EOF
  python3 - "$dir/tasks.md" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r"^\*\*Eval:\*\*.*$", "**Eval:** none — waiver: nothing to run", s, flags=re.M)
open(p, "w", encoding="utf-8").write(s)
PY
  run bash "$VALIDATE" "$dir"
  [ "$status" -ne 0 ]
}

@test "r2 [2]: a wrapped SHALL with a covering scenario passes" {
  # The mirror of the negative case: seeing the wrapped modal must not make a
  # properly covered requirement fail. Guards over-tightening.
  dir="$(mkbase demo)"
  cat >"$dir/requirements.md" <<'EOF'
# Requirements: demo

## Requirements (EARS)

- **REQ-001** (ubiquitous): The system
  shall persist work items to disk.

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: persist round trip
**Covers:** REQ-001

- GIVEN a work item
- WHEN it is persisted
- THEN it round-trips
<!-- /mb-scenario:1 -->
EOF
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# ── [4] an empty Seams block is not a seam ──────────────────────────────────

@test "r2 [4]: a Seams block with zero entries is rejected" {
  dir="$(mkbase demo)"
  python3 - "$dir/design.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("**Seams:**\n- the persistence boundary\n", "**Seams:**\n")
open(p, "w", encoding="utf-8").write(s)
PY
  run bash "$VALIDATE" "$dir"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'REQ-051\|seam'
}

@test "r2 [4]: two seams still require a rationale (no regression)" {
  dir="$(mkbase demo)"
  python3 - "$dir/design.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("- the persistence boundary\n",
              "- the persistence boundary\n- the checklist boundary\n")
open(p, "w", encoding="utf-8").write(s)
PY
  run bash "$VALIDATE" "$dir"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'REQ-051\|seam\|rationale'
}

# ── [3] test artifacts must not mask a docs-only product scope ──────────────

@test "r2 [3]: docs-only product scope plus a test artifact still needs structural Eval" {
  dir="$(mkbase demo)"
  # Product surface is documentation-only; the .bats file is the Eval's own
  # artifact, not product. REQ-049 must still demand a structural Eval.
  python3 - "$dir/tasks.md" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("**Role:** backend",
              "**Role:** backend\n**Scope:** docs/**, tests/bats/test_demo.bats")
open(p, "w", encoding="utf-8").write(s)
PY
  run bash "$VALIDATE" "$dir"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'REQ-049\|structural'
}

@test "r2 [3]: a genuine runtime scope is unaffected" {
  dir="$(mkbase demo)"
  python3 - "$dir/tasks.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("**Role:** backend",
              "**Role:** backend\n**Scope:** src/**, tests/bats/test_demo.bats")
open(p, "w", encoding="utf-8").write(s)
PY
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# ── [5] a transitively missing cross-spec dependency must be reported ───────

@test "r2 [5]: a missing transitive cross-spec dependency is reported" {
  alpha="$(mkbase alpha)"
  beta="$(mkbase beta)"
  # alpha#1 → beta#1 → ghost#1, where ghost does not exist at all.
  python3 - "$alpha/tasks.md" beta '#1' <<'PY'
import sys
p, topic, n = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
s = s.replace("**Role:** backend", "**Role:** backend\n**Blocked-by:** %s%s" % (topic, n))
open(p, "w", encoding="utf-8").write(s)
PY
  python3 - "$beta/tasks.md" ghost '#1' <<'PY'
import sys
p, topic, n = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
s = s.replace("**Role:** backend", "**Role:** backend\n**Blocked-by:** %s%s" % (topic, n))
open(p, "w", encoding="utf-8").write(s)
PY
  run bash "$VALIDATE" "$alpha"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'ghost'
}

@test "r2 [5]: a resolvable transitive cross-spec chain still passes" {
  alpha="$(mkbase alpha)"
  beta="$(mkbase beta)"
  python3 - "$alpha/tasks.md" beta <<'PY'
import sys
p, topic = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
s = s.replace("**Role:** backend", "**Role:** backend\n**Blocked-by:** %s#1" % topic)
open(p, "w", encoding="utf-8").write(s)
PY
  run bash "$VALIDATE" "$alpha"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
