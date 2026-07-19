#!/usr/bin/env bash
# Assertion helpers that actually fail the test they are written in.
#
# THE TRAP (I-147). Bats runs a test body under `set -e`, but `! cmd` is
# explicitly EXEMPT from it: POSIX treats a negated command as a tested
# condition, so its failure is swallowed. A negated assertion therefore only
# fails a test when it happens to be the LAST command in the body:
#
#     @test "x" { ! grep -q PRESENT f ; true }   → PASSES even though it is false
#     @test "y" { ! grep -q PRESENT f }          → fails correctly
#
# That made 73 "this must be absent" assertions across the suite decorative:
# an implementation that produced the forbidden output kept them green. Worse,
# a legitimately-last negation becomes hollow the moment anyone appends a line
# below it, so the correctness of the assertion depended on statement order.
#
# THE SECOND TRAP. `[ "$before" = "$(cat f)" ]` cannot see a lost trailing
# newline, because command substitution strips ALL trailing newlines from both
# sides. Use `snapshot` + `assert_unchanged` (byte-exact `cmp`) instead.
#
# Usage:  load lib/assert          (from tests/bats/*.bats)
#         load ../bats/lib/assert  (from tests/e2e/*.bats)
#
# Converting the shapes that occur in this repo:
#
#   ! grep -q X f                  -> refute_grep -q X f
#   ! echo "$output" | grep -q X   -> refute_substring "$output" X
#   ! printf '%s\n' "$x" | grep -q X -> refute_substring "$x" X
#   ! jq -e '...' f >/dev/null     -> refute_cmd jq -e '...' f
#   ! kill -0 "$pid" 2>/dev/null   -> refute_cmd kill -0 "$pid"
#   ! find D -name P | grep -q .   -> refute_cmd bash -c 'find D -name P | grep -q .'
#   ! [ -f f ] / ! [[ -e f ]]      -> refute_file f
#   ! [[ "$a" == *b* ]]            -> refute_substring "$a" b   (or just [[ != ]])
#   [ "$b" = "$(cat f)" ]          -> snapshot f SAVE ... assert_unchanged f SAVE
#
# A `!` that is genuinely the LAST command in a test is already correct and
# needs no change -- the contract test only rejects the hollow ones.
#
# shellcheck shell=bash

# refute_grep <grep-args...> — the pattern must be ABSENT.
#
# Fails on a match (grep 0) AND on a grep error such as a mistyped path or an
# unreadable file (grep 2). `! grep` accepted exit 2 as "absent", so a typo in
# the path silently turned the assertion into a no-op.
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

# refute_cmd <cmd...> — the command must FAIL (any non-zero status).
# For non-grep negations (`jq -e`, `test`, a script invocation) where the exact
# failing status is not part of the contract.
refute_cmd() {
  local rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ]
}

# refute_substring <haystack> <needle> — for `$output` checks. `[[ != ]]` is a
# plain command, not a negated one, so set -e sees its failure.
refute_substring() {
  [[ "$1" != *"$2"* ]]
}

# assert_substring <haystack> <needle>
assert_substring() {
  [[ "$1" == *"$2"* ]]
}

# refute_file <path> — the path must not exist (file, dir or dangling symlink).
refute_file() {
  [ ! -e "$1" ] && [ ! -L "$1" ]
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
