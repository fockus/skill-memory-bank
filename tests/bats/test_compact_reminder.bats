#!/usr/bin/env bats
# Tests for hooks/mb-compact-reminder.sh — weekly /mb compact prompt at SessionEnd.
#
# Contract:
#   - Reads JSON input from stdin (standard Claude Code hook protocol)
#   - If .memory-bank/ missing → silent exit 0
#   - If .memory-bank/.last-compact missing → silent exit 0 (opt-in)
#   - If .last-compact mtime < 7d → silent exit 0
#   - If .last-compact ≥7d AND /mb compact --dry-run shows candidates > 0 →
#     reminder on stderr
#   - If MB_COMPACT_REMIND=off → noop (env opt-out)
#   - Read-only: 0 file changes

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/mb-compact-reminder.sh"

  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/notes" "$MB/plans/done"
  for n in STATUS plan checklist progress lessons RESEARCH BACKLOG; do
    : > "$MB/$n.md"
  done
  # Stub jq usage: hook reads .cwd from JSON
  JSON_INPUT="{\"cwd\":\"$PROJECT\",\"session_id\":\"test-s\"}"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

# Invoke hook with given env + stdin, capture stdout/stderr/status
run_hook() {
  local raw
  raw=$(printf '%s' "$JSON_INPUT" | env "$@" bash "$HOOK" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

# Set mtime to N days ago on a file (portable BSD/GNU)
age_days() {
  local file="$1" days="$2" ts
  if ts=$(date -v-"${days}"d +"%Y%m%d%H%M" 2>/dev/null); then
    touch -t "$ts" "$file"
  else
    ts=$(date -d "$days days ago" +"%Y%m%d%H%M")
    touch -t "$ts" "$file"
  fi
}

make_compact_candidate() {
  # Add aged done plan so /mb compact --dry-run returns candidates > 0
  local plan="$MB/plans/done/2025-11-01_old.md"
  echo "# Old" > "$plan"
  age_days "$plan" 90
}

# ═══════════════════════════════════════════════════════════════

@test "reminder: no .memory-bank → silent exit 0" {
  rm -rf "$MB"
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "reminder: missing .last-compact → silent (opt-in)" {
  make_compact_candidate
  # .last-compact is NOT created
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" != *"compact"* ]] || [[ "$output" != *"ready"* ]]
}

@test "reminder: fresh .last-compact (<7d) → silent" {
  make_compact_candidate
  touch "$MB/.last-compact"   # fresh
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" != *"compact"* ]] || [[ "$output" != *"ready"* ]]
}

@test "reminder: stale .last-compact (>7d) + 0 candidates → silent" {
  # No aged plans/notes → candidates=0
  touch "$MB/.last-compact"
  age_days "$MB/.last-compact" 10
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" != *"ready for compact"* ]]
}

@test "reminder: stale .last-compact + candidates > 0 → stderr reminder" {
  make_compact_candidate
  touch "$MB/.last-compact"
  age_days "$MB/.last-compact" 10
  run_hook
  [ "$status" -eq 0 ]
  # Expect a reminder — mention of "compact" and the number of candidates
  [[ "$output" == *"compact"* ]]
}

@test "reminder: MB_COMPACT_REMIND=off → full noop" {
  make_compact_candidate
  touch "$MB/.last-compact"
  age_days "$MB/.last-compact" 10
  run_hook MB_COMPACT_REMIND=off
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "reminder: read-only — does not create files in .memory-bank/" {
  make_compact_candidate
  touch "$MB/.last-compact"
  age_days "$MB/.last-compact" 10

  # Snapshot of the file list before
  local before_files
  before_files=$(find "$MB" -type f | sort)

  run_hook

  local after_files
  after_files=$(find "$MB" -type f | sort)
  [ "$before_files" = "$after_files" ]
}
