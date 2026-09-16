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

  # Collect every name once, then match once. One grep over the whole list, not
  # one grep per name: the per-name form forked 3669 times and cost ~17 s.
  local names="" f name
  shopt -s nullglob
  for f in "$repo_root"/tests/bats/*.bats \
           "$repo_root"/tests/e2e/*.bats \
           "$repo_root"/hooks/tests/*.bats; do
    while IFS= read -r name; do
      names+="  ${f#"$repo_root"/}: ${name}"$'\n'
    done < <(sed -nE 's/^@test "(.*)" \{.*/\1/p' "$f")
  done

  # C.UTF-8, not C: under a byte-wise locale `[А-Яа-яЁё]` expands to a byte set
  # that `→` (E2 86 92) falls into, reddening 600+ innocent names.
  local offenders rc
  offenders="$(printf '%s' "$names" | LC_ALL=C.UTF-8 grep -E '[А-Яа-яЁё]')" && rc=0 || rc=$?
  # rc 0 = found, 1 = none, anything else = grep itself failed. A guard that
  # reports "clean" on its own failure guards nothing.
  if [ "$rc" -gt 1 ]; then
    printf 'the cyrillic scan itself failed (grep rc=%s) — refusing to report a clean run\n' "$rc"
    return 1
  fi

  if [ -n "$offenders" ]; then
    printf 'cyrillic letters in @test names (breaks bats name mangling):\n'
    printf '%s\n' "$offenders"
    return 1
  fi
}
