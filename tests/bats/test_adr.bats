#!/usr/bin/env bats
# Tests for scripts/mb-adr.sh — capture Architecture Decision Record.
#
# Contract:
#   Usage: mb-adr.sh <title> [mb_path]
#   - Appends to `## ADR` section in backlog.md as
#     `### ADR-NNN — <title> [YYYY-MM-DD]`
#   - Monotonic NNN (zero-padded 3 digits) across entire file.
#   - Skeleton includes: **Context:** / **Options:** / **Decision:** / **Rationale:** / **Consequences:**
#   - Prints created ID on stdout.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ADR="$REPO_ROOT/scripts/mb-adr.sh"

  TMPROOT="$(mktemp -d)"
  TMPBANK="$TMPROOT/.memory-bank"
  mkdir -p "$TMPBANK"

  cat > "$TMPBANK/backlog.md" <<'EOF'
# Backlog

## Ideas

## ADR
EOF
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

@test "adr: script exists and is executable" {
  [ -f "$ADR" ]
  [ -x "$ADR" ]
}

@test "adr: creates ADR-001 on first call" {
  run bash "$ADR" "Use OIDC for PyPI publishing" "$TMPBANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ADR-001"* ]]

  grep -qE '### ADR-001 — Use OIDC for PyPI publishing \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]' "$TMPBANK/backlog.md"
}

@test "adr: skeleton contains required labeled sections" {
  bash "$ADR" "Sample ADR" "$TMPBANK"

  grep -q '\*\*Context:\*\*'      "$TMPBANK/backlog.md"
  grep -q '\*\*Options:\*\*'      "$TMPBANK/backlog.md"
  grep -q '\*\*Decision:\*\*'     "$TMPBANK/backlog.md"
  grep -q '\*\*Rationale:\*\*'    "$TMPBANK/backlog.md"
  grep -q '\*\*Consequences:\*\*' "$TMPBANK/backlog.md"
}

@test "adr: monotonic IDs across calls" {
  bash "$ADR" "First ADR"  "$TMPBANK"
  bash "$ADR" "Second ADR" "$TMPBANK"

  grep -qE '### ADR-001 — First ADR' "$TMPBANK/backlog.md"
  grep -qE '### ADR-002 — Second ADR' "$TMPBANK/backlog.md"
}

@test "adr: skips gap — user-added ADR-007 → next auto is ADR-008" {
  cat >> "$TMPBANK/backlog.md" <<'EOF'

### ADR-007 — manual ADR [2026-04-10]
EOF

  bash "$ADR" "After gap" "$TMPBANK"
  grep -qE '### ADR-008 — After gap' "$TMPBANK/backlog.md"
}
