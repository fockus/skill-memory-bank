#!/bin/bash
# SessionEnd hook: auto-capture для Memory Bank.
#   - Если .memory-bank/.session-lock свежий (<1h) → /mb done уже был,
#     подчищаем lock и выходим.
#   - Иначе (в режиме MB_AUTO_CAPTURE=auto) дописываем placeholder entry
#     в progress.md (append-only, идемпотентно по session_id).
#   - MB_AUTO_CAPTURE=off → полный noop. =strict → skip с hint.
#   - Concurrent-safe: .auto-lock защищает от дублей при быстрых вызовах.
#   - Полный actualize остаётся у ручного /mb done (Sonnet); hook — Haiku-ready
#     placeholder, который MB Manager раскроет в следующей сессии.

set -u

command -v jq >/dev/null 2>&1 || exit 0   # без jq — тихо noop

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -z "$CWD" ] && CWD="$PWD"

MB="$CWD/.memory-bank"
[ -d "$MB" ] || exit 0

MODE="${MB_AUTO_CAPTURE:-auto}"
LOCK="$MB/.session-lock"
AUTO_LOCK="$MB/.auto-lock"
MAX_LOCK_AGE=3600  # 1 час
MAX_AUTO_LOCK_AGE=30

# Portable mtime
mtime() {
  stat -f%m "$1" 2>/dev/null || stat -c%Y "$1" 2>/dev/null || echo 0
}

now=$(date +%s)

# ═══ Lock-файл: маркер ручного /mb done ═══
if [ -f "$LOCK" ]; then
  age=$(( now - $(mtime "$LOCK") ))
  if [ "$age" -lt "$MAX_LOCK_AGE" ]; then
    rm -f "$LOCK"
    exit 0
  fi
  # Stale lock — убираем и продолжаем auto-capture.
  rm -f "$LOCK"
fi

# ═══ Mode dispatch ═══
case "$MODE" in
  off)
    exit 0
    ;;
  strict)
    printf '[MB strict] ожидается явный /mb done (нет .session-lock), auto-capture пропущен\n' >&2
    exit 0
    ;;
  auto)
    ;;  # fall through
  *)
    printf '[MB] unknown MB_AUTO_CAPTURE=%s (ожидалось auto|strict|off), skipping\n' "$MODE" >&2
    exit 0
    ;;
esac

# ═══ Concurrent guard ═══
if [ -f "$AUTO_LOCK" ]; then
  auto_age=$(( now - $(mtime "$AUTO_LOCK") ))
  if [ "$auto_age" -lt "$MAX_AUTO_LOCK_AGE" ]; then
    exit 0
  fi
  rm -f "$AUTO_LOCK"
fi
touch "$AUTO_LOCK"
trap 'rm -f "$AUTO_LOCK"' EXIT INT TERM

# ═══ progress.md ═══
PROGRESS="$MB/progress.md"
[ -f "$PROGRESS" ] || exit 0   # не создаём — это работа /mb init

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
SID_PREFIX=$(printf '%s' "$SID" | cut -c1-8)
TODAY=$(date +%Y-%m-%d)

# Идемпотентность: та же сессия и день уже записаны → ничего не делаем.
if grep -q "Auto-capture.*${SID_PREFIX}" "$PROGRESS" 2>/dev/null; then
  exit 0
fi

{
  printf '\n## %s\n\n' "$TODAY"
  printf '### Auto-capture %s (session %s)\n' "$TODAY" "$SID_PREFIX"
  printf -- '- Сессия завершилась без явного /mb done\n'
  printf -- '- Детали будут восстановлены при следующем /mb start (MB Manager дочитает транскрипт)\n'
} >> "$PROGRESS"

exit 0
