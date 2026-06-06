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

RG="${RG:-rg}"
if command -v "$RG" >/dev/null 2>&1; then
  out="$("$RG" -n --color=never -i -- "$QUERY" "${targets[@]}" 2>/dev/null || true)"
else
  out="$(grep -rni -- "$QUERY" "${targets[@]}" 2>/dev/null || true)"
fi

if [ -n "$out" ]; then
  printf '%s\n' "$out"
else
  echo "no matches for: $QUERY"
fi
exit 0
