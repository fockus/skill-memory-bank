# claude-skill-memory-bank: Статус проекта

## Текущая фаза
**Phase: Рефактор skill v2.** Аудит завершён, план утверждён, приступаем к исполнению этапов.

Долговременная проектная память для Claude Code. Skill обеспечивает сохранение контекста между сессиями через `.memory-bank/`. Рефактор v2 делает skill language-agnostic, добавляет тесты/CI, интегрирует `mb-codebase-mapper`, устраняет дублирование и хардкод.

## Ключевые метрики
- Shell-скрипты: 8 (5 refactored под `_lib.sh` + `_lib.sh` сам)
- Python-скрипты: 1 (`merge-hooks.py`, без тестов — Этап 6)
- Агенты: 4 (`mb-manager`, `mb-doctor`, `plan-verifier`, `codebase-mapper` — последний orphan, адаптируется в Этапе 3)
- Команды: 19 в `commands/` (консолидация в Этапе 5)
- Bats tests: **36/36 green** (`tests/bats/test_lib.bats`)
- Python tests: 0 (Этап 6-8)
- Shellcheck warnings: **0** (с `-x --source-path=SCRIPTDIR`)
- CI: отсутствует (Этап 6)
- Fixtures: 6 стеков (python, go, rust, node, multi, unknown)

## Roadmap

### ✅ Завершено
- **Аудит skill v1**: выявлено 36 проблем, сгруппировано по критичности
- **План рефактора v2**: 10 этапов с DoD SMART, TDD, рисками, Gate
- **Этап 0: Dogfood init** — `.memory-bank/` инициализирован в репо, план сохранён, коммит `637dd84`
- **Этап 1: DRY + language detection** — `_lib.sh` (7 функций, 150 строк), 36 bats-тестов зелёные, 5 скриптов рефакторены, 0 shellcheck warnings

### 🔧 В работе
- **Этап 2: Language-agnostic `/mb update` и `mb-doctor`** — убрать хардкод pytest/ruff/taskloom

### ⬜ Далее
- **Этап 3**: `mb-codebase-mapper` — memory-bank-native
- **Этап 4**: Автоматизация consistency-chain (plan-sync)
- **Этап 5**: Ecosystem integration (Agent tool, native memory coexistence, merge init)
- **Этап 6**: Tests + CI (bats, pytest, GitHub Actions)
- **Этап 7**: Hooks — fixes (false-positives, log rotation, bypass)
- **Этап 8**: `index.json` — прагматичная реализация
- **Этап 9**: Финализация (CHANGELOG, migration guide, SKILL.md <150 строк)

## Gate v2

Skill considered refactored when: 4 стека детектируются, CI зелёный на macOS+Ubuntu, 0 `Task(` legacy, `_lib.sh` переиспользуется 4+ скриптами, Python coverage ≥85%, `mb-codebase-mapper` работает через `/mb map`, skill дог-фудит сам себя через этот `.memory-bank/`.

## Известные ограничения (устраняются планом)
- Хардкод Python/pytest в `/mb update` → Этап 2
- `codebase-mapper` пишет в `.planning/` → Этап 3
- Нет тестов → Этап 6
- Task tool вместо Agent → Этап 5
- Дублирование workspace-resolver в 4 скриптах → Этап 1
