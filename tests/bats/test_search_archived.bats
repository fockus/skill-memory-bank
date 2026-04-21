#!/usr/bin/env bats
# Tests for mb-search.sh --include-archived — notes/archive/ filtering.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SEARCH="$REPO_ROOT/scripts/mb-search.sh"
  INDEX_PY="$REPO_ROOT/scripts/mb-index-json.py"

  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/notes/archive"

  # Active note
  cat > "$MB/notes/active.md" <<EOF
---
type: note
tags: [active]
importance: medium
---

ARCHIVE_SEARCH_NEEDLE active.
EOF

  # Archived note with the same keyword
  cat > "$MB/notes/archive/old.md" <<EOF
---
type: note
tags: [archived-tag]
importance: low
---

ARCHIVE_SEARCH_NEEDLE from archive.
EOF

  python3 "$INDEX_PY" "$MB" >/dev/null 2>&1
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

run_search() {
  local raw
  raw=$(cd "$PROJECT" && bash "$SEARCH" "$@" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

@test "search default: does NOT find notes/archive/" {
  run_search ARCHIVE_SEARCH_NEEDLE
  [ "$status" -eq 0 ]
  [[ "$output" == *"notes/active.md"* ]]
  [[ "$output" != *"notes/archive/old.md"* ]]
}

@test "search --include-archived: finds both active and archived" {
  run_search --include-archived ARCHIVE_SEARCH_NEEDLE
  [ "$status" -eq 0 ]
  [[ "$output" == *"notes/active.md"* ]]
  [[ "$output" == *"notes/archive/old.md"* ]]
}

@test "search --tag default: does NOT find archived" {
  run_search --tag archived-tag
  [ "$status" -eq 0 ]
  [[ "$output" != *"notes/archive/old.md"* ]]
}

@test "search --include-archived --tag: finds archived" {
  run_search --include-archived --tag archived-tag
  [ "$status" -eq 0 ]
  [[ "$output" == *"notes/archive/old.md"* ]]
}
