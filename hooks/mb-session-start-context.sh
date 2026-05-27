#!/usr/bin/env bash
# sessionStart hook: auto-inject Memory Bank context into Cursor system prompt.
#
# Cursor sessionStart may return:
#   {"additional_context": "..."}
#
# Fail-open: missing jq, missing workspace, missing .memory-bank/, or errors → {}

set -eu

if [ "${MB_AUTOLOAD_CONTEXT:-on}" = "off" ]; then
  echo '{}'
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

INPUT=$(cat || true)
WORKSPACE=$(printf '%s' "$INPUT" | jq -r '.workspace_roots[0] // empty' 2>/dev/null || true)
if [ -z "$WORKSPACE" ]; then
  echo '{}'
  exit 0
fi

HOOK_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
# shellcheck source=hooks/_skill_root.sh
. "$HOOK_DIR/_skill_root.sh"

MB=""
if hit="$(mb_hook_resolve_mb_path "$WORKSPACE" 2>/dev/null || true)" && [ -n "$hit" ]; then
  MB="$hit"
fi
if [ -z "$MB" ] || [ ! -d "$MB" ]; then
  echo '{}'
  exit 0
fi

CONTEXT="[MEMORY BANK: ACTIVE]\n\n"

if [ -f "$MB/status.md" ]; then
  CONTEXT+="## status.md\n$(head -30 "$MB/status.md")\n\n"
fi

if [ -f "$MB/checklist.md" ]; then
  unfinished=$(grep -E '^- \[ \]' "$MB/checklist.md" 2>/dev/null | head -10 || true)
  if [ -n "$unfinished" ]; then
    CONTEXT+="## checklist (unfinished)\n${unfinished}\n\n"
  fi
fi

if [ -f "$MB/roadmap.md" ]; then
  roadmap_hint=$(grep -E '^(## Now|## Next|_None\.)' "$MB/roadmap.md" 2>/dev/null | head -5 || true)
  if [ -n "$roadmap_hint" ]; then
    CONTEXT+="## roadmap\n${roadmap_hint}\n\n"
  fi
fi

# Hard cap to avoid blowing the context window on large banks.
if [ "${#CONTEXT}" -gt 2500 ]; then
  CONTEXT="${CONTEXT:0:2500}"
fi

jq -n --arg ctx "$CONTEXT" '{additional_context: $ctx}'
