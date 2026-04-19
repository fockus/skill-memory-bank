#!/usr/bin/env bash
# mb-upgrade.sh — обновление skill из GitHub.
#
# Usage:
#   mb-upgrade.sh              # check → prompt → pull + reinstall
#   mb-upgrade.sh --check      # только проверить: exit 0 = up to date, 1 = update available
#   mb-upgrade.sh --force      # применить без подтверждения (для автоматизации)
#
# Env:
#   MB_SKILL_DIR — путь к клонированному репо. Default: ~/.claude/skills/claude-skill-memory-bank
#
# Требования:
#   - skill установлен как `git clone` (не ZIP)
#   - working tree чистый (нет локальных правок)
#   - network access для git fetch

set -euo pipefail

SKILL_DIR="${MB_SKILL_DIR:-$HOME/.claude/skills/claude-skill-memory-bank}"

CHECK_ONLY=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --force) FORCE=1 ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
  esac
done

# ═══ Pre-flight: skill directory exists ═══
if [ ! -d "$SKILL_DIR" ]; then
  echo "[error] Skill directory не найдена: $SKILL_DIR" >&2
  echo "[hint] Установи через: git clone https://github.com/fockus/claude-skill-memory-bank.git $SKILL_DIR" >&2
  exit 1
fi

# ═══ Pre-flight: it's a git repo ═══
if [ ! -d "$SKILL_DIR/.git" ]; then
  echo "[error] $SKILL_DIR — не git repository (auto-upgrade требует clone)" >&2
  echo "[hint] Переустанови через: rm -rf $SKILL_DIR && git clone https://github.com/fockus/claude-skill-memory-bank.git $SKILL_DIR" >&2
  exit 1
fi

cd "$SKILL_DIR"

# ═══ Pre-flight: working tree clean ═══
if ! git diff --quiet 2>/dev/null; then
  echo "[error] Skill repo имеет unstaged локальные изменения" >&2
  git status --short >&2
  echo "[hint] Сохрани/откати изменения: git stash OR git checkout -- ." >&2
  exit 1
fi
if ! git diff --cached --quiet 2>/dev/null; then
  echo "[error] Skill repo имеет staged локальные изменения" >&2
  git status --short >&2
  exit 1
fi

# ═══ Read local version ═══
local_version="unknown"
[ -f VERSION ] && local_version=$(tr -d '[:space:]' < VERSION)
local_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

echo "Local:  $local_version ($local_commit)"

# ═══ Fetch from remote ═══
echo "[info] Fetching from origin..."
if ! git fetch origin 2>&1 | grep -v "^$" | head -5; then
  : # может быть no-op если up-to-date
fi

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
remote_branch="origin/$branch"

# Если remote-ветка не существует — ошибка
if ! git rev-parse --verify "$remote_branch" >/dev/null 2>&1; then
  echo "[error] Remote branch $remote_branch не найдена. Возможно remote настроен неправильно." >&2
  exit 2
fi

remote_commit=$(git rev-parse --short "$remote_branch")

# ═══ Compare ═══
behind=$(git rev-list --count "HEAD..$remote_branch" 2>/dev/null || echo 0)
ahead=$(git rev-list --count "$remote_branch..HEAD" 2>/dev/null || echo 0)

echo "Remote: $remote_commit ($branch)"
echo "Status: $behind behind, $ahead ahead"
echo ""

if [ "$behind" -eq 0 ]; then
  echo "[✓] Up to date"
  exit 0
fi

# ═══ Update available ═══
echo "=== $behind новых коммитов ==="
git --no-pager log --oneline "HEAD..$remote_branch" | head -10
echo ""

if [ "$CHECK_ONLY" -eq 1 ]; then
  exit 1  # сигнал что update доступен
fi

# ═══ Prompt ═══
if [ "$FORCE" -eq 0 ]; then
  if [ ! -t 0 ]; then
    echo "[error] Не-интерактивный режим требует --force флаг" >&2
    exit 3
  fi
  read -r -p "Применить $behind обновлений (git pull + re-install)? (y/n): " answer
  if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
    echo "Отменено пользователем"
    exit 0
  fi
fi

# ═══ Apply ═══
echo "[info] git pull --ff-only origin $branch..."
if ! git pull --ff-only origin "$branch"; then
  echo "[error] git pull failed (возможно, divergent branches)" >&2
  echo "[hint] Вручную: cd $SKILL_DIR && git pull" >&2
  exit 4
fi

if [ -x "$SKILL_DIR/install.sh" ]; then
  echo "[info] Re-running install.sh..."
  bash "$SKILL_DIR/install.sh"
else
  echo "[warning] install.sh отсутствует или не executable — пропускаю re-install" >&2
fi

new_version="unknown"
[ -f VERSION ] && new_version=$(tr -d '[:space:]' < VERSION)
new_commit=$(git rev-parse --short HEAD)

echo ""
echo "[✓] Skill обновлён: $local_version → $new_version ($local_commit → $new_commit)"
