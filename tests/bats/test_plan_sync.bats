#!/usr/bin/env bats
# Tests for scripts/mb-plan-sync.sh and scripts/mb-plan-done.sh.
#
# v3.1 contract — minimal single-plan edge cases + error handling.
# Multi-plan behaviour lives in test_plan_sync_multi.bats / test_plan_done_multi.bats.
#
# Contract (sync):
#   - checklist.md: for each (N, name) pair — if no `## Stage N: <name>` yet,
#     append heading + `- ⬜ <name>`. Idempotent by EXACT title.
#   - plan.md: upsert entry in `<!-- mb-active-plans --> ... <!-- /mb-active-plans -->`
#     block; create the block if missing.
#
# Contract (done):
#   - Removes plan's Stage sections from checklist.md.
#   - Removes plan's entry from the active-plans block.
#   - Moves plan file to plans/done/<basename>.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SYNC="$REPO_ROOT/scripts/mb-plan-sync.sh"
  DONE="$REPO_ROOT/scripts/mb-plan-done.sh"

  TMPROOT="$(mktemp -d)"
  TMPBANK="$TMPROOT/.memory-bank"
  mkdir -p "$TMPBANK/plans/done"

  PLAN_FILE="$TMPBANK/plans/2026-04-19_refactor_skill-v2.md"
  cat > "$PLAN_FILE" <<'EOF'
# Plan: refactor — skill-v2

## Context

Test plan.

## Stages

<!-- mb-stage:1 -->
### Stage 1: DRY-utilities

What to do: create _lib.sh.

<!-- mb-stage:2 -->
### Stage 2: Language-agnostic metrics

What to do: create mb-metrics.sh.

<!-- mb-stage:3 -->
### Stage 3: codebase-mapper

What to do: adapt agent.
EOF

  cat > "$TMPBANK/checklist.md" <<'EOF'
# Project — Checklist

## Stage 0: Dogfood init
- ✅ initialization
EOF

  cat > "$TMPBANK/roadmap.md" <<'EOF'
# Project — Plan

## Current focus

Test focus.

## Active plans

<!-- mb-active-plans -->
<!-- /mb-active-plans -->

## Next up

See BACKLOG.md.
EOF
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# ═══════════════════════════════════════════════════════════════
# mb-plan-sync.sh
# ═══════════════════════════════════════════════════════════════

@test "sync: script exists and is executable" {
  [ -f "$SYNC" ]
  [ -x "$SYNC" ]
}

@test "sync: parses mb-stage markers from plan" {
  run bash "$SYNC" "$PLAN_FILE" "$TMPBANK"
  [ "$status" -eq 0 ]
}

@test "sync: appends missing stages to checklist" {
  run bash "$SYNC" "$PLAN_FILE" "$TMPBANK"
  [ "$status" -eq 0 ]

  grep -q "^## Stage 1: DRY-utilities$" "$TMPBANK/checklist.md"
  grep -q "^## Stage 2: Language-agnostic metrics$" "$TMPBANK/checklist.md"
  grep -q "^## Stage 3: codebase-mapper$" "$TMPBANK/checklist.md"
}

@test "sync: legacy unmarked section preserved + new marker section appended (v3.2 contract)" {
  # v3.2 (Sprint 3, I-028): sync no longer claims unmarked sections. A pre-existing
  # legacy section with the same heading must remain untouched; sync writes its
  # own `<!-- mb-plan:<basename> -->` marker section alongside it.
  cat >> "$TMPBANK/checklist.md" <<'EOF'

## Stage 1: DRY-utilities
- ✅ custom item
EOF

  bash "$SYNC" "$PLAN_FILE" "$TMPBANK"

  # Legacy section preserved
  grep -q "custom item" "$TMPBANK/checklist.md"
  # Two `## Stage 1: DRY-utilities` headings now coexist (one legacy, one marker-owned)
  count=$(grep -c "^## Stage 1: DRY-utilities$" "$TMPBANK/checklist.md")
  [ "$count" -eq 2 ]
  # Plan's marker is present
  grep -q "<!-- mb-plan:2026-04-19_refactor_skill-v2.md -->" "$TMPBANK/checklist.md"
}

@test "sync: idempotent — double run equals single run" {
  bash "$SYNC" "$PLAN_FILE" "$TMPBANK"
  sum1=$(shasum "$TMPBANK/checklist.md" "$TMPBANK/roadmap.md" | shasum)

  bash "$SYNC" "$PLAN_FILE" "$TMPBANK"
  sum2=$(shasum "$TMPBANK/checklist.md" "$TMPBANK/roadmap.md" | shasum)

  [ "$sum1" = "$sum2" ]
}

@test "sync: upserts entry into plan.md active-plans block" {
  bash "$SYNC" "$PLAN_FILE" "$TMPBANK"

  grep -q "2026-04-19_refactor_skill-v2.md" "$TMPBANK/roadmap.md"
  grep -q "refactor — skill-v2" "$TMPBANK/roadmap.md"
}

@test "sync: active-plans markers stay a single pair" {
  bash "$SYNC" "$PLAN_FILE" "$TMPBANK"

  op=$(grep -c "<!-- mb-active-plans -->" "$TMPBANK/roadmap.md")
  cl=$(grep -c "<!-- /mb-active-plans -->" "$TMPBANK/roadmap.md")
  [ "$op" -eq 1 ]
  [ "$cl" -eq 1 ]
}

@test "sync: fallback to regex when no mb-stage markers" {
  cat > "$PLAN_FILE" <<'EOF'
# Plan: fix — legacy-plan

## Stages

### Stage 1: fix bug A
content

### Stage 2: fix bug B
content
EOF

  run bash "$SYNC" "$PLAN_FILE" "$TMPBANK"
  [ "$status" -eq 0 ]

  grep -q "^## Stage 1: fix bug A$" "$TMPBANK/checklist.md"
  grep -q "^## Stage 2: fix bug B$" "$TMPBANK/checklist.md"
}

@test "sync: creates active-plans markers if plan.md lacks them" {
  cat > "$TMPBANK/roadmap.md" <<'EOF'
# Plan

## Current focus

Empty.
EOF

  run bash "$SYNC" "$PLAN_FILE" "$TMPBANK"
  [ "$status" -eq 0 ]

  grep -q "<!-- mb-active-plans -->" "$TMPBANK/roadmap.md"
  grep -q "<!-- /mb-active-plans -->" "$TMPBANK/roadmap.md"
  grep -q "2026-04-19_refactor_skill-v2.md" "$TMPBANK/roadmap.md"
}

@test "sync: fails gracefully when plan-file missing" {
  run bash "$SYNC" "$TMPBANK/plans/nonexistent.md" "$TMPBANK"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"not found"* ]]
}

@test "sync: checklist with ⬜ item per stage" {
  bash "$SYNC" "$PLAN_FILE" "$TMPBANK"

  grep -q "^- ⬜ DRY-utilities$" "$TMPBANK/checklist.md"
  grep -q "^- ⬜ Language-agnostic metrics$" "$TMPBANK/checklist.md"
  grep -q "^- ⬜ codebase-mapper$" "$TMPBANK/checklist.md"
}

# ═══════════════════════════════════════════════════════════════
# mb-plan-done.sh — error handling only (full contract: test_plan_done_multi.bats)
# ═══════════════════════════════════════════════════════════════

@test "done: script exists and is executable" {
  [ -f "$DONE" ]
  [ -x "$DONE" ]
}

@test "done: moves plan file to plans/done/" {
  bash "$SYNC" "$PLAN_FILE" "$TMPBANK"
  basename_file=$(basename "$PLAN_FILE")
  run bash "$DONE" "$PLAN_FILE" "$TMPBANK"
  [ "$status" -eq 0 ]

  [ -f "$TMPBANK/plans/done/$basename_file" ]
  [ ! -f "$PLAN_FILE" ]
}

@test "done: fails when plan-file not in plans/ of mb_path" {
  stray="$TMPROOT/stray-plan.md"
  cp "$PLAN_FILE" "$stray"

  run bash "$DONE" "$stray" "$TMPBANK"
  [ "$status" -ne 0 ]
}

@test "done: idempotent — re-running after move fails gracefully" {
  bash "$SYNC" "$PLAN_FILE" "$TMPBANK"
  bash "$DONE" "$PLAN_FILE" "$TMPBANK"

  run bash "$DONE" "$PLAN_FILE" "$TMPBANK"
  [ "$status" -ne 0 ]
}

@test "done: preserves other stages in checklist" {
  bash "$SYNC" "$PLAN_FILE" "$TMPBANK"
  bash "$DONE" "$PLAN_FILE" "$TMPBANK"

  grep -q "^## Stage 0: Dogfood init$" "$TMPBANK/checklist.md"
  grep -q "^- ✅ initialization$" "$TMPBANK/checklist.md"
}
