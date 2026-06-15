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

# ── Handoff capsule (handoff-v2 §4 "SessionStart consumption") ──
# If a handoff capsule exists AND it is newer than the most recent progress.md
# entry, PREPEND its body (truncated) ahead of everything above so the next
# session restores from a fresh capsule instead of stale progress. Otherwise
# the existing fallback context is used unchanged.
HANDOFF_LATEST="$MB/handoff/latest.md"
HANDOFF_CAP=1500
if [ -f "$HANDOFF_LATEST" ]; then
  # Portable mtime (epoch seconds) of the capsule — must be strictly numeric.
  # GNU `stat -f %m` interprets the format string as a FILE path and may print
  # '?' (exit 0) instead of an epoch, so we validate the result and fall through
  # to the GNU form when it is not a plain integer.
  capsule_mtime=""
  _bsd_mtime=$(stat -f %m "$HANDOFF_LATEST" 2>/dev/null || true)
  if printf '%s' "$_bsd_mtime" | grep -qE '^[0-9]+$'; then
    capsule_mtime="$_bsd_mtime"
  else
    _gnu_mtime=$(stat -c %Y "$HANDOFF_LATEST" 2>/dev/null || true)
    if printf '%s' "$_gnu_mtime" | grep -qE '^[0-9]+$'; then
      capsule_mtime="$_gnu_mtime"
    fi
  fi
  capsule_mtime="${capsule_mtime:-0}"

  # Epoch (UTC midnight) of the MOST RECENT `## YYYY-MM-DD` heading in
  # progress.md.  progress.md is OLDEST-FIRST (newest appended at the bottom),
  # so `head -1` returns the OLDEST date — wrong.  Sort all heading dates
  # lexicographically descending (`sort -r`) and take the first to get the MAX.
  # A heading may carry a trailing parenthetical, e.g. `## 2026-06-07 (topic)`.
  last_progress_epoch=0
  if [ -f "$MB/progress.md" ]; then
    last_date=$(grep -oE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$MB/progress.md" 2>/dev/null \
      | sed -E 's/^## //' | sort -r | head -1 || true)
    if [ -n "$last_date" ]; then
      # BSD date (-j -f) then GNU date (-d); fall back to 0 on parse failure.
      last_progress_epoch=$(date -u -j -f '%Y-%m-%d' "$last_date" +%s 2>/dev/null \
        || date -u -d "$last_date" +%s 2>/dev/null || echo 0)
    fi
  fi

  if [ "$capsule_mtime" -gt "$last_progress_epoch" ]; then
    capsule_body=$(head -c "$HANDOFF_CAP" "$HANDOFF_LATEST" 2>/dev/null || true)
    if [ -n "$capsule_body" ]; then
      CONTEXT="[MEMORY BANK: ACTIVE]\n\n## Handoff capsule (fresh — restored from PreCompact)\n${capsule_body}\n\n${CONTEXT#\[MEMORY BANK: ACTIVE\]\\n\\n}"
      echo "[mb] using fresh handoff capsule" >&2
    fi
  fi
fi

# Hard cap to avoid blowing the context window on large banks.
if [ "${#CONTEXT}" -gt 2500 ]; then
  CONTEXT="${CONTEXT:0:2500}"
fi

jq -n --arg ctx "$CONTEXT" '{additional_context: $ctx}'
