#!/usr/bin/env bats
# Tests for scripts/mb-idea-promote.sh — promote an idea to a plan.
#
# Contract:
#   Usage: mb-idea-promote.sh <I-NNN> <type> [mb_path]
#   type ∈ feature|fix|refactor|experiment
#   - Finds idea by ID in BACKLOG.md, extracts title → slug.
#   - Calls mb-plan.sh with <type> <slug> to create a plan file.
#   - Changes idea status NEW|TRIAGED → PLANNED, adds/updates `**Plan:** [plans/...](plans/...)`.
#   - Runs mb-plan-sync.sh on the created plan (appears in STATUS.md + plan.md active-plans).
#   - Rejects promoting idea already in PLANNED/DONE/DECLINED status.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PROMOTE="$REPO_ROOT/scripts/mb-idea-promote.sh"

  TMPROOT="$(mktemp -d)"
  TMPBANK="$TMPROOT/.memory-bank"
  mkdir -p "$TMPBANK/plans/done"

  cat > "$TMPBANK/backlog.md" <<'EOF'
# Backlog

## Ideas

### I-001 — refactor logging layer [HIGH, NEW, 2026-04-01]

**Problem:** logs are not structured.

**Sketch:** use structlog.

**Plan:** —

### I-002 — already planned idea [MED, PLANNED, 2026-04-02]

**Plan:** [plans/2026-04-02_feature_existing.md](plans/2026-04-02_feature_existing.md)

## ADR
EOF

  cat > "$TMPBANK/checklist.md" <<'EOF'
# Project — Checklist
EOF

  cat > "$TMPBANK/roadmap.md" <<'EOF'
# Project — Plan

## Active plans

<!-- mb-active-plans -->
<!-- /mb-active-plans -->
EOF

  cat > "$TMPBANK/status.md" <<'EOF'
# Project — Status

## Active plans

<!-- mb-active-plans -->
<!-- /mb-active-plans -->

## Recently done (last 10)

<!-- mb-recent-done -->
<!-- /mb-recent-done -->
EOF
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# ═══════════════════════════════════════════════════════════════
# Smoke
# ═══════════════════════════════════════════════════════════════

@test "promote: script exists and is executable" {
  [ -f "$PROMOTE" ]
  [ -x "$PROMOTE" ]
}

# ═══════════════════════════════════════════════════════════════
# Happy path
# ═══════════════════════════════════════════════════════════════

@test "promote: creates plan file with sanitized slug from idea title" {
  run bash "$PROMOTE" "I-001" "refactor" "$TMPBANK"
  [ "$status" -eq 0 ]

  # Plan file should exist with basename containing "refactor-logging-layer"
  find "$TMPBANK/plans" -maxdepth 1 -type f -name '*refactor*logging*layer*' | grep -q .
}

@test "promote: flips idea status NEW → PLANNED" {
  bash "$PROMOTE" "I-001" "refactor" "$TMPBANK"

  ! grep -qE 'I-001 — refactor logging layer \[HIGH, NEW' "$TMPBANK/backlog.md"
  grep -qE 'I-001 — refactor logging layer \[HIGH, PLANNED' "$TMPBANK/backlog.md"
}

@test "promote: adds Plan link to the idea section" {
  bash "$PROMOTE" "I-001" "refactor" "$TMPBANK"

  # Plan link should point to plans/<basename>
  awk '
    /### I-001/ { inside=1; next }
    /^### / { inside=0 }
    inside { print }
  ' "$TMPBANK/backlog.md" > /tmp/mb-i-001.txt

  grep -qE '\*\*Plan:\*\* \[plans/.*refactor.*logging.*layer.*\.md\]' /tmp/mb-i-001.txt
  rm -f /tmp/mb-i-001.txt
}

@test "promote: plan appears in mb-active-plans block" {
  bash "$PROMOTE" "I-001" "refactor" "$TMPBANK"

  # plan.md should contain the new plan basename in active-plans block
  awk '
    /<!-- mb-active-plans -->/ { inside=1; next }
    /<!-- \/mb-active-plans -->/ { inside=0; next }
    inside { print }
  ' "$TMPBANK/roadmap.md" > /tmp/mb-active.txt

  grep -qE 'refactor.*logging.*layer' /tmp/mb-active.txt
  rm -f /tmp/mb-active.txt
}

# ═══════════════════════════════════════════════════════════════
# Validation
# ═══════════════════════════════════════════════════════════════

@test "promote: rejects idea that is already PLANNED" {
  run bash "$PROMOTE" "I-002" "feature" "$TMPBANK"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"PLANNED"* ]] || [[ "$output" == *"already"* ]]
}

@test "promote: rejects unknown idea ID" {
  run bash "$PROMOTE" "I-099" "feature" "$TMPBANK"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"I-099"* ]] || [[ "$output$stderr" == *"not found"* ]]
}
