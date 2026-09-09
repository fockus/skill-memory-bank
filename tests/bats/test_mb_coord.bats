#!/usr/bin/env bats
# mb-coord.sh — read the coordination board without loading 200 KB of it.
#
# Contract:
#   `active` prints only what a session must act on: active FREEZEs, HANDOVERs
#   with no matching ACK, the last N entries verbatim (default 3), and one
#   `board:` summary line. Entry type comes from the heading tag
#   (`## FREEZE · …` / `LIFT` / `HANDOVER` / `ACK` / `STATUS`); an untagged
#   entry is STATUS unless its body declares a freeze in a **bolded** marker
#   line, in which case it is reported as a legacy-detected freeze (a freeze
#   missed by the reader risks a destructive git op; one extra line does not).
#   Prose that merely mentions a freeze is not a declaration.
#   `append` writes a canonically tagged entry through a locked atomic append,
#   so what it writes is parseable by `active`.

load 'lib/assert'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-coord.sh"
  TMPDIR_T="$(mktemp -d)"
  BANK="$TMPDIR_T/bank/.memory-bank"
  mkdir -p "$BANK"
  BOARD="$BANK/COORDINATION.md"
}

teardown() {
  [ -n "${TMPDIR_T:-}" ] && rm -rf "$TMPDIR_T"
}

# pad <n> — filler entries appended after the fixture, so the `--tail` window
# is NOT the entries under test. Without them "is it in the FREEZE section?"
# and "is it in the verbatim tail?" are the same assertion.
pad() {
  local i=1
  while [ "$i" -le "$1" ]; do
    printf '\n## STATUS · 2026-09-09 · main · filler %s\nfiller body %s\n' "$i" "$i" >> "$BOARD"
    i=$((i + 1))
  done
}

@test "coord active: untagged legacy entries without a freeze marker are STATUS, never an active freeze" {
  cat > "$BOARD" <<'EOF'
# COORDINATION (append-only)

## 2026-07-15 — legacy plain entry
Prose body, no markers at all.

## 2026-07-15 — legacy prose mentioning a freeze
Despite the FREEZE REQUEST above, I ran a whole-tree `git stash`.
Работа велась AROUND the active adapter-parity FREEZE above.

## STATUS · 2026-09-06 · main · tagged status
Nothing frozen here.
EOF
  pad 3

  run bash "$SCRIPT" active --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" 'FREEZE (active): 0'
  refute_substring "$output" 'legacy prose mentioning a freeze'
  refute_substring "$output" 'legacy plain entry'
}

@test "coord active: untagged legacy entry with a bolded FREEZE marker is reported as a legacy freeze" {
  cat > "$BOARD" <<'EOF'
# COORDINATION (append-only)

## 2026-07-15 — adapter-parity governed execution (session 36e70e9c)
Running `/mb work adapter-parity`.

**⚠️ FREEZE REQUEST — do NOT `git rebase`, `git reset --hard`, `git checkout .`, or
whole-tree `git stash` on this working tree while adapter-parity T3–T8 are in flight.**

## STATUS · 2026-09-06 · main · unrelated
body
EOF
  pad 3

  run bash "$SCRIPT" active --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" 'FREEZE (active): 1'
  assert_substring "$output" 'legacy'
  assert_substring "$output" 'adapter-parity governed execution'
  assert_substring "$output" 'FREEZE REQUEST'
}

@test "coord active: FREEZE without LIFT is active; with a matching LIFT it is not" {
  cat > "$BOARD" <<'EOF'
# COORDINATION (append-only)

## FREEZE · 2026-09-06 · scripts/mb-work.sh
Signature in flight.

## FREEZE · 2026-09-06 · docs/mb-work.md
Rewriting the cost ladder.

## LIFT · 2026-09-06 · scripts/mb-work.sh
Signature published, edit freely.
EOF
  pad 3

  run bash "$SCRIPT" active --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" 'FREEZE (active): 1'
  assert_substring "$output" 'docs/mb-work.md'
  refute_substring "$output" 'FREEZE · 2026-09-06 · scripts/mb-work.sh'
}

@test "coord active: a LIFT written BEFORE its freeze does not cancel it" {
  cat > "$BOARD" <<'EOF'
# COORDINATION (append-only)

## LIFT · 2026-09-05 · scripts/mb-work.sh
Earlier episode closed.

## FREEZE · 2026-09-06 · scripts/mb-work.sh
New freeze, same scope, still in force.
EOF
  pad 3

  run bash "$SCRIPT" active --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" 'FREEZE (active): 1'
  assert_substring "$output" 'scripts/mb-work.sh'
}

@test "coord active: HANDOVER without ACK is reported; with a matching ACK it is not" {
  cat > "$BOARD" <<'EOF'
# COORDINATION (append-only)

## HANDOVER · 2026-09-06 · Stage 6 mb-coord
Handing Stage 6 over.

## HANDOVER · 2026-09-06 · Stage 7 core-cap
Handing Stage 7 over.

## ACK · 2026-09-06 · Stage 6 mb-coord
Received, picking it up.
EOF
  pad 3

  run bash "$SCRIPT" active --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" 'HANDOVER (no ACK): 1'
  assert_substring "$output" 'Stage 7 core-cap'
  refute_substring "$output" 'HANDOVER · 2026-09-06 · Stage 6 mb-coord'
}

@test "coord active: --tail 2 prints exactly the last two entries" {
  cat > "$BOARD" <<'EOF'
# COORDINATION (append-only)

## STATUS · 2026-09-01 · main · first
first body

## STATUS · 2026-09-02 · main · second
second body

## STATUS · 2026-09-03 · main · third
third body
EOF

  run bash "$SCRIPT" active --tail 2 --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" 'Last 2 entries'
  assert_substring "$output" 'second body'
  assert_substring "$output" 'third body'
  refute_substring "$output" 'first body'
}

@test "coord active: board summary line reports entry count, byte size and the full path" {
  cat > "$BOARD" <<'EOF'
# COORDINATION (append-only)

## STATUS · 2026-09-01 · main · one
a

## STATUS · 2026-09-02 · main · two
b
EOF
  size="$(wc -c < "$BOARD" | tr -d ' ')"

  run bash "$SCRIPT" active --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" "board: 2 entries, $size bytes"
  assert_substring "$output" "$BOARD"
}

@test "coord append: writes a tagged entry that active parses back" {
  printf '# COORDINATION (append-only)\n\n## STATUS · 2026-09-01 · main · seed\nseed body\n' > "$BOARD"
  printf 'Do not touch scripts/mb-coord.sh until Stage 6 lands.\n' > "$TMPDIR_T/body.md"

  run bash "$SCRIPT" append --type FREEZE --title 'scripts/mb-coord.sh' --body-file "$TMPDIR_T/body.md" --mb "$BANK"
  [ "$status" -eq 0 ]

  # Append-only: the seed entry survives untouched.
  assert_grep -qxF -e '## STATUS · 2026-09-01 · main · seed' "$BOARD"
  assert_grep -qF -e 'FREEZE · ' "$BOARD"

  run bash "$SCRIPT" active --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" 'FREEZE (active): 1'
  assert_substring "$output" 'scripts/mb-coord.sh'
  assert_substring "$output" 'Do not touch scripts/mb-coord.sh'
}

@test "coord append: a live foreign lock fails loudly and writes nothing" {
  printf '# COORDINATION (append-only)\n\n## STATUS · 2026-09-01 · main · seed\nseed body\n' > "$BOARD"
  snapshot "$BOARD" "$TMPDIR_T/board.before"

  mkdir -p "$BANK/.coord-append.lock"
  printf '%s' "99999-foreign" > "$BANK/.coord-append.lock/owner"

  MB_COORD_LOCK_TIMEOUT=1 run bash "$SCRIPT" append --type STATUS --title 'blocked write' --mb "$BANK"
  [ "$status" -ne 0 ]
  # It must fail BECAUSE of the lock — "command not found" also exits non-zero.
  assert_substring "$output" 'lock'
  assert_unchanged "$BOARD" "$TMPDIR_T/board.before"
}

@test "coord active: output on a 200 KB board stays under 4 KB" {
  {
    printf '# COORDINATION (append-only)\n\n'
    printf '## 2026-07-15 — legacy governed execution (session 36e70e9c)\n'
    printf 'Running a governed pipeline in this shared tree.\n\n'
    printf '**⚠️ FREEZE REQUEST — do NOT `git rebase`, `git reset --hard`, `git checkout .`.**\n\n'
    i=1
    while [ "$i" -le 400 ]; do
      printf '## STATUS · 2026-09-06 · main · synthetic entry %s\n' "$i"
      j=1
      while [ "$j" -le 6 ]; do
        printf 'Filler line %s of synthetic entry %s: scoped git add only, never -A, board read before commit.\n' "$j" "$i"
        j=$((j + 1))
      done
      printf '\n'
      i=$((i + 1))
    done
  } > "$BOARD"

  size="$(wc -c < "$BOARD" | tr -d ' ')"
  [ "$size" -ge 204800 ]

  run bash "$SCRIPT" active --mb "$BANK"
  [ "$status" -eq 0 ]
  out_bytes="$(printf '%s' "$output" | wc -c | tr -d ' ')"
  [ "$out_bytes" -lt 4096 ]
  # Cheap output is worthless if it drops the freeze that makes it necessary.
  assert_substring "$output" 'FREEZE (active): 1'
  assert_substring "$output" 'synthetic entry 400'
}

@test "coord active: missing board exits 0 with a 'no board' line" {
  run bash "$SCRIPT" active --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" 'no board'
  [ "${#lines[@]}" -eq 1 ]
}

@test "coord append: no --body-file, and no board yet — creates a headed board with the entry" {
  refute_file "$BOARD"

  run bash "$SCRIPT" append --type STATUS --title 'first ever entry' --mb "$BANK"
  [ "$status" -eq 0 ]

  assert_grep -qF -e '# COORDINATION (append-only)' "$BOARD"
  assert_grep -qF -e 'mb-coord.sh active' "$BOARD"
  assert_grep -qF -e 'STATUS · ' "$BOARD"
  assert_grep -qF -e 'first ever entry' "$BOARD"

  run bash "$SCRIPT" active --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" 'board: 1 entries'
  assert_substring "$output" 'first ever entry'
}
