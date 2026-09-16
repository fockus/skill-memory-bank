#!/usr/bin/env bats
# Stage 4 — mb-session-prune.sh: after --apply removes contentless stubs, mark the
# index dirty (`.index/.dirty`) so the next recall's inline catch-up drops index blocks
# whose source disappeared (I-132: no detached semantic processes). Never blocks, never
# fails the prune (fail-open, exit 0 always).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-session-prune.sh"
  TMP="$(mktemp -d)"
  MB="$TMP/.memory-bank"
  mkdir -p "$MB/session"
  _stub() {  # contentless
    cat > "$MB/session/$1" <<EOF
---
session_id: $1
summarized: false
---

## Live log
- 10:00 — User: "" · tools: (none) · files: (none) · ok
EOF
  }
  _stub "2026-06-10_1000_aaaaaaaa.md"
}
teardown() { rm -rf "$TMP"; }

@test "--apply with a stub invokes the semantic prune trigger" {
  run bash "$SCRIPT" --apply "$MB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reindex=1"* ]]
}

@test "dry-run never triggers the semantic prune" {
  run bash "$SCRIPT" "$MB"
  [ "$status" -eq 0 ]
  [ -f "$MB/session/2026-06-10_1000_aaaaaaaa.md" ]
  # Last position on purpose: a `[[ ]]` anywhere earlier in a bats body is
  # exempt from set -e and cannot fail the test (I-147 vacuity class). This
  # assertion stayed green through a mutation that made dry-run claim
  # reindex=1 until it was moved here.
  [[ "$output" == *"reindex=0"* ]]
}

@test "--apply still exits 0 and reports reindex=0 when the index dir is unusable" {
  # Point MB_INDEX_DIR (honored by the prune block) below a *regular file*, so both
  # `mkdir -p` and the `.dirty` write fail with ENOTDIR. Deterministic for any uid —
  # unlike a chmod-based denial, which root walks straight through. The dirty mark is
  # best-effort: the prune still succeeds, it just reports that nothing was marked.
  printf 'not a directory\n' > "$TMP/blocker"
  run env MB_INDEX_DIR="$TMP/blocker/index" bash "$SCRIPT" --apply "$MB"
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/blocker/index" ]
  # `[[ ]]` last on purpose: a failing `[[ ]]` mid-test does NOT abort under this
  # bash/bats, so a trailing assertion would swallow it (I-147 vacuity class).
  [[ "$output" == *"reindex=0"* ]]
}
