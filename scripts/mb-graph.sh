#!/usr/bin/env bash
# mb-graph.sh — short front door to the Memory Bank code graph + code search.
#
#   mb-graph.sh who-calls|impact|tests <Symbol>   structural answer (mb-graph-query.py)
#   mb-graph.sh status                            graph freshness
#   mb-graph.sh search "<query>" [--source-only]  code search (mb-semantic-search.py)
#
# Thin by design: resolves the bank (walking up from a project subdirectory),
# then execs the real CLI. who-calls = `neighbors --direction in` (edges whose
# dst is the symbol itself = its callers). search: one token = exact name
# → bm25, a phrase → embeddings.
# Extra flags after the argument pass through (e.g. --json).
# Exit codes: the delegate's own (0 ok, 1 no match, 3 missing graph), 2 usage,
# 4 no Memory Bank found.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$HERE/_lib.sh"

usage() {
  echo "usage: mb-graph.sh who-calls|impact|tests <Symbol> | status | search \"<query>\" [flags]" >&2
  echo "  exit 4 = no Memory Bank found (set MB_PATH=<bank>)" >&2
  exit 2
}

cmd="${1:-}"
case "$cmd" in
  who-calls | impact | tests | search) [ -n "${2:-}" ] || usage ;;
  status) ;;
  *) usage ;;
esac
shift

# Nearest ancestor holding a bank marker becomes the project root.
if [ -z "${MB_PATH:-}" ]; then
  root="$PWD"
  while [ "$root" != "/" ] && [ ! -d "$root/.memory-bank" ] && [ ! -f "$root/.claude-workspace" ]; do
    root="$(dirname "$root")"
  done
  [ "$root" = "/" ] || cd "$root"
fi
MB="$(mb_resolve_path)"
MB="$(cd "$MB" 2>/dev/null && pwd)" || {
  echo "mb-graph.sh: no Memory Bank found from $PWD (global bank? run with MB_PATH=<bank>)" >&2
  exit 4
}
# src-root = the project the graph maps. A `.memory-bank` dir sits in its project
# (parent = root); a global bank (~/.claude/memory-bank/projects/<id>) does not,
# so fall back to the git repo we stand in.
if [ -z "${MB_PATH:-}" ]; then
  ROOT="$PWD"
elif [ "$(basename "$MB")" = ".memory-bank" ]; then
  ROOT="$(dirname "$MB")"
else
  ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
GRAPH="$MB/codebase/graph.json"
PY="${PYTHON:-python3}"

case "$cmd" in
  who-calls) exec "$PY" "$HERE/mb-graph-query.py" neighbors --graph "$GRAPH" --symbol "$1" --direction in "${@:2}" ;;
  impact | tests) exec "$PY" "$HERE/mb-graph-query.py" "$cmd" --graph "$GRAPH" --symbol "$1" "${@:2}" ;;
  status) exec "$PY" "$HERE/mb-graph-query.py" status --graph "$GRAPH" --src-root "$ROOT" "$@" ;;
  search)
    backend=embeddings
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_.]*$ ]] && backend=bm25
    exec "$PY" "$HERE/mb-semantic-search.py" "$1" --backend "$backend" "${@:2}" "$MB"
    ;;
esac
