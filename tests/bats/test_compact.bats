#!/usr/bin/env bats
# Tests for scripts/mb-compact.sh — status-based compaction decay.
#
# Archival requires (age > threshold) AND (done-signal):
#   - done-signal for plans:
#       • file in plans/done/ — primary (already closed through mb-plan-done.sh)
#       • OR path mentioned in checklist.md on a line with ✅/[x]
#       • OR mentioned in progress.md/status.md as "done|closed|shipped"
#   - done-signal for notes: frontmatter importance: low + no active references
#
# Active plans (not done) are NOT touched even >180d → warning only.
#
# Output: key=value on stdout, reasoning per candidate.
# Exit: 0 success, 1 error.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  COMPACT="$REPO_ROOT/scripts/mb-compact.sh"

  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/notes" "$MB/plans/done" "$MB/reports"
  : > "$MB/status.md"
  : > "$MB/checklist.md"
  : > "$MB/roadmap.md"
  : > "$MB/progress.md"
  : > "$MB/lessons.md"
  : > "$MB/research.md"
  : > "$MB/backlog.md"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

# Run compact, capturing stdout/stderr and exit code.
run_compact() {
  local raw
  raw=$(cd "$PROJECT" && bash "$COMPACT" "$@" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

# Set mtime to N days ago (portable BSD/GNU touch -t).
set_mtime_days_ago() {
  local file="$1" days="$2"
  local ts
  # BSD date
  if ts=$(date -v-"${days}"d +"%Y%m%d%H%M" 2>/dev/null); then
    touch -t "$ts" "$file"
  else
    # GNU date
    ts=$(date -d "$days days ago" +"%Y%m%d%H%M")
    touch -t "$ts" "$file"
  fi
}

# ═══════════════════════════════════════════════════════════════
# Contract — smoke
# ═══════════════════════════════════════════════════════════════

@test "compact: empty bank → drift_candidates=0 exit 0" {
  run_compact --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"candidates=0"* ]] || [[ "$output" == *"0 plans"* ]]
}

@test "compact: --dry-run is default (no args)" {
  run_compact
  [ "$status" -eq 0 ]
  # No file changes
  [ ! -d "$MB/notes/archive" ]
}

# ═══════════════════════════════════════════════════════════════
# Plans — time threshold (60d default)
# ═══════════════════════════════════════════════════════════════

@test "compact: plan in plans/done/ <60d → do not touch (age too low)" {
  local p="$MB/plans/done/2026-03-15_feature_x.md"
  echo "# Plan X" > "$p"
  set_mtime_days_ago "$p" 30

  run_compact --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"plans/done/2026-03-15_feature_x.md"* ]] \
    || [[ "$output" == *"skip"*"2026-03-15"* ]]
}

@test "compact: plan in plans/done/ =61d → candidate for archival" {
  local p="$MB/plans/done/2026-02-18_feature_old.md"
  echo "# Plan Old" > "$p"
  set_mtime_days_ago "$p" 61

  run_compact --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-02-18_feature_old.md"* ]]
  [[ "$output" == *"archive"* ]] || [[ "$output" == *"candidate"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Plans — status-based safety (CRITICAL)
# ═══════════════════════════════════════════════════════════════

@test "compact: active plan in plans/ (not done) + >180d → do not touch" {
  local p="$MB/plans/2025-10-01_feature_active.md"
  echo "# Active Plan" > "$p"
  set_mtime_days_ago "$p" 200

  run_compact --dry-run
  [ "$status" -eq 0 ]
  # Not among archive candidates
  [[ "$output" != *"archive: plans/2025-10-01"* ]]
  # There should be a warning about an old active plan
  [[ "$output" == *"2025-10-01"* ]]
  [[ "$output" == *"active"*"old"* ]] \
    || [[ "$output" == *"warning"* ]] \
    || [[ "$output" == *"not done"* ]] \
    || [[ "$output" == *"not done"* ]]
}

@test "compact: plan marked ✅ in checklist.md + >60d → done-signal → archive" {
  local p="$MB/plans/2026-02-18_feature_done_checklist.md"
  echo "# Plan" > "$p"
  set_mtime_days_ago "$p" 70
  # ✅ signal in checklist
  cat > "$MB/checklist.md" <<EOF
## Stage 1: X
- ✅ Plan work completed: plans/2026-02-18_feature_done_checklist.md
EOF

  run_compact --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-02-18_feature_done_checklist.md"* ]]
  [[ "$output" == *"archive"* ]] || [[ "$output" == *"candidate"* ]]
}

@test "compact: plan marked ⬜ in checklist + >180d → do not touch (active)" {
  local p="$MB/plans/2025-09-01_feature_still_todo.md"
  echo "# Plan" > "$p"
  set_mtime_days_ago "$p" 230
  cat > "$MB/checklist.md" <<EOF
## Stage 1: Y
- ⬜ plans/2025-09-01_feature_still_todo.md — still in progress
EOF

  run_compact --dry-run
  [ "$status" -eq 0 ]
  # Do not archive
  [[ "$output" != *"archive: plans/2025-09-01"* ]]
}

@test "compact: plan mentioned in progress.md as 'done' + >60d → archive" {
  local p="$MB/plans/2026-02-10_feature_progress_done.md"
  echo "# Plan" > "$p"
  set_mtime_days_ago "$p" 75
  cat > "$MB/progress.md" <<EOF
## 2026-02-15

- Plan 2026-02-10_feature_progress_done.md done
EOF

  run_compact --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-02-10_feature_progress_done.md"* ]]
  [[ "$output" == *"archive"* ]] || [[ "$output" == *"candidate"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Notes — importance + age
# ═══════════════════════════════════════════════════════════════

@test "compact: low-importance note >90d → candidate" {
  local n="$MB/notes/2026-01-10_old_note.md"
  cat > "$n" <<EOF
---
type: note
importance: low
tags: [cleanup]
---
Old low-value note.
EOF
  set_mtime_days_ago "$n" 100

  run_compact --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-01-10_old_note.md"* ]]
  [[ "$output" == *"archive"* ]] || [[ "$output" == *"candidate"* ]]
}

@test "compact: medium-importance note >90d → untouched" {
  local n="$MB/notes/2026-01-10_medium.md"
  cat > "$n" <<EOF
---
type: note
importance: medium
tags: []
---
Medium note.
EOF
  set_mtime_days_ago "$n" 100

  run_compact --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"archive: notes/2026-01-10_medium"* ]]
}

@test "compact: low note <90d → untouched" {
  local n="$MB/notes/2026-04-01_recent_low.md"
  cat > "$n" <<EOF
---
type: note
importance: low
---
Recent low note.
EOF
  set_mtime_days_ago "$n" 20

  run_compact --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"archive: notes/2026-04-01"* ]]
}

@test "compact: low note >90d + referenced in roadmap.md → untouched (safety)" {
  local n="$MB/notes/2026-01-05_referenced.md"
  cat > "$n" <<EOF
---
type: note
importance: low
---
Referenced from plan.
EOF
  set_mtime_days_ago "$n" 120
  cat > "$MB/roadmap.md" <<EOF
# Plan
See also notes/2026-01-05_referenced.md
EOF

  run_compact --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"archive: notes/2026-01-05_referenced"* ]]
}

@test "compact: does not perform structural migration for checklist or roadmap.md" {
  local p="$MB/plans/done/2026-01-01_done.md"
  cat > "$p" <<'EOF'
# Done plan

## Stages
### Stage 1: legacy-stage
EOF
  set_mtime_days_ago "$p" 90

  cat > "$MB/checklist.md" <<'EOF'
## Stage 1: legacy-stage
- ✅ finished
EOF

  cat > "$MB/roadmap.md" <<'EOF'
## Deferred

- keep-this-for-migrate
EOF

  run_compact --apply
  [ "$status" -eq 0 ]
  grep -q '^## Stage 1: legacy-stage' "$MB/checklist.md"
  grep -q '^- keep-this-for-migrate' "$MB/roadmap.md"
}

# ═══════════════════════════════════════════════════════════════
# --apply mechanics
# ═══════════════════════════════════════════════════════════════

@test "compact: --apply moves plan to BACKLOG archive + deletes file" {
  local p="$MB/plans/done/2026-01-01_archive_me.md"
  cat > "$p" <<EOF
# Archive Me

Outcome: success.
EOF
  set_mtime_days_ago "$p" 120

  run_compact --apply
  [ "$status" -eq 0 ]
  # File removed
  [ ! -f "$p" ]
  # BACKLOG received a line
  grep -q "archive_me" "$MB/backlog.md"
  grep -q "Archived plans" "$MB/backlog.md"
}

@test "compact: --apply moves note to notes/archive/" {
  local n="$MB/notes/2026-01-02_archive_low.md"
  cat > "$n" <<EOF
---
type: note
importance: low
---
Archivable note body line.
EOF
  set_mtime_days_ago "$n" 120

  run_compact --apply
  [ "$status" -eq 0 ]
  [ ! -f "$n" ]
  [ -f "$MB/notes/archive/2026-01-02_archive_low.md" ]
}

@test "compact: --apply is idempotent (2 consecutive runs — 0 extra changes)" {
  local p="$MB/plans/done/2026-01-01_idem.md"
  echo "# Plan" > "$p"
  set_mtime_days_ago "$p" 80

  run_compact --apply
  [ "$status" -eq 0 ]

  local backlog_size1
  backlog_size1=$(wc -l < "$MB/backlog.md")

  run_compact --apply
  [ "$status" -eq 0 ]

  local backlog_size2
  backlog_size2=$(wc -l < "$MB/backlog.md")
  [ "$backlog_size1" -eq "$backlog_size2" ]
}

@test "compact: --apply updates .last-compact timestamp" {
  [ ! -f "$MB/.last-compact" ]
  run_compact --apply
  [ "$status" -eq 0 ]
  [ -f "$MB/.last-compact" ]
}

@test "compact: --dry-run does NOT create .last-compact" {
  run_compact --dry-run
  [ "$status" -eq 0 ]
  [ ! -f "$MB/.last-compact" ]
}

# ═══════════════════════════════════════════════════════════════
# Error handling
# ═══════════════════════════════════════════════════════════════

@test "compact: broken frontmatter note → skip with warning, does not block batch" {
  # Good note that should still be processed
  local good="$MB/notes/2026-01-01_good_low.md"
  cat > "$good" <<EOF
---
type: note
importance: low
---
Good note to archive.
EOF
  set_mtime_days_ago "$good" 100

  # Broken note: invalid frontmatter
  local bad="$MB/notes/2026-01-01_broken.md"
  cat > "$bad" <<EOF
---
type: [[[broken yaml
importance: low
---
Broken.
EOF
  set_mtime_days_ago "$bad" 100

  run_compact --dry-run
  [ "$status" -eq 0 ]
  # Good note made it into candidates
  [[ "$output" == *"2026-01-01_good_low.md"* ]]
}

@test "compact: missing .memory-bank/ → exit 1 with hint" {
  NOBANK="$(mktemp -d)"
  raw=$(cd "$NOBANK" && bash "$COMPACT" --dry-run 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
  [ "$status" -ne 0 ]
  [[ "$output" == *".memory-bank"* ]] || [[ "$output" == *"not found"* ]]
  rm -rf "$NOBANK"
}

@test "compact: unknown flag → exit 1 with usage" {
  run_compact --unknown-flag
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"unknown"* ]]
}
