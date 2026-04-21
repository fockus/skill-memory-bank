#!/usr/bin/env bats
# Tests for mb-search.sh --tag filter (via index.json).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SEARCH="$REPO_ROOT/scripts/mb-search.sh"
  INDEX_BUILDER="$REPO_ROOT/scripts/mb-index-json.py"

  TMPBANK="$(mktemp -d)/.memory-bank"
  mkdir -p "$TMPBANK/notes"
  echo "# Lessons" > "$TMPBANK/lessons.md"
  # Core files (required by some scripts)
  : > "$TMPBANK/STATUS.md"
  : > "$TMPBANK/plan.md"
  : > "$TMPBANK/checklist.md"
}

teardown() {
  [ -n "${TMPBANK:-}" ] && [ -d "$(dirname "$TMPBANK")" ] && rm -rf "$(dirname "$TMPBANK")"
}

make_note() {
  local name="$1" tags="$2" body="$3"
  cat > "$TMPBANK/notes/$name" <<EOF
---
type: note
tags: [$tags]
importance: medium
---

$body
EOF
}

@test "search --tag: finds notes matching a tag" {
  make_note "auth.md" "auth, bug" "Auth fix description"
  make_note "perf.md" "perf" "Perf insight"
  python3 "$INDEX_BUILDER" "$TMPBANK" >/dev/null

  run bash "$SEARCH" --tag auth "$TMPBANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"auth.md"* ]]
  [[ "$output" != *"perf.md"* ]]
}

@test "search --tag: returns nothing for unused tag" {
  make_note "auth.md" "auth" "Something"
  python3 "$INDEX_BUILDER" "$TMPBANK" >/dev/null

  run bash "$SEARCH" --tag nonexistent "$TMPBANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing found"* ]]
}

@test "search --tag: auto-generates index.json if missing" {
  make_note "auth.md" "auth" "body"
  # no index.json yet
  [ ! -f "$TMPBANK/index.json" ]

  run bash "$SEARCH" --tag auth "$TMPBANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"auth.md"* ]]
  [ -f "$TMPBANK/index.json" ]
}

@test "search --tag: tag appearing in multiple notes returns all" {
  make_note "a.md" "common" "note A"
  make_note "b.md" "common, other" "note B"
  make_note "c.md" "other" "note C"
  python3 "$INDEX_BUILDER" "$TMPBANK" >/dev/null

  run bash "$SEARCH" --tag common "$TMPBANK"
  [[ "$output" == *"a.md"* ]]
  [[ "$output" == *"b.md"* ]]
  [[ "$output" != *"c.md"* ]]
}

@test "search: regular grep mode still works (no --tag)" {
  make_note "findme.md" "auth" "unique_search_marker_xyz"
  run bash "$SEARCH" "unique_search_marker_xyz" "$TMPBANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"findme.md"* || "$output" == *"unique_search_marker_xyz"* ]]
}
