#!/bin/bash
# PostToolUse hook: лог изменений файлов + проверка на placeholder/secrets.
#   - логирует Write/Edit в ~/.claude/file-changes.log
#   - ротирует лог при превышении 10 MB (→ .log.1, .log.2)
#   - ищет TODO/FIXME/HACK/XXX/PLACEHOLDER/NotImplementedError в КОДЕ (не в
#     docstrings и не в плейнтекстовых файлах)
#   - НЕ считает bare `pass` за placeholder — это легитимный Python
#   - варнит на hardcoded secrets в source-коде

set -u

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required for hook" >&2; exit 1; }

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
LOG_FILE="$HOME/.claude/file-changes.log"
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10 MB

# ═══ Log rotation ═══
# Portable size check: BSD stat -f%z (macOS) или GNU stat -c%s (Linux).
if [ -f "$LOG_FILE" ]; then
  LOG_SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$LOG_SIZE" -gt "$MAX_LOG_SIZE" ]; then
    # Сдвигаем .log.2 → .log.3, .log.1 → .log.2, .log → .log.1
    [ -f "$LOG_FILE.2" ] && mv "$LOG_FILE.2" "$LOG_FILE.3"
    [ -f "$LOG_FILE.1" ] && mv "$LOG_FILE.1" "$LOG_FILE.2"
    mv "$LOG_FILE" "$LOG_FILE.1"
  fi
fi

# ═══ Append log entry ═══
case "$TOOL" in
  Write) echo "[$TIMESTAMP] WRITE: $FILE_PATH" >> "$LOG_FILE" ;;
  Edit)  echo "[$TIMESTAMP] EDIT: $FILE_PATH"  >> "$LOG_FILE" ;;
esac

[ -f "$FILE_PATH" ] || exit 0

# Плейнтекстовые файлы — без проверок (TODO в markdown/config ≠ bug).
if [[ "$FILE_PATH" =~ \.(md|txt|json|yaml|yml|toml|cfg|ini|env)$ ]]; then
  exit 0
fi

# ═══ Placeholder detection (вне docstrings) ═══
#
# Алгоритм: сначала вырезаем triple-quoted блоки (""" ... """ и ''' ... '''),
# потом грепаем в том, что осталось.
#   - `pass` убран из списка — легитимный Python-стейтмент.
#   - Поиск выполняется с учётом ещё одной границы (\b): "TODOLIST" не триггерит.
#
# awk читает маркеры через переменные, чтобы shellcheck-SC1003 не путался
# с тройными одинарными кавычками внутри awk-скрипта.
stripped=$(awk -v dq='"""' -v sq="'''" '
  BEGIN { in_q = 0 }
  function count(str, pat,   n) {
    n = 0
    while (index(str, pat) > 0) {
      str = substr(str, index(str, pat) + length(pat))
      n++
    }
    return n
  }
  {
    line = $0
    occ = count(line, dq) + count(line, sq)
    if (in_q) {
      if (occ > 0) { in_q = 0 }
      next
    }
    if (occ >= 2) { next }          # open-and-close on one line → skip
    if (occ == 1) { in_q = 1; next } # only opener → enter docstring
    printf "%d:%s\n", NR, line
  }
' "$FILE_PATH")

PLACEHOLDERS=$(printf '%s\n' "$stripped" \
  | grep -E '\b(TODO|FIXME|HACK|XXX|PLACEHOLDER|NotImplementedError|raise NotImplemented)\b' \
  | head -5 || true)

if [ -n "$PLACEHOLDERS" ]; then
  echo "WARNING: Placeholder'ы найдены в $FILE_PATH:" >&2
  echo "$PLACEHOLDERS" >&2
fi

# ═══ <private> markers в .md файлах ═══
# Если пользователь коммитит файл с <private>...</private> — предупреждаем.
# Блок не утечёт в index.json/search, но может утечь в git history.
if [[ "$FILE_PATH" =~ \.md$ ]] && grep -q '<private>' "$FILE_PATH" 2>/dev/null; then
  echo "WARNING: <private> block in $FILE_PATH — убедись что не коммитишь в git (или используй git-filter/.gitattributes)" >&2
fi

# ═══ Secrets в исходниках ═══
if [[ "$FILE_PATH" =~ \.(py|go|js|ts|rb|java|rs|swift|kt)$ ]]; then
  SECRETS=$(grep -nEi '(password|secret|api_key|token|private_key)\s*=\s*["\x27][^"\x27]{8,}' "$FILE_PATH" 2>/dev/null \
    | grep -vEi '(test|mock|fake|example|placeholder|xxx|your_)' \
    | head -3)
  if [ -n "$SECRETS" ]; then
    echo "WARNING: Possible hardcoded secrets in $FILE_PATH:" >&2
    echo "$SECRETS" >&2
  fi
fi

exit 0
