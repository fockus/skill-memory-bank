#!/usr/bin/env bats
# I-132 — spawn discipline for the semantic layer.
# The OOM root cause was detached `( mb-semantic.py reindex … & )` spawns from
# SessionStart/SessionEnd: N closed sessions = N parallel model-loading
# indexers, unbounded and unkillable. The contract now is: lifecycle hooks only
# set a dirty marker; indexing happens inline in the next search, under a
# non-blocking flock. These are runnable invariants over the hook sources —
# they fail the moment anyone reintroduces a detached semantic spawn.

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "no hook or script detaches mb-semantic.py into the background" {
  run grep -nE 'mb-semantic\.py[^)]*&' \
    "$BIN/mb-session-start.sh" "$BIN/mb-session-summarize.sh" "$BIN/mb-semantic-recall.sh" \
    "$BIN/../scripts/mb-session-prune.sh"
  [ "$status" -ne 0 ]
}

@test "session-prune marks the index dirty instead of detaching prune" {
  run grep -F '.dirty' "$BIN/../scripts/mb-session-prune.sh"
  [ "$status" -eq 0 ]
}

@test "lifecycle dirty markers honor MB_INDEX_DIR" {
  run grep -F 'MB_INDEX_DIR' "$BIN/mb-session-start.sh"
  [ "$status" -eq 0 ]
  run grep -F 'MB_INDEX_DIR' "$BIN/mb-session-summarize.sh"
  [ "$status" -eq 0 ]
  run grep -F 'MB_INDEX_DIR' "$BIN/../scripts/mb-session-prune.sh"
  [ "$status" -eq 0 ]
}

@test "session-start marks the index dirty instead of reindexing" {
  run grep -F '.dirty' "$BIN/mb-session-start.sh"
  [ "$status" -eq 0 ]
}

@test "session-summarize marks the index dirty instead of reindexing" {
  run grep -F '.dirty' "$BIN/mb-session-summarize.sh"
  [ "$status" -eq 0 ]
}
