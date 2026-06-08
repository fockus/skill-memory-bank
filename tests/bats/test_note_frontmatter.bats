#!/usr/bin/env bats
# A1 — mb-note.sh must emit YAML frontmatter so index.json picks up
# type/tags/importance instead of empty tags / null importance.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-note.sh"
  TMP="$(mktemp -d)"
  MB="$TMP/.memory-bank"; mkdir -p "$MB/notes"
}
teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

@test "note starts with YAML frontmatter and required keys" {
  run bash "$SCRIPT" "my test topic" "$MB"
  [ "$status" -eq 0 ]
  f="$output"
  [ -f "$f" ]
  [ "$(head -1 "$f")" = "---" ]
  grep -qE '^type:[[:space:]]*note' "$f"
  grep -qE '^tags:' "$f"
  grep -qE '^importance:' "$f"
  grep -qE '^source:' "$f"
}

@test "frontmatter is closed before the heading" {
  run bash "$SCRIPT" "another topic" "$MB"
  [ "$status" -eq 0 ]
  # at least two '---' fences (open + close) and the title heading present
  [ "$(grep -c '^---$' "$output")" -ge 2 ]
  grep -qF '# another topic' "$output"
}

@test "collision suffix still works with frontmatter" {
  run bash "$SCRIPT" "dupe topic" "$MB"; f1="$output"
  run bash "$SCRIPT" "dupe topic" "$MB"; f2="$output"
  [ "$f1" != "$f2" ]
  [ "$(head -1 "$f2")" = "---" ]
}
