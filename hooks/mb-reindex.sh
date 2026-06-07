#!/usr/bin/env bash
# mb-reindex.sh — (re)build the semantic index. Bootstraps the venv if needed.
# Usage: mb-reindex.sh [--full|--incremental]   (default: --full)
set -u
HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 1
MB="$(cd "$HOOK_DIR/.." 2>/dev/null && pwd)" || exit 1
MODE="${1:---full}"

bash "$HOOK_DIR/mb-semantic-bootstrap.sh"
PY="$MB/.venv/bin/python"; [ -x "$PY" ] || PY="python3"
command -v "$PY" >/dev/null 2>&1 || { echo "no python3 — cannot reindex"; exit 0; }

"$PY" "$MB/bin/mb-semantic.py" reindex "$MODE"
"$PY" "$MB/bin/mb-semantic.py" stats
exit 0
