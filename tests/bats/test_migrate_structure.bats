#!/usr/bin/env bats
# Tests for scripts/mb-migrate-structure.sh — one-shot v3.0 → v3.1 migrator.
#
# Contract:
#   Usage: mb-migrate-structure.sh [--dry-run|--apply] [mb_path]
#   --dry-run (default): report actions, 0 changes.
#   --apply: perform migration + create `.memory-bank/.pre-migrate/<timestamp>/` backup.
#   Detection:
#     • legacy if plan.md has `<!-- mb-active-plan -->` (singular) but NOT plural variant
#     • OR BACKLOG.md has raw `## Ideas` with `(пока нет)` / `(empty)` placeholder
#     • OR STATUS.md lacks `<!-- mb-active-plans -->` / `<!-- mb-recent-done -->` markers
#   Actions:
#     • Upgrade markers: `<!-- mb-active-plan -->` → `<!-- mb-active-plans -->` in plan.md + STATUS.md
#     • Add `<!-- mb-recent-done -->` block to STATUS.md if missing
#     • Restructure BACKLOG.md to skeleton with `## Ideas` + `## ADR` sections
#     • Remove done-stage sections from checklist.md referencing files in plans/done/ older than 30d
#   Idempotent: second --apply is no-op.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  MIGRATE="$REPO_ROOT/scripts/mb-migrate-structure.sh"
  FIXTURE="$REPO_ROOT/tests/fixtures/mb-legacy-v3-0"

  TMPROOT="$(mktemp -d)"
  TMPBANK="$TMPROOT/.memory-bank"

  # Copy legacy fixture to an isolated temp bank
  cp -R "$FIXTURE" "$TMPBANK"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

@test "migrate: script exists and is executable" {
  [ -f "$MIGRATE" ]
  [ -x "$MIGRATE" ]
}

@test "migrate: --dry-run default, no changes to files" {
  sum1=$(shasum "$TMPBANK/plan.md" "$TMPBANK/STATUS.md" "$TMPBANK/BACKLOG.md" | shasum)
  bash "$MIGRATE" "$TMPBANK"
  sum2=$(shasum "$TMPBANK/plan.md" "$TMPBANK/STATUS.md" "$TMPBANK/BACKLOG.md" | shasum)

  [ "$sum1" = "$sum2" ]
}

@test "migrate: --dry-run reports mutations without applying" {
  run bash "$MIGRATE" --dry-run "$TMPBANK"
  [ "$status" -eq 0 ]
  # Must mention the detected legacy markers
  [[ "$output" == *"mb-active-plans"* ]] || [[ "$output" == *"mb-active-plan"* ]]
  [[ "$output" == *"mb-recent-done"* ]] || [[ "$output" == *"BACKLOG"* ]]
}

@test "migrate: --apply creates .pre-migrate/ backup directory" {
  bash "$MIGRATE" --apply "$TMPBANK"

  # Backup directory with timestamp
  find "$TMPBANK/.pre-migrate" -maxdepth 2 -type f -name plan.md | grep -q .
  find "$TMPBANK/.pre-migrate" -maxdepth 2 -type f -name STATUS.md | grep -q .
  find "$TMPBANK/.pre-migrate" -maxdepth 2 -type f -name BACKLOG.md | grep -q .
}

@test "migrate: --apply upgrades plan.md single-marker to plural" {
  bash "$MIGRATE" --apply "$TMPBANK"
  grep -q '<!-- mb-active-plans -->' "$TMPBANK/plan.md"
  # Singular form must be gone
  ! grep -q '<!-- mb-active-plan -->' "$TMPBANK/plan.md"
  ! grep -q '<!-- /mb-active-plan -->' "$TMPBANK/plan.md"
}

@test "migrate: --apply adds mb-active-plans + mb-recent-done to STATUS.md" {
  bash "$MIGRATE" --apply "$TMPBANK"
  grep -q '<!-- mb-active-plans -->'  "$TMPBANK/STATUS.md"
  grep -q '<!-- /mb-active-plans -->' "$TMPBANK/STATUS.md"
  grep -q '<!-- mb-recent-done -->'   "$TMPBANK/STATUS.md"
  grep -q '<!-- /mb-recent-done -->'  "$TMPBANK/STATUS.md"
}

@test "migrate: --apply restructures BACKLOG.md to skeleton with Ideas + ADR sections" {
  bash "$MIGRATE" --apply "$TMPBANK"

  grep -qE '^## Ideas' "$TMPBANK/BACKLOG.md"
  grep -qE '^## ADR'   "$TMPBANK/BACKLOG.md"
  # placeholder "(пока нет)" should be removed
  ! grep -q 'пока нет' "$TMPBANK/BACKLOG.md"
}

@test "migrate: --apply is idempotent (second run no-op on already-migrated bank)" {
  bash "$MIGRATE" --apply "$TMPBANK"
  sum1=$(shasum "$TMPBANK/plan.md" "$TMPBANK/STATUS.md" "$TMPBANK/BACKLOG.md" "$TMPBANK/checklist.md" | shasum)

  bash "$MIGRATE" --apply "$TMPBANK"
  sum2=$(shasum "$TMPBANK/plan.md" "$TMPBANK/STATUS.md" "$TMPBANK/BACKLOG.md" "$TMPBANK/checklist.md" | shasum)

  [ "$sum1" = "$sum2" ]
}
