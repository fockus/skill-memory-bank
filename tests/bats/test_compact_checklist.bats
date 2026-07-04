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
  : > "$MB/backlog.md"

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

# --- B3: opt-in SessionEnd checklist autoprune hook ---

AUTOPRUNE="$REPO_ROOT/hooks/mb-checklist-autoprune.sh"

_big_collapsible_checklist() {  # $1 = number of done sections
  { printf '# Checklist\n\n## ⏳ In flight\n- ⬜ keep this open TODO\n\n'
    local i
    for i in $(seq 1 "$1"); do
      printf '### Stage %s: task-%s\n' "$i" "$i"
      printf -- '- ✅ implemented part %s\n' "$i"
      printf -- '- ✅ Plan: [done-%s](plans/done/2026-01-01_feature_x_%s.md)\n\n' "$i" "$i"
    done
  } > "$MB/checklist.md"
}

@test "B3: autoprune runs when enabled AND over the 120-line cap" {
  AUTOPRUNE="$REPO_ROOT/hooks/mb-checklist-autoprune.sh"
  _big_collapsible_checklist 40           # ~168 lines, all collapsible
  before="$(wc -l < "$MB/checklist.md" | tr -d ' ')"
  [ "$before" -gt 120 ]
  run env MB_CHECKLIST_AUTOPRUNE=on CLAUDE_PROJECT_DIR="$PROJECT" bash "$AUTOPRUNE"
  [ "$status" -eq 0 ]
  after="$(wc -l < "$MB/checklist.md" | tr -d ' ')"
  [ "$after" -lt "$before" ]              # collapsed
  ls "$MB/.checklist.md.bak."* >/dev/null # backup written
  grep -q 'keep this open TODO' "$MB/checklist.md"   # In-flight preserved
}

@test "B3: autoprune is a no-op when disabled (default off)" {
  AUTOPRUNE="$REPO_ROOT/hooks/mb-checklist-autoprune.sh"
  _big_collapsible_checklist 40
  before="$(shasum "$MB/checklist.md" | awk '{print $1}')"
  run env -u MB_CHECKLIST_AUTOPRUNE CLAUDE_PROJECT_DIR="$PROJECT" bash "$AUTOPRUNE"
  [ "$status" -eq 0 ]
  after="$(shasum "$MB/checklist.md" | awk '{print $1}')"
  [ "$before" = "$after" ]
  if ls "$MB/.checklist.md.bak."* >/dev/null 2>&1; then false; fi
}

@test "B3: autoprune is a no-op when under the cap" {
  AUTOPRUNE="$REPO_ROOT/hooks/mb-checklist-autoprune.sh"
  _big_collapsible_checklist 3            # small, well under 120
  before="$(shasum "$MB/checklist.md" | awk '{print $1}')"
  run env MB_CHECKLIST_AUTOPRUNE=on CLAUDE_PROJECT_DIR="$PROJECT" bash "$AUTOPRUNE"
  [ "$status" -eq 0 ]
  after="$(shasum "$MB/checklist.md" | awk '{print $1}')"
  [ "$before" = "$after" ]
}

@test "B3: autoprune fail-safe when checklist is missing" {
  AUTOPRUNE="$REPO_ROOT/hooks/mb-checklist-autoprune.sh"
  rm -f "$MB/checklist.md"
  run env MB_CHECKLIST_AUTOPRUNE=on CLAUDE_PROJECT_DIR="$PROJECT" bash "$AUTOPRUNE"
  [ "$status" -eq 0 ]
}
