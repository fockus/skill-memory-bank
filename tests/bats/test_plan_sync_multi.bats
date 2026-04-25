#!/usr/bin/env bats
# Tests for v3.1 multi-active-plan support in scripts/mb-plan-sync.sh.
#
# Contract (v3.1):
#   - New marker block `<!-- mb-active-plans --> ... <!-- /mb-active-plans -->`
#     (plural) in BOTH roadmap.md and status.md.
#   - Each active plan is an entry `- [YYYY-MM-DD] [plans/<basename>](plans/<basename>) — <title>`.
#   - Upsert semantics: syncing plan A then plan B produces 2 entries, not 1.
#   - Re-syncing same plan updates (replaces line for that basename), not dupes.
#   - Backward-compat: single `<!-- mb-active-plan -->` → auto-upgrade to plural.
#   - status.md gets parallel update (same block).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SYNC="$REPO_ROOT/scripts/mb-plan-sync.sh"

  TMPROOT="$(mktemp -d)"
  TMPBANK="$TMPROOT/.memory-bank"
  mkdir -p "$TMPBANK/plans/done"

  PLAN_A="$TMPBANK/plans/2026-04-20_feature_a.md"
  cat > "$PLAN_A" <<'EOF'
# Plan: feature — a

## Stages

<!-- mb-stage:1 -->
### Stage 1: do-a-1

content
EOF

  PLAN_B="$TMPBANK/plans/2026-04-21_refactor_b.md"
  cat > "$PLAN_B" <<'EOF'
# Plan: refactor — b

## Stages

<!-- mb-stage:1 -->
### Stage 1: do-b-1

content
EOF

  cat > "$TMPBANK/checklist.md" <<'EOF'
# Project — Checklist

<!-- Only active phase tasks. -->
EOF

  cat > "$TMPBANK/roadmap.md" <<'EOF'
# Project — Plan

## Current focus

Test.

## Active plans

<!-- mb-active-plans -->
<!-- /mb-active-plans -->

## Next up

See [backlog.md](backlog.md).
EOF

  cat > "$TMPBANK/status.md" <<'EOF'
# Project — Status

**Current phase:** testing

## Metrics

- Tests: N/A

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
# Multi-active: two plans in parallel
# ═══════════════════════════════════════════════════════════════

@test "sync-multi: first plan creates one entry in mb-active-plans block" {
  bash "$SYNC" "$PLAN_A" "$TMPBANK"

  run cat "$TMPBANK/roadmap.md"
  [[ "$output" == *"<!-- mb-active-plans -->"* ]]
  [[ "$output" == *"2026-04-20_feature_a.md"* ]]
  count=$(grep -c 'plans/2026-04-20_feature_a' "$TMPBANK/roadmap.md" || true)
  [ "$count" -ge 1 ]
}

@test "sync-multi: second plan appends entry, first preserved (no overwrite)" {
  bash "$SYNC" "$PLAN_A" "$TMPBANK"
  bash "$SYNC" "$PLAN_B" "$TMPBANK"

  grep -q "2026-04-20_feature_a.md" "$TMPBANK/roadmap.md"
  grep -q "2026-04-21_refactor_b.md" "$TMPBANK/roadmap.md"
}

@test "sync-multi: resyncing plan A does not create duplicate entry" {
  bash "$SYNC" "$PLAN_A" "$TMPBANK"
  bash "$SYNC" "$PLAN_A" "$TMPBANK"

  count=$(grep -c "2026-04-20_feature_a.md" "$TMPBANK/roadmap.md")
  [ "$count" -eq 1 ]
}

@test "sync-multi: both entries live inside same mb-active-plans block" {
  bash "$SYNC" "$PLAN_A" "$TMPBANK"
  bash "$SYNC" "$PLAN_B" "$TMPBANK"

  # Exactly 1 opening + 1 closing marker pair
  op=$(grep -c '<!-- mb-active-plans -->' "$TMPBANK/roadmap.md")
  cl=$(grep -c '<!-- /mb-active-plans -->' "$TMPBANK/roadmap.md")
  [ "$op" -eq 1 ]
  [ "$cl" -eq 1 ]

  awk '
    /<!-- mb-active-plans -->/ { inside=1; next }
    /<!-- \/mb-active-plans -->/ { inside=0; next }
    inside { print }
  ' "$TMPBANK/roadmap.md" > /tmp/mb-multi-block.txt

  grep -q 'feature_a' /tmp/mb-multi-block.txt
  grep -q 'refactor_b' /tmp/mb-multi-block.txt
  rm -f /tmp/mb-multi-block.txt
}

# ═══════════════════════════════════════════════════════════════
# status.md parallel sync
# ═══════════════════════════════════════════════════════════════

@test "sync-multi: status.md gets same entry in its mb-active-plans block" {
  bash "$SYNC" "$PLAN_A" "$TMPBANK"

  grep -q "2026-04-20_feature_a.md" "$TMPBANK/status.md"
}

@test "sync-multi: status.md accumulates both plans too" {
  bash "$SYNC" "$PLAN_A" "$TMPBANK"
  bash "$SYNC" "$PLAN_B" "$TMPBANK"

  grep -q "2026-04-20_feature_a.md" "$TMPBANK/status.md"
  grep -q "2026-04-21_refactor_b.md" "$TMPBANK/status.md"
}

# ═══════════════════════════════════════════════════════════════
# Backward compatibility: single-plan marker
# ═══════════════════════════════════════════════════════════════

@test "sync-multi: auto-upgrades legacy single-plan marker to plural" {
  # Replace plural markers with legacy singular
  cat > "$TMPBANK/roadmap.md" <<'EOF'
# Project — Plan

## Active plan

<!-- mb-active-plan -->
<!-- /mb-active-plan -->
EOF

  bash "$SYNC" "$PLAN_A" "$TMPBANK"

  # After sync — plural markers present; singular gone (or coexist gracefully)
  grep -q '<!-- mb-active-plans -->' "$TMPBANK/roadmap.md"
  grep -q "2026-04-20_feature_a.md" "$TMPBANK/roadmap.md"
}

# ═══════════════════════════════════════════════════════════════
# Entry format
# ═══════════════════════════════════════════════════════════════

@test "sync-multi: entry format includes date + link + title" {
  bash "$SYNC" "$PLAN_A" "$TMPBANK"

  # Format: "- [YYYY-MM-DD] [plans/<basename>](plans/<basename>) — <title>"
  # Date MUST come from the plan basename's date prefix (2026-04-20)
  awk '
    /<!-- mb-active-plans -->/ { inside=1; next }
    /<!-- \/mb-active-plans -->/ { inside=0; next }
    inside && /feature_a/ { print }
  ' "$TMPBANK/roadmap.md" > /tmp/mb-entry.txt

  grep -qE '2026-04-20' /tmp/mb-entry.txt
  grep -qE 'plans/2026-04-20_feature_a.md' /tmp/mb-entry.txt
  grep -qE 'feature — a' /tmp/mb-entry.txt
  rm -f /tmp/mb-entry.txt
}

@test "sync-multi: idempotent — two runs checksum equal" {
  bash "$SYNC" "$PLAN_A" "$TMPBANK"
  bash "$SYNC" "$PLAN_B" "$TMPBANK"
  sum1=$(shasum "$TMPBANK/roadmap.md" "$TMPBANK/status.md" "$TMPBANK/checklist.md" | shasum)

  bash "$SYNC" "$PLAN_A" "$TMPBANK"
  bash "$SYNC" "$PLAN_B" "$TMPBANK"
  sum2=$(shasum "$TMPBANK/roadmap.md" "$TMPBANK/status.md" "$TMPBANK/checklist.md" | shasum)

  [ "$sum1" = "$sum2" ]
}
