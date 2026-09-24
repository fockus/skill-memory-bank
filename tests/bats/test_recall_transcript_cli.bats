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

# --- sc_semantic_py: which python mb-recall.sh uses for semantic hits ----------
# Run from "$SKILL_DIR"/hooks there is no venv beside the hook dir; the global venv
# that mb-semantic-bootstrap.sh creates (~/.claude/hooks/.venv) must still be found.

_semantic_py() {  # <home> <hook_dir> <mb_root>
  env -u MB_SEMANTIC_PY HOME="$1" bash -c '. "$0/hooks/lib/session-common.sh"; sc_semantic_py "$1" "$2"' \
    "$REPO_ROOT" "$2" "$3"
}

_stub_py() { mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\n' > "$1"; chmod +x "$1"; }

@test "sc_semantic_py: falls back to the global ~/.claude/hooks venv when none sits beside the hook dir" {
  _stub_py "$TMP/home/.claude/hooks/.venv/bin/python"
  mkdir -p "$TMP/skill/hooks"
  out="$(_semantic_py "$TMP/home" "$TMP/skill/hooks" "$MB")"
  [ "$out" = "$TMP/home/.claude/hooks/.venv/bin/python" ]
}

@test "sc_semantic_py: venv beside the hook dir wins over the global venv" {
  _stub_py "$TMP/home/.claude/hooks/.venv/bin/python"
  _stub_py "$TMP/skill/hooks/.venv/bin/python"
  out="$(_semantic_py "$TMP/home" "$TMP/skill/hooks" "$MB")"
  [ "$out" = "$TMP/skill/hooks/.venv/bin/python" ]
}

@test "sc_semantic_py: MB_SEMANTIC_PY override wins over every venv" {
  _stub_py "$TMP/home/.claude/hooks/.venv/bin/python"
  out="$(HOME="$TMP/home" MB_SEMANTIC_PY=/pinned/python bash -c \
    '. "$0/hooks/lib/session-common.sh"; sc_semantic_py "$1" "$2"' "$REPO_ROOT" "$TMP/skill/hooks" "$MB")"
  [ "$out" = "/pinned/python" ]
}

@test "sc_semantic_py: no venv anywhere -> python3" {
  mkdir -p "$TMP/home" "$TMP/skill/hooks"
  out="$(_semantic_py "$TMP/home" "$TMP/skill/hooks" "$MB")"
  [ "$out" = "python3" ]
}
