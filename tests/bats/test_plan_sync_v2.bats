#!/usr/bin/env bats
# Sprint 1 Stage 5 — mb-plan-sync.sh writes ONE v2 checklist block per plan.
#
# Contract:
#   <!-- mb-plan:<basename> -->
#   ## <plan title> — k/n
#   - ✅|⬜ Stage N — <name>
#
# Idempotent by (marker, stage number): a re-sync neither duplicates the block
# nor resets a ✅ already recorded there.

load 'lib/assert'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SYNC="$REPO_ROOT/scripts/mb-plan-sync.sh"
  TMPROOT="$(mktemp -d)"
  MB="$TMPROOT/.memory-bank"
  mkdir -p "$MB/plans/done"

  PLAN="$MB/plans/2026-09-01_feature_widgets.md"
  cat > "$PLAN" <<'EOF'
# Plan: feature — widget pipeline

<!-- mb-stage:1 -->
### Stage 1: build the widget

<!-- mb-stage:2 -->
### Stage 2: ship the widget
EOF

  printf '# Project — Checklist\n' > "$MB/checklist.md"
  printf '# Roadmap\n\n## Active plans\n\n<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n' > "$MB/roadmap.md"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

@test "sync-v2: v2 block created for a new plan" {
  run bash "$SYNC" "$PLAN" "$MB"
  [ "$status" -eq 0 ]

  [ "$(grep -c '^<!-- mb-plan:2026-09-01_feature_widgets.md -->$' "$MB/checklist.md")" -eq 1 ]
  assert_grep -q '^## widget pipeline — 0/2$' "$MB/checklist.md"
  assert_grep -q '^- ⬜ Stage 1 — build the widget$' "$MB/checklist.md"
  assert_grep -q '^- ⬜ Stage 2 — ship the widget$' "$MB/checklist.md"
  # No per-stage `## Stage N:` sections any more.
  refute_grep -q '^## Stage 1: build the widget$' "$MB/checklist.md"
}

@test "sync-v2: existing block updated, not duplicated" {
  bash "$SYNC" "$PLAN" "$MB"
  cat >> "$PLAN" <<'EOF'

<!-- mb-stage:3 -->
### Stage 3: document the widget
EOF
  run bash "$SYNC" "$PLAN" "$MB"
  [ "$status" -eq 0 ]

  [ "$(grep -c '^<!-- mb-plan:2026-09-01_feature_widgets.md -->$' "$MB/checklist.md")" -eq 1 ]
  assert_grep -q '^## widget pipeline — 0/3$' "$MB/checklist.md"
  assert_grep -q '^- ⬜ Stage 3 — document the widget$' "$MB/checklist.md"
  [ "$(grep -c '^- ⬜ Stage 1 — build the widget$' "$MB/checklist.md")" -eq 1 ]
}

@test "sync-v2: k/n recomputed after a flip, and the flip survives re-sync" {
  bash "$SYNC" "$PLAN" "$MB"
  # Simulate the flip mb-work-checkbox.sh mirrors into the checklist.
  python3 "$REPO_ROOT/scripts/mb-checklist-v2.py" flip --checklist "$MB/checklist.md" \
    --plan-basename 2026-09-01_feature_widgets.md --stage 1
  assert_grep -q '^## widget pipeline — 1/2$' "$MB/checklist.md"

  run bash "$SYNC" "$PLAN" "$MB"
  [ "$status" -eq 0 ]
  assert_grep -q '^## widget pipeline — 1/2$' "$MB/checklist.md"
  assert_grep -q '^- ✅ Stage 1 — build the widget$' "$MB/checklist.md"
}

@test "sync-v2: pre-existing v1 per-stage blocks fold into the plan's v2 block" {
  cat >> "$MB/checklist.md" <<'EOF'

<!-- mb-plan:2026-09-01_feature_widgets.md -->
## Stage 1: build the widget
- ✅ build the widget

<!-- mb-plan:2026-09-01_feature_widgets.md -->
## Stage 2: ship the widget
- ⬜ ship the widget
EOF

  run bash "$SYNC" "$PLAN" "$MB"
  [ "$status" -eq 0 ]

  [ "$(grep -c '^<!-- mb-plan:2026-09-01_feature_widgets.md -->$' "$MB/checklist.md")" -eq 1 ]
  assert_grep -q '^## widget pipeline — 1/2$' "$MB/checklist.md"
  assert_grep -q '^- ✅ Stage 1 — build the widget$' "$MB/checklist.md"
  assert_grep -q '^- ⬜ Stage 2 — ship the widget$' "$MB/checklist.md"
}
