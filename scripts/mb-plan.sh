#!/usr/bin/env bash
# mb-plan.sh — создание файла плана в Memory Bank.
# Usage: mb-plan.sh <type> <topic> [mb_path]
# Types: feature, fix, refactor, experiment
# Создаёт plans/YYYY-MM-DD_<type>_<topic>.md с шаблоном (DoD, TDD, риски, Gate).
# Маркеры <!-- mb-stage:N --> в шаблоне используются mb-plan-sync.sh (Этап 4).

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

TYPE="${1:?Usage: mb-plan.sh <type> <topic> [mb_path]. Types: feature, fix, refactor, experiment}"
TOPIC="${2:?Usage: mb-plan.sh <type> <topic> [mb_path]}"
MB_PATH=$(mb_resolve_path "${3:-}")
PLANS_DIR="$MB_PATH/plans"

case "$TYPE" in
  feature|fix|refactor|experiment) ;;
  *) echo "Неизвестный тип: $TYPE. Допустимые: feature, fix, refactor, experiment" >&2; exit 1 ;;
esac

SAFE_TOPIC=$(mb_sanitize_topic "$TOPIC")

if [[ -z "$SAFE_TOPIC" ]]; then
  echo "Topic содержит только не-ASCII символы: $TOPIC" >&2
  exit 1
fi

DATE=$(date +"%Y-%m-%d")
FILENAME="${DATE}_${TYPE}_${SAFE_TOPIC}.md"
FILEPATH=$(mb_collision_safe_filename "$PLANS_DIR/$FILENAME")

mkdir -p "$PLANS_DIR"

cat > "$FILEPATH" << 'TEMPLATE'
# План: TYPE — TOPIC

## Контекст

**Проблема:** <!-- Что промптило создание этого плана -->

**Ожидаемый результат:** <!-- Что должно получиться -->

**Связанные файлы:**
- <!-- ссылки на код, спеки, эксперименты -->

---

## Этапы

<!-- mb-stage:1 -->
### Этап 1: <!-- название -->

**Что сделать:**
- <!-- конкретные действия -->

**Тестирование (TDD — тесты ПЕРЕД реализацией):**
- <!-- unit тесты: что проверяем, edge cases -->
- <!-- integration тесты: какие компоненты вместе -->

**DoD (Definition of Done):**
- [ ] <!-- конкретный, измеримый критерий (SMART) -->
- [ ] тесты проходят
- [ ] lint clean

**Правила кода:** SOLID, DRY, KISS, YAGNI, Clean Architecture

---

<!-- mb-stage:2 -->
### Этап 2: <!-- название -->

**Что сделать:**
-

**Тестирование (TDD):**
-

**DoD:**
- [ ]

---

## Риски и mitigation

| Риск | Вероятность | Mitigation |
|------|-------------|------------|
| <!-- риск --> | <!-- H/M/L --> | <!-- как предотвратить --> |

## Gate (критерий успеха плана)

<!-- Когда план считается выполненным целиком -->
TEMPLATE

# Подставить type и topic в заголовок (портативный sed: macOS vs GNU)
if sed --version >/dev/null 2>&1; then
  sed -i "s|TYPE|$TYPE|g; s|TOPIC|$SAFE_TOPIC|g" "$FILEPATH"
else
  sed -i '' "s|TYPE|$TYPE|g; s|TOPIC|$SAFE_TOPIC|g" "$FILEPATH"
fi

echo "$FILEPATH"
