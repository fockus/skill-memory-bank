#!/usr/bin/env bash
# mb-context.sh — собирает текущий контекст из Memory Bank.
#
# Usage:
#   mb-context.sh [mb_path]          # обычный контекст (core + plans + last note)
#   mb-context.sh --deep [mb_path]   # то же + полные codebase/ MD
#
# Default: .memory-bank/ в cwd (или external из .claude-workspace).
#
# Интеграция с mb-codebase-mapper:
#   Если .memory-bank/codebase/ существует с MD-файлами — добавляется
#   секция "Codebase summary" с 1-строчным summary каждого MD (default)
#   или полным содержимым (--deep).

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

DEEP=0
if [[ "${1:-}" == "--deep" ]]; then
  DEEP=1
  shift
fi

MB_PATH=$(mb_resolve_path "${1:-}")

if [[ ! -d "$MB_PATH" ]]; then
  echo "[MEMORY BANK: INACTIVE] Директория $MB_PATH не найдена"
  exit 0
fi

echo "=== [MEMORY BANK: ACTIVE] ==="
echo ""

# Core files
for file in STATUS.md plan.md checklist.md RESEARCH.md; do
  filepath="$MB_PATH/$file"
  if [[ -f "$filepath" ]]; then
    echo "--- $file ---"
    cat "$filepath"
    echo ""
  fi
done

# Активные планы (не в done/)
if [[ -d "$MB_PATH/plans" ]]; then
  active_plans=$(find "$MB_PATH/plans" -maxdepth 1 -name "*.md" -type f 2>/dev/null | sort -r | head -3)
  if [[ -n "$active_plans" ]]; then
    echo "--- Активные планы ---"
    while IFS= read -r plan; do
      echo "  - $(basename "$plan")"
    done <<< "$active_plans"
    echo ""
  fi
fi

# Codebase summary (от mb-codebase-mapper)
if [[ -d "$MB_PATH/codebase" ]]; then
  codebase_mds=$(find "$MB_PATH/codebase" -maxdepth 1 -name "*.md" -type f 2>/dev/null | sort)
  if [[ -n "$codebase_mds" ]]; then
    echo "--- Codebase summary ---"
    while IFS= read -r md; do
      name=$(basename "$md")
      if [[ "$DEEP" -eq 1 ]]; then
        echo ""
        echo "### $name"
        cat "$md"
      else
        # Первая не-пустая строка, не являющаяся markdown-заголовком
        summary=$(grep -vE '^(#|\s*$)' "$md" 2>/dev/null | head -1 || true)
        if [[ -n "$summary" ]]; then
          echo "  $name: $summary"
        else
          echo "  $name: (empty)"
        fi
      fi
    done <<< "$codebase_mds"
    echo ""
  fi
fi

# Последняя заметка
if [[ -d "$MB_PATH/notes" ]]; then
  latest_note=$(find "$MB_PATH/notes" -name "*.md" -type f 2>/dev/null | sort -r | head -1)
  if [[ -n "$latest_note" ]]; then
    echo "--- Последняя заметка: $(basename "$latest_note") ---"
    cat "$latest_note"
    echo ""
  fi
fi
