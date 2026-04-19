#!/usr/bin/env bash
# mb-search.sh — поиск по Memory Bank.
# Usage: mb-search.sh <query> [mb_path]

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

QUERY="${1:?Usage: mb-search.sh <query> [mb_path]}"
MB_PATH=$(mb_resolve_path "${2:-}")

if [[ ! -d "$MB_PATH" ]]; then
  echo "[MEMORY BANK: INACTIVE] Директория $MB_PATH не найдена" >&2
  exit 1
fi

# ripgrep с fallback на grep
if command -v rg >/dev/null 2>&1; then
  rg --color=never -n -i --type md --heading "$QUERY" "$MB_PATH" || echo "Ничего не найдено по запросу: $QUERY"
else
  grep -rn -i --include="*.md" "$QUERY" "$MB_PATH" || echo "Ничего не найдено по запросу: $QUERY"
fi
