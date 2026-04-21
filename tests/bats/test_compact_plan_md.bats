#!/usr/bin/env bats
# Tests for v3.1 /mb compact — legacy localized Deferred / Declined migration.
#
# Contract (extension to mb-compact.sh):
#   --apply on plan.md:
#     • For each bullet under the localized `Deferred` section → move to BACKLOG.md as
#       `### I-NNN — <text> [MED, DEFERRED, YYYY-MM-DD]`
#     • For each bullet under the localized `Declined` section → move as
#       `### I-NNN — <text> [LOW, DECLINED, YYYY-MM-DD]`
#     • Removes bullets from plan.md (empties the sections).
#   Also accepts English equivalents: "Deferred" / "Declined".
#   --dry-run reports `plan_md_ideas_to_migrate=N`.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  COMPACT="$REPO_ROOT/scripts/mb-compact.sh"

  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/plans/done" "$MB/notes"
  : > "$MB/STATUS.md"
  : > "$MB/progress.md"
  : > "$MB/RESEARCH.md"
  : > "$MB/checklist.md"

  cat > "$MB/BACKLOG.md" <<'EOF'
# Backlog

## Ideas

## ADR
EOF

  cat > "$MB/plan.md" <<'EOF'
# Project — Plan

## Current focus

Test.

## Active plans

<!-- mb-active-plans -->
<!-- /mb-active-plans -->

## Deferred

- Telemetry opt-in
- Remote backend sync

## Declined

- Auto-commit on save (YAGNI)
EOF
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

@test "compact-plan-md: dry-run reports plan_md_ideas_to_migrate=3" {
  run bash "$COMPACT" --dry-run "$MB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"plan_md_ideas_to_migrate=3"* ]]
}

@test "compact-plan-md: --apply moves Deferred bullets to BACKLOG as DEFERRED" {
  bash "$COMPACT" --apply "$MB"

  grep -qE '### I-00[0-9]+ — Telemetry opt-in \[MED, DEFERRED' "$MB/BACKLOG.md"
  grep -qE '### I-00[0-9]+ — Remote backend sync \[MED, DEFERRED' "$MB/BACKLOG.md"
}

@test "compact-plan-md: --apply moves Declined bullets as DECLINED" {
  bash "$COMPACT" --apply "$MB"
  grep -qE '### I-00[0-9]+ — Auto-commit on save \(YAGNI\) \[LOW, DECLINED' "$MB/BACKLOG.md"
}

@test "compact-plan-md: removes bullets from plan.md" {
  bash "$COMPACT" --apply "$MB"

  ! grep -q '^- Telemetry opt-in' "$MB/plan.md"
  ! grep -q '^- Remote backend sync' "$MB/plan.md"
  ! grep -q '^- Auto-commit on save' "$MB/plan.md"
}

@test "compact-plan-md: keeps section headings empty (for future additions)" {
  bash "$COMPACT" --apply "$MB"
  grep -q '^## Deferred' "$MB/plan.md"
  grep -q '^## Declined' "$MB/plan.md"
}

@test "compact-plan-md: legacy localized aliases also work" {
  cat > "$MB/plan.md" <<'EOF'
# Project — Plan

## __LOCALIZED_DEFERRED__

- Later thing

## __LOCALIZED_DECLINED__

- Never thing
EOF
  perl -0pi -e 's/__LOCALIZED_DEFERRED__/\x{041E}\x{0442}\x{043B}\x{043E}\x{0436}\x{0435}\x{043D}\x{043E}/g; s/__LOCALIZED_DECLINED__/\x{041E}\x{0442}\x{043A}\x{043B}\x{043E}\x{043D}\x{0435}\x{043D}\x{043E}/g' "$MB/plan.md"

  bash "$COMPACT" --apply "$MB"
  grep -qE '### I-00[0-9]+ — Later thing \[MED, DEFERRED' "$MB/BACKLOG.md"
  grep -qE '### I-00[0-9]+ — Never thing \[LOW, DECLINED' "$MB/BACKLOG.md"
}
