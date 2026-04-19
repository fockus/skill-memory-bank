#!/usr/bin/env bash
# mb-metrics.sh — language-agnostic сборщик метрик проекта.
#
# Usage:
#   mb-metrics.sh [dir]          # read-only: выводит key=value (stack, cmds, counts)
#   mb-metrics.sh --run [dir]    # выполняет test_cmd и записывает test_status
#
# Priority:
#   1. ./.memory-bank/metrics.sh (override) — если существует, вызывается вместо auto-detect
#   2. Auto-detect через mb_detect_stack из _lib.sh
#
# Exit 0 даже при unknown-стеке (graceful fallback).

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

RUN_MODE=0
if [[ "${1:-}" == "--run" ]]; then
  RUN_MODE=1
  shift
fi

DIR="${1:-.}"

# ═══ Priority 1: project-specific override ═══
if [[ -f "$DIR/.memory-bank/metrics.sh" ]]; then
  echo "source=override"
  bash "$DIR/.memory-bank/metrics.sh"
  exit 0
fi

# ═══ Priority 2: auto-detect ═══
STACK=$(mb_detect_stack "$DIR")
echo "source=auto"
echo "stack=$STACK"

if [[ "$STACK" == "unknown" ]]; then
  echo "test_cmd="
  echo "lint_cmd="
  echo "src_count=0"
  echo "[warning] Стек не определён. Метрики пропущены." >&2
  echo "[hint] Создайте .memory-bank/metrics.sh для кастомных метрик." >&2
  exit 0
fi

TEST_CMD=$(mb_detect_test_cmd "$STACK")
LINT_CMD=$(mb_detect_lint_cmd "$STACK")

echo "test_cmd=$TEST_CMD"
echo "lint_cmd=$LINT_CMD"

# ═══ Source file count ═══
count_files() {
  local stack="$1" dir="$2"
  case "$stack" in
    python)
      find "$dir" -name "*.py" -type f \
        -not -path '*/\.*' \
        -not -path '*/__pycache__/*' \
        -not -path '*/node_modules/*' \
        2>/dev/null | wc -l | tr -d ' '
      ;;
    go)
      find "$dir" -name "*.go" -type f \
        -not -path '*/\.*' \
        -not -path '*/vendor/*' \
        2>/dev/null | wc -l | tr -d ' '
      ;;
    rust)
      find "$dir" -name "*.rs" -type f \
        -not -path '*/\.*' \
        -not -path '*/target/*' \
        2>/dev/null | wc -l | tr -d ' '
      ;;
    node)
      find "$dir" \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) -type f \
        -not -path '*/\.*' \
        -not -path '*/node_modules/*' \
        -not -path '*/dist/*' \
        -not -path '*/build/*' \
        2>/dev/null | wc -l | tr -d ' '
      ;;
    java)
      find "$dir" -name "*.java" -type f \
        -not -path '*/\.*' \
        -not -path '*/target/*' \
        -not -path '*/build/*' \
        -not -path '*/.gradle/*' \
        2>/dev/null | wc -l | tr -d ' '
      ;;
    kotlin)
      find "$dir" \( -name "*.kt" -o -name "*.kts" \) -type f \
        -not -path '*/\.*' \
        -not -path '*/target/*' \
        -not -path '*/build/*' \
        -not -path '*/.gradle/*' \
        2>/dev/null | wc -l | tr -d ' '
      ;;
    swift)
      find "$dir" -name "*.swift" -type f \
        -not -path '*/\.*' \
        -not -path '*/.build/*' \
        -not -path '*/DerivedData/*' \
        2>/dev/null | wc -l | tr -d ' '
      ;;
    cpp)
      find "$dir" \( -name "*.cpp" -o -name "*.cc" -o -name "*.cxx" -o -name "*.c" -o -name "*.hpp" -o -name "*.h" \) -type f \
        -not -path '*/\.*' \
        -not -path '*/build/*' \
        -not -path '*/out/*' \
        -not -path '*/cmake-build-*/*' \
        2>/dev/null | wc -l | tr -d ' '
      ;;
    ruby)
      find "$dir" -name "*.rb" -type f \
        -not -path '*/\.*' \
        -not -path '*/vendor/*' \
        -not -path '*/.bundle/*' \
        2>/dev/null | wc -l | tr -d ' '
      ;;
    php)
      find "$dir" -name "*.php" -type f \
        -not -path '*/\.*' \
        -not -path '*/vendor/*' \
        2>/dev/null | wc -l | tr -d ' '
      ;;
    csharp)
      find "$dir" -name "*.cs" -type f \
        -not -path '*/\.*' \
        -not -path '*/bin/*' \
        -not -path '*/obj/*' \
        2>/dev/null | wc -l | tr -d ' '
      ;;
    elixir)
      find "$dir" \( -name "*.ex" -o -name "*.exs" \) -type f \
        -not -path '*/\.*' \
        -not -path '*/_build/*' \
        -not -path '*/deps/*' \
        2>/dev/null | wc -l | tr -d ' '
      ;;
    multi)
      echo "-1"  # multi-stack: caller может декомпозировать через отдельные вызовы
      ;;
    *)
      echo "0"
      ;;
  esac
}

SRC_COUNT=$(count_files "$STACK" "$DIR")
echo "src_count=$SRC_COUNT"

# ═══ Optional: --run mode ═══
if [[ "$RUN_MODE" -eq 1 ]] && [[ -n "$TEST_CMD" ]]; then
  echo ""
  echo "[run] Выполнение test_cmd: $TEST_CMD"
  if (cd "$DIR" && bash -c "$TEST_CMD" >/tmp/mb-metrics-test.log 2>&1); then
    echo "test_status=pass"
  else
    echo "test_status=fail"
    echo "[tail] $(tail -5 /tmp/mb-metrics-test.log 2>/dev/null | tr '\n' ' ')" >&2
  fi
fi
