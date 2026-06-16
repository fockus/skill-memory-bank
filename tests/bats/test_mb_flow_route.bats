#!/usr/bin/env bats
#
# Task 8 — deterministic route resolver (mb-flow-route.sh).
# Covers REQ-DF-020 (auto candidate), REQ-DF-022 (route-floor) and
# REQ-DF-025 (explicit override still floored). The LLM classifier lives in
# the command layer; THIS resolver is the deterministic, testable core.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-flow-route.sh"
  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

# 1. domain/ path forces arch even though the candidate is the lower code-change.
@test "mb-flow-route: domain/ diff forces arch over a code-change candidate" {
  run bash "$SCRIPT" "$MB" --changed "src/domain/user.py" --candidate code-change --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
  [[ "$output" == *'domain'* ]]
}

# 2. application/ports path forces arch over a bugfix candidate.
@test "mb-flow-route: application/ports diff forces arch over a bugfix candidate" {
  run bash "$SCRIPT" "$MB" --changed "src/application/ports/repo.py" --candidate bugfix --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
}

# 3. A *Protocol interface file forces arch.
@test "mb-flow-route: *Protocol interface file forces arch" {
  run bash "$SCRIPT" "$MB" --changed "src/UserProtocol.py" --candidate code-change --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
}

# 4. A declared protected_path forces arch (temp bank declares the glob).
@test "mb-flow-route: protected_path match forces arch" {
  printf 'protected_paths:\n  - "secrets/**"\n' > "$MB/pipeline.yaml"
  run bash "$SCRIPT" "$MB" --changed "secrets/key.txt" --candidate code-change --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
  [[ "$output" == *'protected'* ]]
}

# 5. depends_on > 0 forces arch even for a trivial README change.
@test "mb-flow-route: depends_on>0 forces arch" {
  run bash "$SCRIPT" "$MB" --depends-on 1 --changed "README.md" --candidate code-change --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
  [[ "$output" == *'depends_on'* ]]
}

# 6. A trivial single-file source change keeps the candidate (no floor).
@test "mb-flow-route: trivial single-file change keeps code-change (no floor)" {
  run bash "$SCRIPT" "$MB" --changed "src/util.py" --candidate code-change --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"code-change"'* ]]
  [[ "$output" == *'"floor_triggered":false'* ]]
}

# 7. No candidate → defaults to code-change (the dominant case).
@test "mb-flow-route: default candidate is code-change" {
  run bash "$SCRIPT" "$MB" --changed "README.md" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"candidate":"code-change"'* ]]
  [[ "$output" == *'"route":"code-change"'* ]]
  [[ "$output" == *'"floor_triggered":false'* ]]
}

# 8. Explicit override writes route: arch into the status.md fence (real write).
@test "mb-flow-route: explicit --route arch writes the fence" {
  run bash "$SCRIPT" "$MB" --route arch --changed "README.md"
  [ "$status" -eq 0 ]
  [ -f "$MB/status.md" ]
  grep -q 'route: arch' "$MB/status.md"
}

# 9. An override BELOW the floor is raised to the floor, never honored blindly.
@test "mb-flow-route: override below the floor is raised to arch" {
  run bash "$SCRIPT" "$MB" --route bugfix --changed "src/domain/x.py" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"candidate":"bugfix"'* ]]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
}

# 10. research under a floor trigger is raised to arch.
@test "mb-flow-route: research candidate under a trigger is raised to arch" {
  run bash "$SCRIPT" "$MB" --candidate research --changed "src/domain/x.py" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
}

# 11. A real write twice with identical inputs is byte-identical (idempotent).
@test "mb-flow-route: repeated real write is byte-identical" {
  run bash "$SCRIPT" "$MB" --route arch --changed "README.md"
  [ "$status" -eq 0 ]
  cp "$MB/status.md" "$PROJECT/first.md"
  run bash "$SCRIPT" "$MB" --route arch --changed "README.md"
  [ "$status" -eq 0 ]
  diff "$PROJECT/first.md" "$MB/status.md"
}

# 12. An unknown route is rejected with exit 1.
@test "mb-flow-route: unknown route exits 1" {
  run bash "$SCRIPT" "$MB" --route nonsense --changed "README.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nonsense"* ]]
}

# 13. --help prints usage and exits 0.
@test "mb-flow-route: --help works" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"mb-flow-route"* ]]
}

# 14. migration candidate under a trigger stays migration (floor only RAISES).
@test "mb-flow-route: migration candidate under a trigger stays migration" {
  run bash "$SCRIPT" "$MB" --candidate migration --changed "src/domain/x.py" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"migration"'* ]]
}

# --- Fix-cycle 1: floor false-negatives (ADR-4 — false-negatives forbidden) ---

# 15. Singular domain FILE (not under domain/) forces arch.
@test "mb-flow-route: src/domain.py (singular file) forces arch" {
  run bash "$SCRIPT" "$MB" --changed "src/domain.py" --candidate bugfix --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
}

# 16. contracts file forces arch.
@test "mb-flow-route: src/contracts.py forces arch" {
  run bash "$SCRIPT" "$MB" --changed "src/contracts.py" --candidate code-change --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
}

# 17. SINGULAR interface dir forces arch.
@test "mb-flow-route: src/interface/user.py (singular dir) forces arch" {
  run bash "$SCRIPT" "$MB" --changed "src/interface/user.py" --candidate bugfix --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
}

# 18. PLURAL protocols dir forces arch.
@test "mb-flow-route: src/protocols/user.py (plural dir) forces arch" {
  run bash "$SCRIPT" "$MB" --changed "src/protocols/user.py" --candidate code-change --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
}

# 19. Windows path separators are normalized before matching → arch.
@test "mb-flow-route: windows separators src\\domain\\User.py forces arch" {
  run bash "$SCRIPT" "$MB" --changed 'src\domain\User.py' --candidate bugfix --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
}

# 20. A bare 'maindomain.py' does NOT over-match the domain floor (stays code-change).
@test "mb-flow-route: maindomain.py does not over-match the domain floor" {
  run bash "$SCRIPT" "$MB" --changed "src/maindomain.py" --candidate code-change --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"code-change"'* ]]
  [[ "$output" == *'"floor_triggered":false'* ]]
}

# --- Fix-cycle 2: derive_depends_on must be inline-comment aware (fail-open) ---

# 21. linked_plans entry with a trailing YAML comment still resolves → arch.
@test "mb-flow-route: auto-derived depends_on survives an inline YAML comment" {
  mkdir -p "$MB/plans"
  printf -- '---\ntype: feature\ntopic: p\ndepends_on: [base.md]\n---\n# Plan\n' > "$MB/plans/p.md"
  printf -- '---\nid: G-001\nstatus: active\nlinked_plans: [plans/p.md] # active\n---\n# Goal\n## Acceptance criteria\n- [ ] x\n' > "$MB/goal.md"
  run bash "$SCRIPT" "$MB" --changed "README.md" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
  [[ "$output" == *'depends_on'* ]]
}

# --- Fix-cycle 3: an inconclusive protected-check (rc 2) escalates to arch ---

# 22. A malformed protected_paths config (rc 2) escalates conservatively → arch.
@test "mb-flow-route: protected-check rc 2 escalates to arch" {
  if ! python3 -c 'import yaml' 2>/dev/null; then
    skip "needs pyyaml to force mb-work-protected-check.sh exit 2"
  fi
  printf 'protected_paths: "ci/**"\n' > "$MB/pipeline.yaml"
  run bash "$SCRIPT" "$MB" --changed "ci/build.yml" --candidate code-change --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
  [[ "$output" == *'inconclusive'* ]]
}

# --- Fix-cycle 5: the emitted JSON is valid for ALL control characters ---

# 23. A changed path with a control char still yields exactly one VALID JSON object.
@test "mb-flow-route: control-char path produces valid JSON" {
  out="$(bash "$SCRIPT" "$MB" --candidate bugfix --changed-file $'src/\bProtocol.py' --dry-run)"
  printf '%s' "$out" | python3 -m json.tool >/dev/null
}

# --- Fix-cycle (round 2): ROOT-LEVEL arch dirs must also force arch (ADR-4) ---
# domain/ already matched root-level; the contract/interface/protocol/port/abc
# families only had `*/.../*` (a leading segment was required), so a repo whose
# arch dir sits at the root (`contracts/user.py`) slipped below arch — a
# false-negative ADR-4 forbids. One test per family.

# 24. root-level contracts/ dir forces arch.
@test "mb-flow-route: root-level contracts/user.py forces arch" {
  run bash "$SCRIPT" "$MB" --changed "contracts/user.py" --candidate code-change --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
}

# 25. root-level interface/ dir forces arch.
@test "mb-flow-route: root-level interface/user.py forces arch" {
  run bash "$SCRIPT" "$MB" --changed "interface/user.py" --candidate code-change --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
}

# 26. root-level protocols/ dir forces arch.
@test "mb-flow-route: root-level protocols/user.py forces arch" {
  run bash "$SCRIPT" "$MB" --changed "protocols/user.py" --candidate code-change --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
}

# 27. root-level ports/ dir forces arch.
@test "mb-flow-route: root-level ports/user.py forces arch" {
  run bash "$SCRIPT" "$MB" --changed "ports/user.py" --candidate code-change --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
}

# 28. root-level abc/ dir forces arch.
@test "mb-flow-route: root-level abc/user.py forces arch" {
  run bash "$SCRIPT" "$MB" --changed "abc/user.py" --candidate code-change --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"arch"'* ]]
  [[ "$output" == *'"floor_triggered":true'* ]]
}

# 29. NEGATIVE: a substring like 'reports/x.py' must NOT over-match the port floor.
@test "mb-flow-route: reports/x.py does not over-match the port floor" {
  run bash "$SCRIPT" "$MB" --changed "reports/x.py" --candidate code-change --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"route":"code-change"'* ]]
  [[ "$output" == *'"floor_triggered":false'* ]]
}
