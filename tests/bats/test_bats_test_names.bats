#!/usr/bin/env bats
# Guard (I-208 / Stage 1): bats mangles every @test NAME into a shell function
# identifier. A cyrillic letter in the name produces an identifier bats cannot
# look up again ("bats: unknown test name $'..._Унаследовано_..."), which aborts
# the whole file and silently drops the remaining tests — the file still reports
# a count, it just never runs them.
# Cyrillic inside test BODIES is fine and is frequently the subject under test.

@test "bats_test_names: no @test name carries cyrillic letters" {
  local repo_root
  repo_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

  # One pass over every file: the per-name form forked 3669 times (~17 s), the
  # 4000-name bash loop crashed bash on macOS runners (SIGTRAP), and a `[А-Яа-яЁё]`
  # range depends on the locale (C: a byte set that `→` falls into; GNU grep in
  # C.UTF-8: "Invalid collation character"). perl's \p{Cyrillic} depends on neither.
  local offenders rc
  shopt -s nullglob
  offenders="$(cd "$repo_root" && perl -CSD -ne 'print "$ARGV: $_" if /^\@test "[^"]*\p{Cyrillic}/' \
    tests/bats/*.bats tests/e2e/*.bats hooks/tests/*.bats)" && rc=0 || rc=$?
  # A guard that reports "clean" on its own failure guards nothing.
  if [ "$rc" -ne 0 ]; then
    printf 'the cyrillic scan itself failed (perl rc=%s) — refusing to report a clean run\n' "$rc"
    return 1
  fi

  if [ -n "$offenders" ]; then
    printf 'cyrillic letters in @test names (breaks bats name mangling):\n'
    printf '%s\n' "$offenders"
    return 1
  fi
}
