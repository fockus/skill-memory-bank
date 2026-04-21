#!/usr/bin/env bats
# Tests for v3.1 structural migration — checklist.md done-section removal.
#
# Contract (owned by mb-migrate-structure.sh):
#   --apply removes from checklist.md any `## Stage N: <name>` section where:
#     • ALL its items are ✅  AND
#     • A file plans/done/<basename>.md exists that references that stage/title
#     • The linked plan file in plans/done/ is older than MB_COMPACT_CHECKLIST_DAYS (default 30)
#   Sections with any ⬜ item MUST be preserved (safety).
#   --dry-run reports `checklist_sections_to_remove=N`.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  MIGRATE="$REPO_ROOT/scripts/mb-migrate-structure.sh"

  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/plans/done" "$MB/notes"
  : > "$MB/STATUS.md"
  : > "$MB/plan.md"
  : > "$MB/progress.md"
  : > "$MB/RESEARCH.md"
  : > "$MB/BACKLOG.md"

  # Done plan, 40 days old
  DONE_PLAN="$MB/plans/done/2026-03-01_feature_foo.md"
  cat > "$DONE_PLAN" <<'EOF'
# Plan: feature — foo

## Stages
<!-- mb-stage:1 -->
### Stage 1: first-task

done
EOF

  # Checklist with one fully-done stage section linked to that plan
  cat > "$MB/checklist.md" <<'EOF'
# Project — Checklist

## Stage 1: first-task
- ✅ item-a
- ✅ item-b

## Stage 2: still-active
- ⬜ not done
- ⬜ also not done
EOF

  # Bump done plan age
  set_mtime_days_ago "$DONE_PLAN" 40
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

set_mtime_days_ago() {
  local file="$1" days="$2" ts
  if ts=$(date -v-"${days}"d +"%Y%m%d%H%M" 2>/dev/null); then
    touch -t "$ts" "$file"
  else
    ts=$(date -d "$days days ago" +"%Y%m%d%H%M")
    touch -t "$ts" "$file"
  fi
}

@test "compact-checklist: dry-run reports checklist_sections_to_remove=1" {
  run bash "$MIGRATE" --dry-run "$MB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"checklist_sections_to_remove=1"* ]]
}

@test "compact-checklist: --apply removes fully-done linked section" {
  bash "$MIGRATE" --apply "$MB"

  ! grep -q '^## Stage 1: first-task' "$MB/checklist.md"
  ! grep -q '^- ✅ item-a' "$MB/checklist.md"
}

@test "compact-checklist: preserves section with any ⬜ item" {
  bash "$MIGRATE" --apply "$MB"
  grep -q '^## Stage 2: still-active' "$MB/checklist.md"
  grep -q 'not done' "$MB/checklist.md"
}

@test "compact-checklist: preserves fully-done section WITHOUT matching plans/done/ file" {
  # Add a fully-done section whose plan is NOT in plans/done/ — nothing to link → keep
  cat >> "$MB/checklist.md" <<'EOF'

## Stage 9: orphan-complete
- ✅ only-item
EOF

  bash "$MIGRATE" --apply "$MB"
  grep -q '^## Stage 9: orphan-complete' "$MB/checklist.md"
}

@test "compact-checklist: respects MB_COMPACT_CHECKLIST_DAYS env override" {
  # Set threshold to 100 → 40d plan does not qualify → no removal
  MB_COMPACT_CHECKLIST_DAYS=100 bash "$MIGRATE" --apply "$MB"
  grep -q '^## Stage 1: first-task' "$MB/checklist.md"
}

@test "compact-checklist: idempotent — rerunning --apply is no-op" {
  bash "$MIGRATE" --apply "$MB"
  sum1=$(shasum "$MB/checklist.md" | awk '{print $1}')
  bash "$MIGRATE" --apply "$MB"
  sum2=$(shasum "$MB/checklist.md" | awk '{print $1}')
  [ "$sum1" = "$sum2" ]
}
