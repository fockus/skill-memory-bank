# claude-skill-memory-bank: Статус проекта

## Текущая фаза
**Phase: Рефактор skill v2.** Аудит завершён, план утверждён, приступаем к исполнению этапов.

Долговременная проектная память для Claude Code. Skill обеспечивает сохранение контекста между сессиями через `.memory-bank/`. Рефактор v2 делает skill language-agnostic, добавляет тесты/CI, интегрирует `mb-codebase-mapper`, устраняет дублирование и хардкод.

## Ключевые метрики
- Shell-скрипты: 9 (`_lib.sh`, `mb-metrics.sh` + 5 refactored + 2 hook)
- Python-скрипты: 1 (`merge-hooks.py`, без тестов — Этап 6)
- Агенты: 4 (`mb-manager`, `mb-doctor`, `plan-verifier`, `mb-codebase-mapper` — все MB-native)
- Команды: 19 в `commands/` (`/mb` теперь с подкомандой `map`)
- Bats tests: **93/93 green** (`test_lib.bats` 56 + `test_metrics.bats` 30 + `test_context_integration.bats` 7)
- Python tests: 0 (Этап 6-8)
- Shellcheck warnings: **0** (с `-x --source-path=SCRIPTDIR`)
- CI: отсутствует (Этап 6)
- Fixtures: 12 стеков (python, go, rust, node, java, kotlin, swift, cpp, ruby, php, csharp, elixir + multi + unknown)
- Hardcoded `pytest`/`ruff`/`taskloom` в operational code: **0**
- Orphan-агенты: **0** (`codebase-mapper` → `mb-codebase-mapper`)

## Roadmap

### ✅ Завершено
- **Аудит skill v1**: выявлено 36 проблем, сгруппировано по критичности
- **План рефактора v2**: 10 этапов с DoD SMART, TDD, рисками, Gate
- **Этап 0: Dogfood init** — `.memory-bank/` инициализирован в репо, план сохранён, коммит `637dd84`
- **Этап 1: DRY + language detection** — `_lib.sh` (7 функций), 36 bats-тестов, 5 скриптов рефакторены, коммит `722fbc5`
- **Этап 2: Language-agnostic metrics** — `mb-metrics.sh` + override, `/mb update` и `mb-doctor` без Python-хардкода, коммит `4695a1f`
- **Этап 2.1: Java/Kotlin/Swift/C++** — +20 bats-тестов, 4 новых fixture-стека, коммит `69f9422`
- **Этап 2.2: Ruby/PHP/C#/Elixir** — +20 bats-тестов, 4 новых fixture-стека, коммит `4ad08aa`
- **Этап 3: mb-codebase-mapper** — orphan агент адаптирован (316 vs 770 строк), `/mb map` команда, интеграция в `/mb context --deep`

### 🔧 В работе
- **Этап 4: Автоматизация consistency-chain** — `mb-plan-sync.sh` для синхронизации plan↔checklist↔STATUS

### ⬜ Далее
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
