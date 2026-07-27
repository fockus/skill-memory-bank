#!/usr/bin/env bats
# brief_docs: — svp-brief C4, routing and documentation (Task 4).
#
# Structural assertions on whole lines and whole sections, never on the presence
# of the isolated word "brief" (R2-003): the word occurs all over these files, so
# a grep for it would stay green against a router that dispatches nowhere.
#
# Name convention (X-05, Eval red-anchor): every @test starts with `brief_docs: `.

bats_require_minimum_version 1.5.0
load 'lib/assert'
load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  MBMD="$REPO_ROOT/commands/mb.md"
  BRIEFMD="$REPO_ROOT/commands/brief.md"
  README="$REPO_ROOT/README.md"
  CLAUDEMD="$REPO_ROOT/CLAUDE.md"
  STAGE='brief → discuss → sdd → work'
}

# routing_table — the § Routing block of commands/mb.md, nothing else.
routing_table() {
  awk '/^### Routing/{f=1; next} f && /^---/{exit} f' "$MBMD"
}

@test "brief_docs: router-row — exactly one routing row dispatches to commands/brief.md" {
  local hits
  hits="$(routing_table | grep -cE '^\| *`?brief <topic>`?[^|]*\|.*commands/brief\.md.*\|$' || true)"
  # A comment, or a row without the dispatch target, does not satisfy this.
  [ "$hits" -eq 1 ]
}

@test "brief_docs: router-synopsis — the ### brief block carries the C0 synopsis" {
  local block
  block="$(mb_section "$MBMD" 'brief.*')"
  assert_substring "$block" '/mb brief <topic>'
  assert_substring "$block" '--request'
  assert_substring "$block" '--request-file'
  assert_substring "$block" '--input'
  assert_substring "$block" '--auto'
}

@test "brief_docs: router-synopsis — the block marks --input as repeatable" {
  local block
  block="$(mb_section "$MBMD" 'brief.*')"
  # `[--input <path>]…` — the ellipsis is what makes it repeatable rather than
  # a single optional source.
  assert_grep -qE -e '\[--input <path>\](…|\.\.\.)' <(printf '%s\n' "$block")
}

@test "brief_docs: pipeline-stage — README.md carries the stage" {
  assert_grep -qF -e "$STAGE" "$README"
}

@test "brief_docs: pipeline-stage — CLAUDE.md carries the stage" {
  assert_grep -qF -e "$STAGE" "$CLAUDEMD"
}

@test "brief_docs: no-update-flag — commands/mb.md never mentions --update" {
  refute_grep -qF -e '--update' "$MBMD"
}

@test "brief_docs: no-update-flag — commands/brief.md never mentions --update" {
  # The flag does not exist in MVP (BRIEF-003); documenting it, even to deny it,
  # is how a reader learns to try it.
  refute_grep -qF -e '--update' "$BRIEFMD"
}
