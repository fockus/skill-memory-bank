#!/usr/bin/env bats
# Stage 4 — mb-session-prune.sh: after --apply removes contentless stubs, fire a
# best-effort, backgrounded `mb-semantic.py prune` to drop index blocks whose source
# disappeared. Never blocks, never fails the prune (fail-open, exit 0 always).

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
  [[ "$output" == *"reindex=0"* ]]
  [ -f "$MB/session/2026-06-10_1000_aaaaaaaa.md" ]
}

@test "--apply still exits 0 and skips the trigger when no python is runnable" {
  # Pin the semantic interpreter to a non-existent path via MB_SEMANTIC_PY (honored by
  # sc_semantic_py). The prune block's `command -v "$PRUNE_PY"` guard then fails-open,
  # so the reindex is skipped — deterministic regardless of any local hooks/.venv, which
  # PATH-stripping alone cannot neutralize (sc_semantic_py resolves an absolute venv path).
  run env MB_SEMANTIC_PY="/nonexistent/python-does-not-exist" bash "$SCRIPT" --apply "$MB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reindex=0"* ]]
}
