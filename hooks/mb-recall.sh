#!/usr/bin/env bash
# mb-recall.sh — lexical search over the Memory Bank session/ + notes/ (backs `/mb recall`).
# Usage: mb-recall.sh <query...>
set -u

HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
# shellcheck source=lib/session-common.sh
. "$HOOK_DIR/lib/session-common.sh"

QUERY="${*:-}"
if [ -z "$QUERY" ]; then
  echo "usage: mb-recall <query>"
  exit 0
fi

CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
MB="$(sc_resolve_mb "$CWD")"
if [ -z "$MB" ]; then
  echo "no Memory Bank found"
  exit 0
fi

targets=()
[ -d "$MB/session" ] && targets+=("$MB/session")
[ -d "$MB/notes" ] && targets+=("$MB/notes")
if [ "${#targets[@]}" -eq 0 ]; then
  echo "no session/ or notes/ to search"
  exit 0
fi

# semantic matches first (best-effort); lexical ripgrep always runs as fallback
LEX_HEADER=""
if [ "${MB_SEMANTIC:-auto}" != "off" ]; then
  PY="$(sc_semantic_py "$HOOK_DIR" "$MB")"
  if command -v "$PY" >/dev/null 2>&1; then
    SEM="$(MB_ROOT="$MB" "$PY" "$HOOK_DIR/mb-semantic.py" search "$QUERY" --top-k 5 --min-score 0.3 \
           --timeout "${MB_SEMANTIC_TIMEOUT:-5}" --json 2>/dev/null || true)"
    if [ -n "$SEM" ] && [ "$SEM" != "[]" ]; then
      echo "## Semantic matches"
      printf '%s' "$SEM" | "${JQ:-jq}" -r '.[] | "- ["+.kind+"] "+.source+" ("+(.score|tostring)+")\n  "+(.text|gsub("\n";" ")|.[0:200])' 2>/dev/null || true
      echo
      LEX_HEADER="## Lexical matches"
    fi
  fi
fi

RG="${RG:-rg}"
if command -v "$RG" >/dev/null 2>&1; then
  out="$("$RG" -n --color=never -i -- "$QUERY" "${targets[@]}" 2>/dev/null || true)"
else
  out="$(grep -rni -- "$QUERY" "${targets[@]}" 2>/dev/null || true)"
fi

[ -n "$LEX_HEADER" ] && echo "$LEX_HEADER"
if [ -n "$out" ]; then
  printf '%s\n' "$out"
else
  echo "no matches for: $QUERY"
fi
exit 0
