#!/usr/bin/env bash
# mb-search.sh — поиск по Memory Bank.
#
# Usage:
#   mb-search.sh <query> [mb_path]                     # полнотекстовый grep/rg
#   mb-search.sh --tag <tag> [mb_path]                 # фильтр по tag из index.json
#   mb-search.sh [--show-private] <query> [mb_path]    # показать <private> контент
#
# Флаг --tag требует .memory-bank/index.json (генерируется mb-index-json.py).
# Если index.json отсутствует — warning + auto-regenerate попытка, иначе exit 1.
#
# PII protection (Stage 3 v2.1):
#   Блоки <private>...</private> в заметках по умолчанию заменяются на [REDACTED].
#   --show-private требует MB_SHOW_PRIVATE=1 env (double-confirmation), иначе exit 2.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

# ═══ Parse --show-private flag ═══
SHOW_PRIVATE=0
ARGS=()
for arg in "$@"; do
  if [ "$arg" = "--show-private" ]; then
    SHOW_PRIVATE=1
  else
    ARGS+=("$arg")
  fi
done

if [ "$SHOW_PRIVATE" -eq 1 ] && [ "${MB_SHOW_PRIVATE:-0}" != "1" ]; then
  echo "[error] --show-private требует MB_SHOW_PRIVATE=1 env (double-confirmation)" >&2
  echo "[hint]  MB_SHOW_PRIVATE=1 mb-search --show-private <query>" >&2
  exit 2
fi

# Если есть аргументы после парсинга — используем их; иначе оригинальные "$@" пустые.
if [ "${#ARGS[@]}" -gt 0 ]; then
  set -- "${ARGS[@]}"
else
  set --
fi

# ═══ REDACT filter для вывода ═══
# По умолчанию — вырезать <private>...</private> (inline и multi-line).
# Для строк с открывающим <private> без закрытия в той же строке — редактируем всю строку.
redact() {
  if [ "$SHOW_PRIVATE" -eq 1 ]; then
    cat
    return
  fi
  # Inline закрытые: <private>...</private> → [REDACTED]
  # Строки с <private> без </private> на той же → [REDACTED multi-line private]
  # Строки с </private> без <private> на той же (хвост блока) → [REDACTED multi-line private]
  awk '
    {
      line = $0
      has_open = index(line, "<private>")
      has_close = index(line, "</private>")
      if (has_open > 0 && has_close > 0 && has_close > has_open) {
        # closed inline → substitute contents.
        gsub(/<private>[^<]*<\/private>/, "[REDACTED]", line)
        print line
        next
      }
      if (has_open > 0 || has_close > 0) {
        print "[REDACTED — multi-line private]"
        in_block = (has_open > 0 && has_close == 0)
        if (has_close > 0) in_block = 0
        next
      }
      if (in_block) {
        print "[REDACTED — multi-line private]"
        next
      }
      print line
    }
  '
}

# ═══ Tag mode ═══
if [ "${1:-}" = "--tag" ]; then
  TAG="${2:?Usage: mb-search.sh --tag <tag> [mb_path]}"
  MB_PATH=$(mb_resolve_path "${3:-}")

  INDEX="$MB_PATH/index.json"
  if [ ! -f "$INDEX" ]; then
    if [ -x "$(dirname "$0")/mb-index-json.py" ]; then
      python3 "$(dirname "$0")/mb-index-json.py" "$MB_PATH" >/dev/null 2>&1 || true
    fi
  fi

  if [ ! -f "$INDEX" ]; then
    echo "[error] index.json не найден: $INDEX" >&2
    echo "[hint]  сгенерируй: python3 $(dirname "$0")/mb-index-json.py $MB_PATH" >&2
    exit 1
  fi

  matches=$(TAG="$TAG" INDEX_PATH="$INDEX" python3 -c "
import json, os
tag = os.environ['TAG']
with open(os.environ['INDEX_PATH']) as f: data = json.load(f)
for n in data.get('notes', []):
    if tag in (n.get('tags') or []):
        print(n['path'])
")

  if [ -z "$matches" ]; then
    echo "Ничего не найдено по тегу: $TAG"
    exit 0
  fi

  echo "$matches" | while read -r rel; do
    [ -z "$rel" ] && continue
    echo "=== $rel ==="
    head -20 "$MB_PATH/$rel" 2>/dev/null | redact || true
    echo ""
  done
  exit 0
fi

# ═══ Freetext mode ═══
QUERY="${1:?Usage: mb-search.sh <query> [mb_path]  OR  mb-search.sh --tag <tag> [mb_path]}"
MB_PATH=$(mb_resolve_path "${2:-}")

if [[ ! -d "$MB_PATH" ]]; then
  echo "[MEMORY BANK: INACTIVE] Директория $MB_PATH не найдена" >&2
  exit 1
fi

if [ "$SHOW_PRIVATE" -eq 1 ]; then
  # Полный вывод (user явно подтвердил через MB_SHOW_PRIVATE=1)
  if command -v rg >/dev/null 2>&1; then
    rg --color=never -n -i --type md --heading "$QUERY" "$MB_PATH" 2>/dev/null \
      || echo "Ничего не найдено по запросу: $QUERY"
  else
    grep -rn -i --include="*.md" "$QUERY" "$MB_PATH" 2>/dev/null \
      || echo "Ничего не найдено по запросу: $QUERY"
  fi
else
  # Безопасный режим: аннотируем private-спаны, редактируем hits в этих спанах.
  QUERY="$QUERY" MB="$MB_PATH" python3 - <<'PYEOF'
import os, re
from pathlib import Path

query = os.environ["QUERY"].lower()
mb = Path(os.environ["MB"])
priv_closed = re.compile(r"<private>.*?</private>", re.DOTALL)
priv_open = re.compile(r"<private>.*\Z", re.DOTALL)

REDACTED_STUB = "[REDACTED match in private block]"

found = False
for md in sorted(mb.rglob("*.md")):
    try:
        text = md.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        continue

    # Спаны всех private блоков (закрытых и открытых).
    spans = [m.span() for m in priv_closed.finditer(text)]
    for m in priv_open.finditer(text):
        spans.append(m.span())

    lines = text.splitlines()
    hits = []
    offset = 0
    for i, line in enumerate(lines, 1):
        line_start = offset
        offset += len(line) + 1  # +1 для \n

        if query not in line.lower():
            continue

        # Строка содержит открывающий/закрывающий fence — inline private.
        if "<private>" in line or "</private>" in line:
            display = priv_closed.sub("[REDACTED]", line)
            if "<private>" in display or "</private>" in display:
                display = REDACTED_STUB
            hits.append((i, display))
        # Строка между fence'ами (multi-line блок).
        elif any(s <= line_start < e for s, e in spans):
            hits.append((i, REDACTED_STUB))
        else:
            hits.append((i, line))

    if hits:
        found = True
        print(f"=== {md.relative_to(mb)} ===")
        for num, line in hits[:20]:
            print(f"{num}:{line}")
        print()

if not found:
    print(f"Ничего не найдено по запросу: {os.environ['QUERY']}")
PYEOF
fi
