#!/usr/bin/env bats
# Tests for scripts/mb-idea.sh — capture idea in BACKLOG.md with I-NNN.
#
# Contract:
#   Usage: mb-idea.sh <title> [priority] [mb_path]
#   priority ∈ HIGH|MED|LOW (default MED), case-insensitive input
#   - Appends to `## Ideas` section in BACKLOG.md as
#     `### I-NNN — <title> [<PRIORITY>, NEW, YYYY-MM-DD]`
#   - `I-NNN` is monotonic across ENTIRE file (max existing + 1, zero-padded 3 digits).
#   - Idempotent by title: second call with same title → no-op + warning.
#   - Prints created ID on stdout: "I-NNN".
#   - Exit 0 on success, 1 on missing BACKLOG.md, 2 on invalid priority.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  IDEA="$REPO_ROOT/scripts/mb-idea.sh"

  TMPROOT="$(mktemp -d)"
  TMPBANK="$TMPROOT/.memory-bank"
  mkdir -p "$TMPBANK"

  cat > "$TMPBANK/BACKLOG.md" <<'EOF'
# Backlog

## Ideas

## ADR
EOF
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# ═══════════════════════════════════════════════════════════════
# Smoke
# ═══════════════════════════════════════════════════════════════

@test "idea: script exists and is executable" {
  [ -f "$IDEA" ]
  [ -x "$IDEA" ]
}

@test "idea: creates I-001 on first call in empty BACKLOG" {
  run bash "$IDEA" "First idea" "HIGH" "$TMPBANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"I-001"* ]]

  grep -qE '### I-001 — First idea \[HIGH, NEW, [0-9]{4}-[0-9]{2}-[0-9]{2}\]' "$TMPBANK/BACKLOG.md"
}

@test "idea: default priority is MED when omitted" {
  run bash "$IDEA" "Unspecified priority" "" "$TMPBANK"
  [ "$status" -eq 0 ]
  grep -qE '### I-00[0-9]+ — Unspecified priority \[MED, NEW,' "$TMPBANK/BACKLOG.md"
}

# ═══════════════════════════════════════════════════════════════
# Monotonic IDs
# ═══════════════════════════════════════════════════════════════

@test "idea: second call produces I-002" {
  bash "$IDEA" "One" "HIGH" "$TMPBANK"
  bash "$IDEA" "Two" "LOW" "$TMPBANK"

  grep -qE '### I-001 — One'  "$TMPBANK/BACKLOG.md"
  grep -qE '### I-002 — Two'  "$TMPBANK/BACKLOG.md"
}

@test "idea: auto-increment continues after user-added I-005" {
  cat >> "$TMPBANK/BACKLOG.md" <<'EOF'

### I-005 — manual injection [MED, NEW, 2026-04-01]
EOF

  bash "$IDEA" "After gap" "MED" "$TMPBANK"
  grep -qE '### I-006 — After gap' "$TMPBANK/BACKLOG.md"
}

# ═══════════════════════════════════════════════════════════════
# Idempotency
# ═══════════════════════════════════════════════════════════════

@test "idea: idempotent by title — duplicate is no-op" {
  bash "$IDEA" "Same title" "HIGH" "$TMPBANK"
  bash "$IDEA" "Same title" "HIGH" "$TMPBANK"

  # Exactly one I-NNN line matching the title
  count=$(grep -cE '### I-[0-9]{3} — Same title' "$TMPBANK/BACKLOG.md")
  [ "$count" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════
# Validation
# ═══════════════════════════════════════════════════════════════

@test "idea: invalid priority fails (exit 2)" {
  run bash "$IDEA" "Title" "URGENT!!" "$TMPBANK"
  [ "$status" -eq 2 ]
}

@test "idea: priority is case-insensitive input, uppercase in file" {
  bash "$IDEA" "case test" "low" "$TMPBANK"
  grep -qE '### I-[0-9]{3} — case test \[LOW,' "$TMPBANK/BACKLOG.md"
}
