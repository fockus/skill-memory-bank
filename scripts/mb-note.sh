#!/usr/bin/env bash
# mb-note.sh — create a note in Memory Bank.
# Usage: mb-note.sh <topic> [mb_path]
# Creates `notes/YYYY-MM-DD_HH-MM_<topic>.md`.
# On filename collision, adds suffix `_2`, `_3` instead of failing.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

TOPIC="${1:?Usage: mb-note.sh <topic> [mb_path]}"
MB_PATH=$(mb_resolve_path "${2:-}")
NOTES_DIR="$MB_PATH/notes"

SAFE_TOPIC=$(mb_sanitize_topic "$TOPIC")

if [[ -z "$SAFE_TOPIC" ]]; then
  echo "Topic contains only non-ASCII characters — cannot build a filename: $TOPIC" >&2
  exit 1
fi

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
FILENAME="${TIMESTAMP}_${SAFE_TOPIC}.md"
FILEPATH=$(mb_collision_safe_filename "$NOTES_DIR/$FILENAME")

mkdir -p "$NOTES_DIR"

DATE_NOW=$(date +"%Y-%m-%d %H:%M")
printf '# %s\nDate: %s\n' "$TOPIC" "$DATE_NOW" > "$FILEPATH"
cat >> "$FILEPATH" << 'EOF'

## What was done
-

## New knowledge
-
EOF

echo "$FILEPATH"
