#!/usr/bin/env bats
# mb_glossary: — svp-interview-upgrade C12 deterministic glossary upsert (Task 5).
# term/definition read from files; atomic write; conflict leaves the file
# byte-identical (REQ-018-compatible).
#
# Name convention: every @test starts with `mb_glossary: ` (Eval red-anchor).

bats_require_minimum_version 1.5.0
load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-glossary.sh"
  BANK="$BATS_TEST_TMPDIR/bank"; mkdir -p "$BANK"
  GLOSS="$BANK/glossary.md"
  TF="$BATS_TEST_TMPDIR/term.txt"
  DF="$BATS_TEST_TMPDIR/def.txt"
}

_upsert() {
  printf '%s' "$1" > "$TF"
  printf '%s' "$2" > "$DF"
  "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
}

@test "mb_glossary: the upsert script is present" {
  run assert_script_present scripts/mb-glossary.sh
  [ "$status" -eq 0 ]
}

@test "mb_glossary: first term → glossary=created and file has term — definition" {
  [ ! -e "$GLOSS" ]
  run --separate-stderr _upsert "slice" "a child spec of a group"
  [ "$status" -eq 0 ]
  [ "$output" = "glossary=created" ]
  [ -f "$GLOSS" ]
  grep -q '^slice — a child spec of a group$' "$GLOSS"
}

@test "mb_glossary: same term + same definition → glossary=unchanged, file untouched" {
  _upsert "slice" "a child spec of a group" >/dev/null
  local before; before="$(cat "$GLOSS")"
  run --separate-stderr _upsert "slice" "a child spec of a group"
  [ "$status" -eq 0 ]
  [ "$output" = "glossary=unchanged" ]
  [ "$(cat "$GLOSS")" = "$before" ]
}

@test "mb_glossary: same term + different definition → glossary=conflict exit 1, file byte-identical" {
  _upsert "slice" "a child spec of a group" >/dev/null
  local before; before="$(cat "$GLOSS")"
  run --separate-stderr _upsert "slice" "a plan stage"
  [ "$status" -eq 1 ]
  [ "$output" = "glossary=conflict" ]
  [ "$(cat "$GLOSS")" = "$before" ]
}

@test "mb_glossary: another term → glossary=updated (appended)" {
  _upsert "slice" "a child spec of a group" >/dev/null
  run --separate-stderr _upsert "frontier" "the set of unblocked questions"
  [ "$status" -eq 0 ]
  [ "$output" = "glossary=updated" ]
  grep -q '^slice — a child spec of a group$' "$GLOSS"
  grep -q '^frontier — the set of unblocked questions$' "$GLOSS"
}

@test "mb_glossary: bad subcommand → usage error exit 2" {
  printf 'x' > "$TF"; printf 'y' > "$DF"
  run --separate-stderr "$SCRIPT" frob --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
}

@test "mb_glossary: missing --definition-file → usage error exit 2" {
  printf 'x' > "$TF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
}

@test "mb_glossary: unreadable term file → usage error exit 2" {
  printf 'y' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$BATS_TEST_TMPDIR/nope.txt" --definition-file "$DF"
  [ "$status" -eq 2 ]
}

# ─── single-line contract guard (F7) ───

@test "mb_glossary: multiline term → usage error exit 2, nothing written" {
  [ ! -e "$GLOSS" ]
  printf 'alpha\nbeta' > "$TF"; printf 'a definition' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "error=usage" ]
  [ ! -e "$GLOSS" ]
}

@test "mb_glossary: multiline definition → usage error exit 2, existing file byte-identical" {
  _upsert "slice" "a child spec of a group" >/dev/null
  local before; before="$(cat "$GLOSS")"
  printf 'frontier' > "$TF"; printf 'first\nsecond' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
  [ "$(cat "$GLOSS")" = "$before" ]
}

@test "mb_glossary: empty term → usage error exit 2" {
  printf '' > "$TF"; printf 'a definition' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
}

@test "mb_glossary: whitespace-only definition → usage error exit 2" {
  printf 'slice' > "$TF"; printf '   ' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
}

@test "mb_glossary: separator inside the term → usage error exit 2 (ambiguous key)" {
  printf 'a — b' > "$TF"; printf 'a definition' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
}

# ─── raw CR/LF validated before normalization (cycle-2 major) ───

@test "mb_glossary: term with a trailing blank line (alpha\\n\\n) → usage exit 2, nothing written" {
  [ ! -e "$GLOSS" ]
  printf 'alpha\n\n' > "$TF"; printf 'a definition' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
  [ ! -e "$GLOSS" ]
}

@test "mb_glossary: definition with a trailing blank line → usage exit 2, existing file byte-identical" {
  _upsert "slice" "a child spec of a group" >/dev/null
  local before; before="$(cat "$GLOSS")"
  printf 'frontier' > "$TF"; printf 'the frontier\n\n' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ "$(cat "$GLOSS")" = "$before" ]
}

@test "mb_glossary: carriage return in the definition → usage exit 2" {
  printf 'slice' > "$TF"; printf 'de\rf' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
}

@test "mb_glossary: a single terminal newline is tolerated (created)" {
  [ ! -e "$GLOSS" ]
  printf 'slice\n' > "$TF"; printf 'a child spec\n' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 0 ]
  [ "$output" = "glossary=created" ]
  grep -q '^slice — a child spec$' "$GLOSS"
}

@test "mb_glossary: shellcheck (error severity) and bash -n clean" {
  run shellcheck -x -S error "$SCRIPT"
  [ "$status" -eq 0 ]
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}
