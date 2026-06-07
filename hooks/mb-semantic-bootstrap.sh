#!/usr/bin/env bash
# mb-semantic-bootstrap.sh — create .venv and install fastembed+numpy (idempotent).
# Safe to run repeatedly; exits 0 if already present. Never required at query time.
set -u
HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
# venv sits beside the installed CLI/hooks (global ~/.claude/hooks/.venv, or a project
# bin/.venv). Override with MB_SEMANTIC_VENV. sc_semantic_py resolves the same precedence.
VENV="${MB_SEMANTIC_VENV:-$HOOK_DIR/.venv}"
PY="${PYTHON:-python3}"
if [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c 'import fastembed, numpy' >/dev/null 2>&1; then
  echo "mb-semantic venv ready"; exit 0
fi
command -v "$PY" >/dev/null 2>&1 || { echo "no python3"; exit 0; }
"$PY" -m venv "$VENV" 2>/dev/null || { echo "venv create failed"; exit 0; }
"$VENV/bin/python" -m pip install --quiet --upgrade pip >/dev/null 2>&1
if "$VENV/bin/python" -m pip install --quiet fastembed numpy >/dev/null 2>&1; then
  echo "mb-semantic deps installed"
else
  echo "deps install failed (semantic layer will fall back to lexical)"
fi
exit 0
