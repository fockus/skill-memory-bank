#!/usr/bin/env bats
# Tests for mb_next_backlog_id (scripts/_lib.sh) and its consumer mb-idea.sh —
# S4 Task 9 (design.md C6, C3 CLI). Red-anchor: names start with `backlog_id_alloc: `.

bats_require_minimum_version 1.5.0

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  IDEA="$REPO_ROOT/scripts/mb-idea.sh"
  TMPROOT="$(mktemp -d)"
  BANK="$TMPROOT/my bank/.memory-bank"
  mkdir -p "$BANK"
  printf '# Backlog\n\n## Ideas\n\n### I-074 — seeded [MED, NEW, 2026-04-01]\n\n## ADR\n' > "$BANK/backlog.md"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

alloc() {  # $1 = bank
  run --separate-stderr bash -c 'source "$1/scripts/_lib.sh"; mb_next_backlog_id "$2"' _ "$REPO_ROOT" "$1"
}

@test "backlog_id_alloc: I-079 collision — progress.md I-075 beats backlog max I-074" {
  printf '# Progress\n\n- I-075 implemented thing\n' > "$BANK/progress.md"
  alloc "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "I-076" ]
}

@test "backlog_id_alloc: prints exactly I-NNN plus newline" {
  run bash -c 'source "$1/scripts/_lib.sh"; mb_next_backlog_id "$2" | od -c | head -1' _ "$REPO_ROOT" "$BANK"
  [[ "$output" == *"I   -   0   7   5  \\n"* ]]
}

@test "backlog_id_alloc: progress-archive.md id is counted" {
  printf 'I-120 archived\n' > "$BANK/progress-archive.md"
  alloc "$BANK"
  [ "$output" = "I-121" ]
}

@test "backlog_id_alloc: index.json id is counted" {
  printf '{"items":["I-130"]}\n' > "$BANK/index.json"
  alloc "$BANK"
  [ "$output" = "I-131" ]
}

@test "backlog_id_alloc: ids quoted in status.md notes and .pre-migrate do not count" {
  printf 'see I-500\n' > "$BANK/status.md"
  mkdir -p "$BANK/notes" "$BANK/.pre-migrate/x" "$BANK/session/archive"
  printf 'I-600\n' > "$BANK/notes/n.md"
  printf 'I-700\n' > "$BANK/.pre-migrate/x/backlog.md"
  printf 'I-800\n' > "$BANK/session/archive/a.md"
  alloc "$BANK"
  [ "$output" = "I-075" ]
}

@test "backlog_id_alloc: unreadable optional source warns and succeeds" {
  mkdir "$BANK/progress-archive.md"
  alloc "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "I-075" ]
  [[ "$stderr" == *"[warn] backlog id scan: unreadable source"* ]]
}

@test "backlog_id_alloc: missing backlog.md exits 1 with empty stdout" {
  rm "$BANK/backlog.md"
  alloc "$BANK"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "backlog_id_alloc: unreadable required progress.md exits 1 without allocation" {
  mkdir "$BANK/progress.md"
  alloc "$BANK"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "backlog_id_alloc: max 999 exits 1 with empty stdout" {
  printf 'I-999\n' > "$BANK/progress.md"
  alloc "$BANK"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "backlog_id_alloc: mb-idea.sh allocates past a progress.md id" {
  printf 'I-075 done\n' > "$BANK/progress.md"
  run --separate-stderr bash "$IDEA" "Fresh idea" HIGH "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "I-076" ]
  grep -qE '^### I-076 — Fresh idea \[HIGH, NEW, [0-9-]{10}\]$' "$BANK/backlog.md"
}

@test "backlog_id_alloc: two parallel mb-idea.sh with different titles get distinct ids" {
  bash "$IDEA" "Alpha parallel" MED "$BANK" > "$TMPROOT/a.out" &
  p1=$!
  bash "$IDEA" "Beta parallel" MED "$BANK" > "$TMPROOT/b.out" &
  p2=$!
  wait "$p1"; wait "$p2"
  [ "$(cat "$TMPROOT/a.out")" != "$(cat "$TMPROOT/b.out")" ]
  grep -q 'Alpha parallel' "$BANK/backlog.md"
  grep -q 'Beta parallel' "$BANK/backlog.md"
  [ "$(grep -c '^### I-' "$BANK/backlog.md")" -eq 3 ]
}

@test "backlog_id_alloc: two parallel mb-idea.sh with the SAME title give one block and one id" {
  bash "$IDEA" "Same racing title" MED "$BANK" > "$TMPROOT/a.out" 2>/dev/null &
  p1=$!
  bash "$IDEA" "Same racing title" MED "$BANK" > "$TMPROOT/b.out" 2>/dev/null &
  p2=$!
  wait "$p1"; wait "$p2"
  [ "$(cat "$TMPROOT/a.out")" = "$(cat "$TMPROOT/b.out")" ]
  [ "$(grep -c 'Same racing title' "$BANK/backlog.md")" -eq 1 ]
}

@test "backlog_id_alloc: positional call stdout is byte-identical I-NNN and header grammar unchanged" {
  run --separate-stderr bash "$IDEA" "Positional title" low "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "I-075" ]
  grep -qE '^### I-075 — Positional title \[LOW, NEW, [0-9-]{10}\]$' "$BANK/backlog.md"
}

@test "backlog_id_alloc: --force first argument is accepted" {
  run --separate-stderr bash "$IDEA" --force "Forced title" MED "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "I-075" ]
}

@test "backlog_id_alloc: -- escape hatch allows a title starting with dashes" {
  run --separate-stderr bash "$IDEA" -- "--dashed title" MED "$BANK"
  [ "$status" -eq 0 ]
  grep -qF -- '— --dashed title [' "$BANK/backlog.md"
}

@test "backlog_id_alloc: unknown first --flag exits 2 before any mutation" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/snap"
  run --separate-stderr bash "$IDEA" --bogus "Title" MED "$BANK"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/snap"
}

@test "backlog_id_alloc: mb-idea.sh no longer carries its own grep allocator" {
  refute_grep -q "grep -Eo 'I-\[0-9\]{3}'" "$IDEA"
  grep -q 'mb_next_backlog_id' "$IDEA"
}
