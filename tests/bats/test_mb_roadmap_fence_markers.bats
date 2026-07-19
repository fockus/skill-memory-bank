#!/usr/bin/env bats
# scripts/mb-roadmap-sync.sh — fence marker well-formedness (R4-011): a LONE
# opening or closing marker is ambiguous and must be refused without writing.
#
# Split out of test_mb_roadmap_sync_bootstrap.bats for the 400-line gate.
#
# Red-anchor: every test name starts with `roadmap_sync_bootstrap: `.

bats_require_minimum_version 1.5.0

load lib/s4_assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SYNC="$REPO_ROOT/scripts/mb-roadmap-sync.sh"
  GROUP="grp"
  TMPROOT="$(mktemp -d)"
  BANK="$TMPROOT/.memory-bank"
  mkdir -p "$BANK/plans" "$BANK/specs" "$BANK/context"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

mkspec() {
  local topic="$1" group="$2" ice="$3" blk="$4" conf="$5" status="$6" checked="${7:-0}" total="${8:-0}" dd="${9:-1}"
  local d="$BANK/specs/$topic"
  mkdir -p "$d"
  {
    printf '%s\n' '---'
    printf 'topic: %s\n' "$topic"
    printf 'group: %s\n' "$group"
    [ -n "$ice" ] && printf 'ice: %s\n' "$ice"
    [ -n "$conf" ] && printf 'ice_confirmed: %s\n' "$conf"
    printf 'blocked_by: [%s]\n' "$blk"
    printf 'status: %s\n' "$status"
    printf '%s\n' '---'
    printf '# Requirements: %s\n' "$topic"
  } > "$d/requirements.md"
  printf -- '---\ntopic: %s\ncreated: 2026-01-%02d\n---\n# ctx\n' "$topic" "$dd" > "$BANK/context/$topic.md"
  local i box
  : > "$d/tasks.md"
  printf '# Tasks\n\n' >> "$d/tasks.md"
  i=1
  while [ "$i" -le "$total" ]; do
    if [ "$i" -le "$checked" ]; then box="x"; else box=" "; fi
    printf -- '<!-- mb-task:%s -->\n## Task %s\n\n**DoD:**\n- [%s] item\n<!-- /mb-task:%s -->\n\n' "$i" "$i" "$box" "$i" >> "$d/tasks.md"
    i=$((i + 1))
  done
}

# R4-011: the suite covered reordered and duplicated markers but never a LONE
# one. An implementation that read "0 closing markers" as "no fence at all"
# would inject a brand-new pair right next to the user's ambiguous marker and
# still pass every other case here.

@test "roadmap_sync_bootstrap: a lone OPENING marker is rejected (exit 2, no write)" {
  printf -- '# Roadmap\n\n<!-- mb-roadmap-auto -->\nstray user text\n' > "$BANK/roadmap.md"
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  snapshot "$BANK/roadmap.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"malformed_fence"* ]]
  [[ "$stderr" == *"open=1"* ]]
  [[ "$stderr" == *"close=0"* ]]
  assert_unchanged "$BANK/roadmap.md" "$BATS_TEST_TMPDIR/before.snap"
}

@test "roadmap_sync_bootstrap: a lone CLOSING marker is rejected (exit 2, no write)" {
  printf -- '# Roadmap\n\n<!-- /mb-roadmap-auto -->\nstray user text\n' > "$BANK/roadmap.md"
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  snapshot "$BANK/roadmap.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"malformed_fence"* ]]
  [[ "$stderr" == *"open=0"* ]]
  [[ "$stderr" == *"close=1"* ]]
  assert_unchanged "$BANK/roadmap.md" "$BATS_TEST_TMPDIR/before.snap"
}

@test "roadmap_sync_bootstrap: --check on a lone OPENING marker exits 2, not 0" {
  printf -- '# Roadmap\n\n<!-- mb-roadmap-auto -->\nstray user text\n' > "$BANK/roadmap.md"
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  snapshot "$BANK/roadmap.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$SYNC" --check "$BANK"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"malformed_fence"* ]]
  assert_unchanged "$BANK/roadmap.md" "$BATS_TEST_TMPDIR/before.snap"
}

@test "roadmap_sync_bootstrap: --check on a lone CLOSING marker exits 2, not 0" {
  printf -- '# Roadmap\n\n<!-- /mb-roadmap-auto -->\nstray user text\n' > "$BANK/roadmap.md"
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  snapshot "$BANK/roadmap.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$SYNC" --check "$BANK"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"malformed_fence"* ]]
  assert_unchanged "$BANK/roadmap.md" "$BATS_TEST_TMPDIR/before.snap"
}

