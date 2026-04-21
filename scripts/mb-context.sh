#!/usr/bin/env bash
# mb-context.sh — collects current context from Memory Bank.
#
# Usage:
#   mb-context.sh [mb_path]          # standard context (core + plans + last note)
#   mb-context.sh --deep [mb_path]   # same + full `codebase/` Markdown docs
#
# Default: `.memory-bank/` in CWD (or external storage from `.claude-workspace`).
#
# Integration with `mb-codebase-mapper`:
#   If `.memory-bank/codebase/` exists with Markdown files, add a
#   "Codebase summary" section with a one-line summary for each doc (default)
#   or the full contents (`--deep`).

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
  echo "[MEMORY BANK: INACTIVE] Directory $MB_PATH not found"
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

# Active plans (not in `done/`)
if [[ -d "$MB_PATH/plans" ]]; then
  active_plans=$(find "$MB_PATH/plans" -maxdepth 1 -name "*.md" -type f 2>/dev/null | sort -r | head -3)
  if [[ -n "$active_plans" ]]; then
    echo "--- Active plans ---"
    while IFS= read -r plan; do
      echo "  - $(basename "$plan")"
    done <<< "$active_plans"
    echo ""
  fi
fi

# Codebase summary (from `mb-codebase-mapper`)
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
        # First non-empty line that is not a Markdown heading
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

# Latest note
if [[ -d "$MB_PATH/notes" ]]; then
  latest_note=$(find "$MB_PATH/notes" -name "*.md" -type f 2>/dev/null | sort -r | head -1)
  if [[ -n "$latest_note" ]]; then
    echo "--- Latest note: $(basename "$latest_note") ---"
    cat "$latest_note"
    echo ""
  fi
fi
