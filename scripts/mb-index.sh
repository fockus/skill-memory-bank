#!/usr/bin/env bash
# mb-index.sh — реестр записей Memory Bank.
# Usage: mb-index.sh [mb_path]

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

MB_PATH=$(mb_resolve_path "${1:-}")

if [[ ! -d "$MB_PATH" ]]; then
  echo "[MEMORY BANK: INACTIVE] Директория $MB_PATH не найдена" >&2
  exit 1
fi

# Кроссплатформенная дата модификации
file_mod_date() {
  if stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$1" 2>/dev/null; then
    return
  fi
  stat -c "%y" "$1" 2>/dev/null | cut -d. -f1
}

echo "=== Memory Bank Index ==="
echo ""

# Core files
echo "## Core"
for file in STATUS.md plan.md checklist.md RESEARCH.md BACKLOG.md progress.md lessons.md; do
  filepath="$MB_PATH/$file"
  if [[ -f "$filepath" ]]; then
    mod_date=$(file_mod_date "$filepath")
    lines=$(wc -l < "$filepath" | tr -d ' ')
    echo "  $file ($lines строк, $mod_date)"
  fi
done
echo ""

# Notes
if [[ -d "$MB_PATH/notes" ]]; then
  count=$(find "$MB_PATH/notes" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
  echo "## Notes ($count)"
  find "$MB_PATH/notes" -name "*.md" -type f 2>/dev/null | sort -r | while IFS= read -r f; do
    echo "  $(basename "$f")"
  done
  echo ""
fi

# Plans
if [[ -d "$MB_PATH/plans" ]]; then
  active=$(find "$MB_PATH/plans" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
  done_count=0
  [[ -d "$MB_PATH/plans/done" ]] && done_count=$(find "$MB_PATH/plans/done" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
  echo "## Plans (active: $active, done: $done_count)"
  find "$MB_PATH/plans" -maxdepth 1 -name "*.md" -type f 2>/dev/null | sort -r | while IFS= read -r f; do
    echo "  [active] $(basename "$f")"
  done
  if [[ -d "$MB_PATH/plans/done" ]]; then
    find "$MB_PATH/plans/done" -name "*.md" -type f 2>/dev/null | sort -r | while IFS= read -r f; do
      echo "  [done]   $(basename "$f")"
    done
  fi
  echo ""
fi

# Experiments
if [[ -d "$MB_PATH/experiments" ]]; then
  count=$(find "$MB_PATH/experiments" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
  echo "## Experiments ($count)"
  find "$MB_PATH/experiments" -name "*.md" -type f 2>/dev/null | sort | while IFS= read -r f; do
    echo "  $(basename "$f")"
  done
  echo ""
fi

# Reports
if [[ -d "$MB_PATH/reports" ]]; then
  count=$(find "$MB_PATH/reports" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$count" -gt 0 ]]; then
    echo "## Reports ($count)"
    find "$MB_PATH/reports" -name "*.md" -type f 2>/dev/null | sort -r | while IFS= read -r f; do
      echo "  $(basename "$f")"
    done
    echo ""
  fi
fi
