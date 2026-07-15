#!/usr/bin/env bats
# Session-memory-graph-hardening follow-up — shell-level regression coverage for
# `hooks/mb-recall.sh --transcript <uuid> [--context N]`. The Python `window()`
# helper (hooks/lib/transcript_window.py) already has unit tests; this file covers
# the shell wiring: arg parsing, transcript-path resolution from session
# frontmatter, and exit codes.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/hooks/mb-recall.sh"
  TMP="$(mktemp -d)"
  PROJECT="$TMP/project"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/session"

  JSONL="$TMP/transcript.jsonl"
  cat > "$JSONL" <<'EOF'
{"uuid":"u1","type":"user","message":{"role":"user","content":"hello one"}}
{"uuid":"u2","type":"assistant","message":{"role":"assistant","content":"hello two"}}
{"uuid":"u3","type":"user","message":{"role":"user","content":"hello three"}}
{"uuid":"u4","type":"assistant","message":{"role":"assistant","content":"hello four"}}
{"uuid":"u5","type":"user","message":{"role":"user","content":"hello five"}}
EOF

  cat > "$MB/session/2026-07-15_0000_aaaaaaaa.md" <<EOF
---
session_id: aaaaaaaa
transcript: $JSONL
summarized: false
---

## Live log
- 00:00 — User: "hello" · tools: (none) · files: (none) · ok
EOF

  # Pin the semantic interpreter to the repo venv (Python 3.11) for determinism.
  export MB_SEMANTIC_PY="$REPO_ROOT/.venv/bin/python"
  export CLAUDE_PROJECT_DIR="$PROJECT"
}

teardown() {
  rm -rf "$TMP"
}

@test "--transcript with a known uuid exits 0 and prints the target turn" {
  run bash "$SCRIPT" --transcript u3 --context 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello three"* ]]
}

@test "--transcript with an unknown uuid exits 3" {
  run bash "$SCRIPT" --transcript nope
  [ "$status" -eq 3 ]
}

@test "--context N returns only the +/-N window around the uuid" {
  run bash "$SCRIPT" --transcript u3 --context 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello two"* ]]
  [[ "$output" == *"hello four"* ]]
  [[ "$output" != *"hello one"* ]]
  [[ "$output" != *"hello five"* ]]
}
