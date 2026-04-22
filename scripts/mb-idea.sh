#!/usr/bin/env bash
# mb-idea.sh — capture a new idea in backlog.md with monotonic I-NNN.
#
# Usage:
#   mb-idea.sh <title> [priority] [mb_path]
#     priority ∈ HIGH|MED|LOW (default MED), case-insensitive.
#
# Effect: append `### I-NNN — <title> [PRIORITY, NEW, YYYY-MM-DD]` to the
# `## Ideas` section of backlog.md. Idempotent by title.
#
# Exit: 0 OK, 1 missing backlog.md, 2 invalid priority.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

TITLE="${1:?Usage: mb-idea.sh <title> [priority] [mb_path]}"
PRIO_RAW="${2:-}"
MB_PATH=$(mb_resolve_path "${3:-}")

BACKLOG="$MB_PATH/backlog.md"
[ -f "$BACKLOG" ] || { echo "[error] backlog.md not found: $BACKLOG" >&2; exit 1; }

# Normalize priority
if [ -z "$PRIO_RAW" ]; then
  PRIO="MED"
else
  PRIO=$(printf '%s' "$PRIO_RAW" | tr '[:lower:]' '[:upper:]')
fi
case "$PRIO" in
  HIGH|MED|LOW) ;;
  *) echo "[error] Invalid priority: $PRIO_RAW (expected HIGH|MED|LOW)" >&2; exit 2 ;;
esac

# Idempotency — same title already present?
if grep -qE "^### I-[0-9]{3} — ${TITLE} " "$BACKLOG" \
   || grep -qE "^### I-[0-9]{3} — ${TITLE}\$" "$BACKLOG" \
   || grep -qE "^### I-[0-9]{3} — ${TITLE} \[" "$BACKLOG"; then
  id=$(awk -v t="$TITLE" '
    $0 ~ ("^### I-[0-9]{3} — " t) {
      match($0, /I-[0-9]{3}/)
      print substr($0, RSTART, RLENGTH)
      exit
    }
  ' "$BACKLOG")
  echo "[idea] already present: $id — $TITLE" >&2
  printf '%s\n' "$id"
  exit 0
fi

# Find max existing I-NNN across entire file (grep-based, portable)
max_id=$(grep -Eo 'I-[0-9]{3}' "$BACKLOG" 2>/dev/null | awk -F- '{print $2+0}' | sort -n | tail -1 || true)
next=$(printf '%03d' $(( ${max_id:-0} + 1 )))

TODAY=$(date +%Y-%m-%d)
ID="I-${next}"
ENTRY="### ${ID} — ${TITLE} [${PRIO}, NEW, ${TODAY}]"

# Insert after `## Ideas` heading, before the next `## ` or EOF.
tmp=$(mktemp)
awk -v entry="$ENTRY" '
  BEGIN { inserted=0; in_ideas=0 }
  /^## Ideas[[:space:]]*$/ { print; in_ideas=1; next }
  in_ideas && /^## / && !/^## Ideas/ {
    print ""
    print entry
    print ""
    inserted=1
    in_ideas=0
    print
    next
  }
  { print }
  END {
    if (in_ideas && !inserted) {
      print ""
      print entry
    }
  }
' "$BACKLOG" > "$tmp"

# Guard: if `## Ideas` heading was missing, append a new section at EOF.
if ! grep -qE '^## Ideas[[:space:]]*$' "$BACKLOG"; then
  cp "$BACKLOG" "$tmp"
  {
    printf '\n## Ideas\n\n%s\n' "$ENTRY"
  } >> "$tmp"
fi

mv "$tmp" "$BACKLOG"
printf '%s\n' "$ID"
