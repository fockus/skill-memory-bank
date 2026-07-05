#!/usr/bin/env bats
# Tests for scripts/mb-review-cache.sh:compute_touched_sha (reviewer-2.0 Task 1).
#
# Contract (design.md §5 "Hit/miss algorithm" step 2, §8 test_mb_review_sha):
#   touched_sha = sha256(
#       sorted(touched_files)
#       || for each path: sha256_of_file(path) if it exists else "DELETED:<path>"
#   )
#   - deterministic for the same input set
#   - reordering the input paths normalises to the identical sha (internal sort)
#   - a deleted/missing path is marked with a literal "DELETED:<path>" entry in
#     the canonical (pre-hash) representation, exposed via the `canonical`
#     subcommand for testability
#
# `sha` / `canonical` subcommands read newline-separated paths from stdin.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-review-cache.sh"
  WORKDIR="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORKDIR"
}

sha_of() {
  # $@ = paths (relative to $WORKDIR, resolved to absolute for stdin)
  local out=""
  local p
  for p in "$@"; do
    out="${out}${WORKDIR}/${p}
"
  done
  printf '%s' "$out" | bash "$RUN" sha
}

canonical_of() {
  local out=""
  local p
  for p in "$@"; do
    out="${out}${WORKDIR}/${p}
"
  done
  printf '%s' "$out" | bash "$RUN" canonical
}

@test "mb-review-cache.sh: script exists" {
  [ -f "$RUN" ]
}

@test "mb-review-cache.sh: --help exits 0 and mentions sha" {
  run bash "$RUN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"sha"* ]]
}

@test "compute_touched_sha: deterministic for identical input (two runs, same order)" {
  printf 'one\n' >"$WORKDIR/a.txt"
  printf 'two\n' >"$WORKDIR/b.txt"
  run sha_of a.txt b.txt
  first="$output"
  run sha_of a.txt b.txt
  second="$output"
  [ -n "$first" ]
  [ "$first" = "$second" ]
}

@test "compute_touched_sha: sha is prefixed sha256:" {
  printf 'one\n' >"$WORKDIR/a.txt"
  run sha_of a.txt
  [[ "$output" == sha256:* ]]
}

@test "compute_touched_sha: reordered inputs normalise to the same sha" {
  printf 'one\n' >"$WORKDIR/a.txt"
  printf 'two\n' >"$WORKDIR/b.txt"
  printf 'three\n' >"$WORKDIR/c.txt"
  run sha_of a.txt b.txt c.txt
  forward="$output"
  run sha_of c.txt a.txt b.txt
  reordered="$output"
  [ "$forward" = "$reordered" ]
}

@test "compute_touched_sha: changing a file's content changes the sha" {
  printf 'one\n' >"$WORKDIR/a.txt"
  run sha_of a.txt
  before="$output"
  printf 'one-changed\n' >"$WORKDIR/a.txt"
  run sha_of a.txt
  after="$output"
  [ "$before" != "$after" ]
}

@test "compute_touched_sha: deleted file yields a different sha than when present" {
  printf 'one\n' >"$WORKDIR/a.txt"
  run sha_of a.txt missing.txt
  with_missing="$output"
  printf 'placeholder\n' >"$WORKDIR/missing.txt"
  run sha_of a.txt missing.txt
  with_present="$output"
  [ "$with_missing" != "$with_present" ]
}

@test "compute_touched_sha: empty input set is deterministic" {
  run bash -c "printf '' | bash '$RUN' sha"
  [ "$status" -eq 0 ]
  first="$output"
  run bash -c "printf '' | bash '$RUN' sha"
  [ "$first" = "$output" ]
}

@test "canonical: a deleted path is marked DELETED:<path>" {
  run canonical_of missing.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELETED:${WORKDIR}/missing.txt"* ]]
}

@test "canonical: an existing path is marked with its own sha256, not DELETED" {
  printf 'one\n' >"$WORKDIR/a.txt"
  run canonical_of a.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"sha256:"* ]]
  [[ "$output" != *"DELETED:${WORKDIR}/a.txt"* ]]
}
