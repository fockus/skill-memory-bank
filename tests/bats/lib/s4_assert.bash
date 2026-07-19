#!/usr/bin/env bash
# Assertion helpers that actually fail the test they are written in.
#
# Why this file exists (R4-007/008/010). Bats runs a test body under `set -e`,
# but `! cmd` is explicitly EXEMPT from it: the shell treats a negated command
# as a tested condition, so its failure is swallowed. A negated assertion
# therefore only fails a test when it happens to be the LAST command in the
# body:
#
#     @test "x" { ! grep -q PRESENT f ; true }   → PASSES even though it is false
#     @test "y" { ! grep -q PRESENT f }          → fails correctly
#
# That made 9 "the user's prose survived" assertions in this zone decorative:
# an implementation that deleted the prose kept the suite green. The helpers
# below are plain commands whose failure propagates normally.
#
# The second trap is `[ "$before" = "$(cat f)" ]`: command substitution strips
# ALL trailing newlines, so a write that truncates the file's final newline
# compares equal. `assert_unchanged` uses `cmp -s` against a saved copy and is
# byte-exact.
#
# shellcheck shell=bash

# refute_grep <grep-args...> — the pattern must be ABSENT.
# Fails on a match (grep 0) AND on a grep error such as a mistyped path (grep 2),
# which the old `! grep` spelling silently accepted as "absent".
refute_grep() {
  local rc=0
  grep "$@" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ]
}

# assert_grep <grep-args...> — the pattern must be PRESENT.
assert_grep() {
  local rc=0
  grep "$@" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ]
}

# snapshot <file> <saved> — keep a byte-exact copy to compare against later.
snapshot() {
  cp "$1" "$2"
}

# assert_unchanged <file> <saved> — byte-identical, trailing newline included.
assert_unchanged() {
  if ! cmp -s "$1" "$2"; then
    {
      printf 'assert_unchanged: %s was modified\n' "$1"
      diff "$2" "$1" || true
    } >&2
    return 1
  fi
}

# refute_substring <haystack> <needle> — for `$output` checks. `[[ != ]]` is a
# plain command (not a negated one), so set -e sees its failure.
refute_substring() {
  [[ "$1" != *"$2"* ]]
}
