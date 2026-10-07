#!/usr/bin/env bats
# Tests for scripts/mb-adr.sh — capture an Architecture Decision Record.
#
# Contract (AGR-062):
#   Usage: mb-adr.sh <title> [mb_path]
#   - Appends to <bank>/adr.md (created with `# Architecture Decision Records`
#     when missing) as `### ADR-NNN — <title> [YYYY-MM-DD] · status: accepted`.
#   - NNN = max ADR id over adr.md AND backlog.md + 1 (transition period:
#     banks whose ADRs still sit in backlog.md get no collisions).
#   - Skeleton: **Context:** / **Decision:** / **Alternatives:** / **Consequences:**
#   - backlog.md is never modified.
#   - Prints created ID on stdout.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ADR="$REPO_ROOT/scripts/mb-adr.sh"

  TMPROOT="$(mktemp -d)"
  TMPBANK="$TMPROOT/.memory-bank"
  mkdir -p "$TMPBANK"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

@test "adr: script exists and is executable" {
  [ -f "$ADR" ]
  [ -x "$ADR" ]
}

@test "adr: empty bank → adr.md created with header and ADR-001" {
  run bash "$ADR" "Use OIDC for PyPI publishing" "$TMPBANK"
  [ "$status" -eq 0 ]
  [ "$output" = "ADR-001" ]

  [ "$(head -1 "$TMPBANK/adr.md")" = "# Architecture Decision Records" ]
  grep -qE '^### ADR-001 — Use OIDC for PyPI publishing \[[0-9]{4}-[0-9]{2}-[0-9]{2}\] · status: accepted$' "$TMPBANK/adr.md"
  [ ! -e "$TMPBANK/backlog.md" ]
}

@test "adr: skeleton has exactly the four key fields" {
  bash "$ADR" "Sample ADR" "$TMPBANK"

  grep -q '^\*\*Context:\*\*'      "$TMPBANK/adr.md"
  grep -q '^\*\*Decision:\*\*'     "$TMPBANK/adr.md"
  grep -q '^\*\*Alternatives:\*\*' "$TMPBANK/adr.md"
  grep -q '^\*\*Consequences:\*\*' "$TMPBANK/adr.md"
  run grep -E '^\*\*(Options|Rationale):\*\*' "$TMPBANK/adr.md"
  [ "$status" -eq 1 ]
}

@test "adr: ADR-012 still in backlog.md, no adr.md → ADR-013 in adr.md, backlog untouched" {
  cat > "$TMPBANK/backlog.md" <<'EOF'
# Backlog

## Ideas

## ADR

### ADR-012 — legacy decision [2026-10-05]

**Context:** old.
EOF
  before=$(cksum < "$TMPBANK/backlog.md")

  run bash "$ADR" "Next decision" "$TMPBANK"
  [ "$status" -eq 0 ]
  [ "$output" = "ADR-013" ]
  grep -qE '^### ADR-013 — Next decision ' "$TMPBANK/adr.md"

  run bash "$ADR" "Another decision" "$TMPBANK"
  [ "$output" = "ADR-014" ]
  grep -qE '^### ADR-014 — Another decision ' "$TMPBANK/adr.md"

  [ "$(cksum < "$TMPBANK/backlog.md")" = "$before" ]
}

@test "adr: gap in adr.md — manual ADR-007 → next auto is ADR-008" {
  printf '# Architecture Decision Records\n\n### ADR-007 — manual ADR [2026-04-10] · status: accepted\n' > "$TMPBANK/adr.md"

  run bash "$ADR" "After gap" "$TMPBANK"
  [ "$output" = "ADR-008" ]
  grep -qE '^### ADR-008 — After gap' "$TMPBANK/adr.md"
  grep -qE '^### ADR-007 — manual ADR' "$TMPBANK/adr.md"
}
