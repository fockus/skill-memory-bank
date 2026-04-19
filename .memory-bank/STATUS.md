# claude-skill-memory-bank: Статус проекта

## Текущая фаза
**Phase: Рефактор skill v2 — Этапы 0-5 завершены, 6+ впереди.**

Three-in-one skill для Claude Code: (1) Long-term project memory через `.memory-bank/`, (2) global dev rules (TDD, Clean Architecture для backend, FSD для frontend, Mobile UDF+Clean для iOS/Android, SOLID, Testing Trophy), (3) dev toolkit из 18 команд. Рефактор v2 делает skill language-agnostic, добавляет тесты/CI, интегрирует `mb-codebase-mapper`, автоматизирует consistency-chain, устраняет дублирование и хардкод.

## Ключевые метрики
- Shell-скрипты: **11** (`_lib.sh`, `mb-metrics.sh`, `mb-plan-sync.sh`, `mb-plan-done.sh`, `mb-upgrade.sh` + 5 refactored + 2 hook)
- Python-скрипты: 1 (`merge-hooks.py`, без тестов — Этап 6)
- Агенты: 4 (`mb-manager`, `mb-doctor`, `plan-verifier`, `mb-codebase-mapper`)
- Команды: **18** в `commands/` (после слияния `/mb init` + `/mb:setup-project`)
- Bats tests: **117/117 green**
- Python tests: 0 (Этап 6)
- Shellcheck warnings: **0**
- CI: отсутствует (Этап 6)
- Fixtures: 12 стеков (python, go, rust, node, java, kotlin, swift, cpp, ruby, php, csharp, elixir + multi + unknown)
- Hardcoded `pytest`/`ruff`/`taskloom` в operational code: **0**
- Orphan-агенты: **0**
- `Task(` legacy вхождений в skill-файлах: **0** (все → `Agent(subagent_type=...)`)
- Rules coverage: backend (Clean Architecture), frontend (FSD), mobile (iOS/Android UDF+Clean) — **все 3 слоя**
- Consistency-chain: plan↔checklist↔plan.md автоматизировано через `mb-plan-sync.sh`/`mb-plan-done.sh`

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
- **Этап 4: Автоматизация consistency-chain** — `mb-plan-sync.sh` + `mb-plan-done.sh`, 18 bats-тестов, интеграция в `/mb plan` и `mb-doctor`
- **Этап 5: Ecosystem integration** — Task→Agent (0 legacy), SKILL.md frontmatter fix, `/mb init [--minimal|--full]` (merged with setup-project), coexistence с native memory, three-in-one README, rules для frontend (FSD) и mobile (iOS/Android)

### 🔧 В работе
- **Этап 6: Tests + CI** — pytest для merge-hooks.py, e2e Docker install/uninstall, GitHub Actions matrix

### ⬜ Далее
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
