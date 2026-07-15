#!/usr/bin/env bats
# Tests for scripts/mb-openspec.sh — thin dispatcher (T4: import|sync|list|status).
#
# Contract (design.md, tasks.md T4 — Covers REQ-001, REQ-015, REQ-019):
#   Usage: mb-openspec.sh <import|sync|list|status> [args...]
#   - `import` forwards to `mb-openspec.py import` unchanged.
#   - `list` enumerates `openspec/changes/*` (skip `changes/archive/**` unless
#     `--all`, OQ-3) with import status: not-imported / imported / drifted.
#   - `status <topic>` reports the same status for one imported topic.
#   - `sync [<topic>]` re-imports only when the source hash changed (REQ-015);
#     hash match -> no-op, no topic -> sync all imported topics.
#   - Unknown subcommand -> usage error, exit != 0.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DISPATCH="$REPO_ROOT/scripts/mb-openspec.sh"

  TMPROOT="$(mktemp -d)"
  BANK="$TMPROOT/.memory-bank"
  mkdir -p "$BANK"

  OPENSPEC_ROOT="$TMPROOT/proj"
  mkdir -p "$OPENSPEC_ROOT"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# ═══════════════════════════════════════════════════════════════
# Fixture helpers
# ═══════════════════════════════════════════════════════════════

_write_change() {
  # $1 = change id, $2 = requirement body line (varies to change the hash)
  local id="$1" body="$2"
  local dir="$OPENSPEC_ROOT/openspec/changes/$id"
  mkdir -p "$dir/specs/demo"
  cat > "$dir/proposal.md" <<EOF
## Why

Demo change $id.

## What Changes

- Demo.
EOF
  cat > "$dir/specs/demo/spec.md" <<EOF
## ADDED Requirements

### Requirement: Demo Widget

The system SHALL $body.

#### Scenario: happy path

- WHEN a widget is requested
- THEN it is returned
EOF
  cat > "$dir/tasks.md" <<'EOF'
## 1. Build

- [ ] 1.1 Implement the widget
EOF
}

_write_archived_change() {
  local id="$1"
  local dir="$OPENSPEC_ROOT/openspec/changes/archive/$id"
  mkdir -p "$dir/specs/demo"
  cat > "$dir/proposal.md" <<EOF
## Why

Archived demo change $id.

## What Changes

- Demo.
EOF
  cat > "$dir/specs/demo/spec.md" <<EOF
## ADDED Requirements

### Requirement: Archived Widget

The system SHALL do archived things.
EOF
  cat > "$dir/tasks.md" <<'EOF'
## 1. Build

- [ ] 1.1 Do archived thing
EOF
}

_import() {
  # $1 = change id, $2 = topic
  python3 "$REPO_ROOT/scripts/mb-openspec.py" import \
    "$OPENSPEC_ROOT/openspec/changes/$1" --as "$2" --mb "$BANK"
}

# ═══════════════════════════════════════════════════════════════
# Dispatcher basics
# ═══════════════════════════════════════════════════════════════

@test "mb-openspec.sh: script exists and is executable" {
  [ -f "$DISPATCH" ]
  [ -x "$DISPATCH" ]
}

@test "mb-openspec.sh: unknown subcommand -> usage error, exit != 0" {
  run bash "$DISPATCH" bogus-subcommand
  [ "$status" -ne 0 ]
  [[ "$output" == *"sage"* ]]  # "Usage"/"usage" — tolerant of exact casing
}

@test "mb-openspec.sh: no subcommand -> usage error, exit != 0" {
  run bash "$DISPATCH"
  [ "$status" -ne 0 ]
}

@test "mb-openspec.sh: import forwards to mb-openspec.py import" {
  _write_change "add-widget" "cache widgets"
  run bash "$DISPATCH" import "$OPENSPEC_ROOT/openspec/changes/add-widget" \
    --as widget-topic --mb "$BANK"
  [ "$status" -eq 0 ]
  [ -f "$BANK/specs/widget-topic/requirements.md" ]
}

# ═══════════════════════════════════════════════════════════════
# list
# ═══════════════════════════════════════════════════════════════

@test "list: not-imported change is reported as not-imported" {
  _write_change "add-widget" "cache widgets"

  run bash "$DISPATCH" list --openspec "$OPENSPEC_ROOT" --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"add-widget"* ]]
  [[ "$output" == *"not-imported"* ]]
}

@test "list: imported change with matching hash is reported as imported" {
  _write_change "add-widget" "cache widgets"
  _import "add-widget" "widget-topic"

  run bash "$DISPATCH" list --openspec "$OPENSPEC_ROOT" --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"add-widget"* ]]
  [[ "$output" == *"imported"* ]]
  [[ "$output" != *"drifted"* ]]
}

@test "list: imported change whose source changed is reported as drifted" {
  _write_change "add-widget" "cache widgets"
  _import "add-widget" "widget-topic"

  # Mutate the OpenSpec source after import -> hash no longer matches.
  _write_change "add-widget" "cache widgets aggressively"

  run bash "$DISPATCH" list --openspec "$OPENSPEC_ROOT" --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"add-widget"* ]]
  [[ "$output" == *"drifted"* ]]
}

@test "list: archived changes are hidden by default" {
  _write_change "add-widget" "cache widgets"
  _write_archived_change "old-widget"

  run bash "$DISPATCH" list --openspec "$OPENSPEC_ROOT" --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"add-widget"* ]]
  [[ "$output" != *"old-widget"* ]]
}

@test "list: --all includes archived changes" {
  _write_change "add-widget" "cache widgets"
  _write_archived_change "old-widget"

  run bash "$DISPATCH" list --all --openspec "$OPENSPEC_ROOT" --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"add-widget"* ]]
  [[ "$output" == *"old-widget"* ]]
}

# ═══════════════════════════════════════════════════════════════
# status
# ═══════════════════════════════════════════════════════════════

@test "status: reports imported when hash matches" {
  _write_change "add-widget" "cache widgets"
  _import "add-widget" "widget-topic"

  run bash "$DISPATCH" status widget-topic --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"imported"* ]]
  [[ "$output" != *"drifted"* ]]
}

@test "status: reports drifted after the source changes" {
  _write_change "add-widget" "cache widgets"
  _import "add-widget" "widget-topic"
  _write_change "add-widget" "cache widgets aggressively"

  run bash "$DISPATCH" status widget-topic --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"drifted"* ]]
}

@test "status: unknown topic -> non-zero exit" {
  run bash "$DISPATCH" status no-such-topic --mb "$BANK"
  [ "$status" -ne 0 ]
}

# ═══════════════════════════════════════════════════════════════
# sync
# ═══════════════════════════════════════════════════════════════

@test "sync: is a no-op when the stored hash matches the source" {
  _write_change "add-widget" "cache widgets"
  _import "add-widget" "widget-topic"

  before_req="$(cat "$BANK/specs/widget-topic/requirements.md")"
  before_design="$(cat "$BANK/specs/widget-topic/design.md")"
  before_tasks="$(cat "$BANK/specs/widget-topic/tasks.md")"

  run bash "$DISPATCH" sync widget-topic --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]

  after_req="$(cat "$BANK/specs/widget-topic/requirements.md")"
  after_design="$(cat "$BANK/specs/widget-topic/design.md")"
  after_tasks="$(cat "$BANK/specs/widget-topic/tasks.md")"

  [ "$before_req" = "$after_req" ]
  [ "$before_design" = "$after_design" ]
  [ "$before_tasks" = "$after_tasks" ]
}

@test "sync: re-imports when the source file changed" {
  _write_change "add-widget" "cache widgets"
  _import "add-widget" "widget-topic"

  _write_change "add-widget" "cache widgets aggressively"

  run bash "$DISPATCH" sync widget-topic --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"re-import"* ]] || [[ "$output" == *"synced"* ]]

  grep -q "cache widgets aggressively" "$BANK/specs/widget-topic/requirements.md"
}

@test "sync: with no topic syncs all imported topics" {
  _write_change "add-widget" "cache widgets"
  _import "add-widget" "widget-topic"

  _write_change "add-widget" "cache widgets aggressively"

  run bash "$DISPATCH" sync --mb "$BANK"
  [ "$status" -eq 0 ]
  grep -q "cache widgets aggressively" "$BANK/specs/widget-topic/requirements.md"
}
