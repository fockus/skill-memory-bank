# Shared reader for the /mb command text: commands/mb.md plus references/mb/*.md.
# Usage in a bats test: load 'lib/mb_corpus'; mb_corpus > "$BATS_TEST_TMPDIR/mb.md"
mb_corpus() {
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  cat "$root/commands/mb.md" "$root"/references/mb/*.md
}
