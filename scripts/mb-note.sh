#!/usr/bin/env bash
# mb-note.sh — создание заметки в Memory Bank.
# Usage: mb-note.sh <topic> [mb_path]
# Создаёт notes/YYYY-MM-DD_HH-MM_<topic>.md.
# При коллизии имени добавляет суффикс _2, _3 вместо падения.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

TOPIC="${1:?Usage: mb-note.sh <topic> [mb_path]}"
MB_PATH=$(mb_resolve_path "${2:-}")
NOTES_DIR="$MB_PATH/notes"

SAFE_TOPIC=$(mb_sanitize_topic "$TOPIC")

if [[ -z "$SAFE_TOPIC" ]]; then
  echo "Topic содержит только не-ASCII символы — не удаётся сформировать имя файла: $TOPIC" >&2
  exit 1
fi

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
FILENAME="${TIMESTAMP}_${SAFE_TOPIC}.md"
FILEPATH=$(mb_collision_safe_filename "$NOTES_DIR/$FILENAME")

mkdir -p "$NOTES_DIR"

DATE_NOW=$(date +"%Y-%m-%d %H:%M")
printf '# %s\nDate: %s\n' "$TOPIC" "$DATE_NOW" > "$FILEPATH"
cat >> "$FILEPATH" << 'EOF'

## Что сделано
-

## Новые знания
-
EOF

echo "$FILEPATH"
