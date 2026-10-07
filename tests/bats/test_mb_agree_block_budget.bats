#!/usr/bin/env bats
# Budget contract of the managed `## Active Agreements` block written by
# `mb-agree.sh sync` into CLAUDE.md / AGENTS.md: an index of short lines
# (first sentence, <=140 chars) capped at 4096 bytes, newest entries first
# to survive. Full text stays in agreements.md (SSOT).

load lib/assert

bats_require_minimum_version 1.5.0

MARKER_START='<!-- mb-agreements:start -->'
MARKER_END='<!-- mb-agreements:end -->'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-agree.sh"
  TMPROOT="$(mktemp -d)"
  PROJECT_ROOT="$TMPROOT/project"
  BANK="$PROJECT_ROOT/.memory-bank"
  mkdir -p "$BANK"
  export MB_PATH="$BANK"
  export MB_AGREEMENTS_PROJECT_ROOT="$PROJECT_ROOT"
  export MB_AGREEMENTS_LOCK_TIMEOUT=2
  unset MB_AGREEMENTS || true
}

teardown() {
  [ -n "${TMPROOT:-}" ] && rm -rf "$TMPROOT"
}

# Long statement with no sentence boundary: ~600 chars of words.
long_statement() {
  local n="$1" s="Decision $1"
  while [ "${#s}" -lt 600 ]; do s="$s word$n"; done
  printf '%s' "$s"
}

# Registry with Active entries 1..$1 (long statements).
write_registry() {
  local count="$1" i
  {
    printf '# Agreements\n\n## Active\n\n'
    for i in $(seq 1 "$count"); do
      printf -- '- AGR-%03d (2026-10-06, user-confirmed): %s\n' "$i" "$(long_statement "$i")"
    done
    printf '\n## Deferred\n\n## Open Questions\n\n## Archive\n'
  } > "$BANK/agreements.md"
}

# Managed block (markers included) of the given file.
block_of() {
  awk -v s="$MARKER_START" -v e="$MARKER_END" '
    $0==s{on=1} on{print} $0==e{on=0}' "$1"
}

@test "block budget: 60 long agreements -> block <=4096 bytes, newest kept, overflow line counts the rest" {
  write_registry 60
  run bash "$SCRIPT" sync
  [ "$status" -eq 0 ]

  local block; block="$(block_of "$PROJECT_ROOT/AGENTS.md")"
  [ "$(printf '%s\n' "$block" | wc -c)" -le 4096 ]

  local ids; ids="$(printf '%s\n' "$block" | grep -Eo '^- AGR-[0-9]{3}:' | grep -Eo '[0-9]{3}')"
  local n; n="$(printf '%s\n' "$ids" | grep -c .)"
  [ "$n" -ge 5 ]
  [ "$n" -lt 60 ]
  # Exactly the newest n IDs, oldest dropped.
  [ "$(printf '%s\n' "$ids" | sort -n | head -n1 | sed 's/^0*//')" -eq $((60 - n + 1)) ]
  [ "$(printf '%s\n' "$ids" | sort -n | tail -n1 | sed 's/^0*//')" -eq 60 ]
  refute_substring "$block" "AGR-001:"

  local k=$((60 - n))
  printf '%s\n' "$block" | grep -E "^- … ${k} more → /mb agree list" >/dev/null

  # Each rendered line is truncated: <=140 chars of statement plus an ellipsis.
  printf '%s\n' "$block" | grep -E '^- AGR-060: Decision 60 .*…$' >/dev/null
  printf '%s\n' "$block" | grep -F "agreements.md" >/dev/null
}

@test "block budget: statement shorter than 140 chars renders whole, without ellipsis" {
  run bash "$SCRIPT" add "Short decision that fits."
  [ "$status" -eq 0 ]
  grep -qxF -- "- AGR-001: Short decision that fits." "$PROJECT_ROOT/AGENTS.md"
  ! grep -qF "…" "$PROJECT_ROOT/AGENTS.md"
}

@test "block budget: long statement is cut at the first sentence end" {
  run bash "$SCRIPT" add "First sentence is the gist. Second sentence carries the rationale and should not be rendered in the index line at all, because the index only carries the gist of each decision."
  [ "$status" -eq 0 ]
  grep -qxF -- "- AGR-001: First sentence is the gist.…" "$PROJECT_ROOT/AGENTS.md"
}

@test "block budget: second sync is byte-identical" {
  write_registry 60
  run bash "$SCRIPT" sync
  [ "$status" -eq 0 ]
  local a; a="$(shasum -a 256 "$PROJECT_ROOT/AGENTS.md")"
  run bash "$SCRIPT" sync
  [ "$status" -eq 0 ]
  [ "$(shasum -a 256 "$PROJECT_ROOT/AGENTS.md")" = "$a" ]
}

@test "block budget: deferred and archived agreements are not rendered" {
  run bash "$SCRIPT" add "Keep me."
  run bash "$SCRIPT" add "Defer me."
  run bash "$SCRIPT" add "Replace me."
  run bash "$SCRIPT" defer 2
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" add "Replacement." --supersedes 3
  [ "$status" -eq 0 ]
  local block; block="$(block_of "$PROJECT_ROOT/AGENTS.md")"
  assert_substring "$block" "AGR-001: Keep me."
  assert_substring "$block" "AGR-004: Replacement."
  refute_substring "$block" "AGR-002"
  refute_substring "$block" "AGR-003"
  refute_substring "$block" "more → /mb agree list"
}
