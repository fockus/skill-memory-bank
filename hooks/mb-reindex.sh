#!/usr/bin/env bash
# mb-reindex.sh — (re)build the semantic index. Bootstraps the venv if needed.
# Usage: mb-reindex.sh [--full|--incremental]   (default: --full)
set -u
HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 1
# shellcheck source=lib/session-common.sh
. "$HOOK_DIR/lib/session-common.sh" 2>/dev/null || { echo "session-common.sh missing"; exit 1; }
MODE="${1:---full}"

# Index the current project's Memory Bank (resolved from CWD), not the CLI's own dir.
MB="$(sc_resolve_mb "${CLAUDE_PROJECT_DIR:-$PWD}")"
[ -n "$MB" ] || { echo "no Memory Bank found"; exit 0; }

bash "$HOOK_DIR/mb-semantic-bootstrap.sh"
PY="$(sc_semantic_py "$HOOK_DIR" "$MB")"
command -v "$PY" >/dev/null 2>&1 || { echo "no python3 — cannot reindex"; exit 0; }

MB_ROOT="$MB" "$PY" "$HOOK_DIR/mb-semantic.py" reindex "$MODE"
MB_ROOT="$MB" "$PY" "$HOOK_DIR/mb-semantic.py" stats
exit 0
