#!/usr/bin/env bats
# Sprint 1 Stage 5 — mb-plan-done.sh moves the plan's checklist block into
# progress.md instead of deleting it (AGR-043: information is never deleted).

load 'lib/assert'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SYNC="$REPO_ROOT/scripts/mb-plan-sync.sh"
  DONE="$REPO_ROOT/scripts/mb-plan-done.sh"
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
  printf '# Status\n\n<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n\n<!-- mb-recent-done -->\n<!-- /mb-recent-done -->\n' > "$MB/status.md"
  printf '# Progress\n' > "$MB/progress.md"

  bash "$SYNC" "$PLAN" "$MB" >/dev/null 2>&1
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

@test "done-v2: block moved to progress.md, not dropped" {
  assert_grep -q '^## widget pipeline — 0/2$' "$MB/checklist.md"

  run bash "$DONE" "$PLAN" "$MB"
  [ "$status" -eq 0 ]

  # Gone from the checklist…
  refute_grep -q 'mb-plan:2026-09-01_feature_widgets.md' "$MB/checklist.md"
  refute_grep -q 'widget pipeline' "$MB/checklist.md"

  # …and present verbatim in progress.md under a dated archive heading.
  assert_grep -q '^## \[checklist archive\] .* — 2026-09-01_feature_widgets.md$' "$MB/progress.md"
  assert_grep -q '^<!-- mb-plan:2026-09-01_feature_widgets.md -->$' "$MB/progress.md"
  assert_grep -q '^## widget pipeline — 0/2$' "$MB/progress.md"
  assert_grep -q '^- ⬜ Stage 1 — build the widget$' "$MB/progress.md"
  assert_grep -q '^- ⬜ Stage 2 — ship the widget$' "$MB/progress.md"
}

@test "done-v2: progress.md stays append-only (earlier content survives)" {
  printf '\n## Earlier entry\n\nkeep me\n' >> "$MB/progress.md"
  bash "$DONE" "$PLAN" "$MB"
  assert_grep -q '^# Progress$' "$MB/progress.md"
  assert_grep -q 'keep me' "$MB/progress.md"
}

@test "done-v2: another plan's block is untouched" {
  OTHER="$MB/plans/2026-09-02_fix_other.md"
  cat > "$OTHER" <<'EOF'
# Plan: fix — other thing

<!-- mb-stage:1 -->
### Stage 1: other step
EOF
  bash "$SYNC" "$OTHER" "$MB" >/dev/null 2>&1

  bash "$DONE" "$PLAN" "$MB"

  assert_grep -q '^<!-- mb-plan:2026-09-02_fix_other.md -->$' "$MB/checklist.md"
  assert_grep -q '^- ⬜ Stage 1 — other step$' "$MB/checklist.md"
}
