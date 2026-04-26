#!/usr/bin/env bats
# Stage 6 — `mb-search.sh` must end its own flags before passing the query
# to rg/grep. Otherwise a query starting with `--` is parsed as an unknown
# flag by rg/grep instead of being treated as a search term.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SEARCH="$REPO_ROOT/scripts/mb-search.sh"
  TMP="$(mktemp -d)"
  MB="$TMP/.memory-bank"
  mkdir -p "$MB/notes"
  cat > "$MB/notes/sample.md" <<'EOF'
---
tags: [demo]
---
# Sample note
Mention of --no-config in the middle of a markdown file.
EOF
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

@test "mb-search: query starting with -- is not parsed as a flag" {
  # Must exit 0 (or print a 'Nothing found' message). Must NOT print
  # rg/grep's "unknown flag" / "unrecognized option" diagnostic.
  run bash "$SEARCH" -- "--no-config" "$MB"
  [ "$status" -eq 0 ]
  ! grep -qE "unknown flag|unrecognized option|invalid option" <<<"$output"
}

@test "mb-search: positional query starting with -- still works" {
  run bash "$SEARCH" "--no-config" "$MB"
  [ "$status" -eq 0 ]
  ! grep -qE "unknown flag|unrecognized option|invalid option" <<<"$output"
}
