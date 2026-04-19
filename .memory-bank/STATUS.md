# claude-skill-memory-bank: Статус проекта

## Текущая фаза
**Phase: Рефактор skill v2.** Аудит завершён, план утверждён, приступаем к исполнению этапов.

Долговременная проектная память для Claude Code. Skill обеспечивает сохранение контекста между сессиями через `.memory-bank/`. Рефактор v2 делает skill language-agnostic, добавляет тесты/CI, интегрирует `mb-codebase-mapper`, устраняет дублирование и хардкод.

## Ключевые метрики
- Shell-скрипты: 7 (без тестов)
- Python-скрипты: 1 (`merge-hooks.py`, без тестов)
- Агенты: 4 (`mb-manager`, `mb-doctor`, `plan-verifier`, `codebase-mapper` — последний orphan)
- Команды: 19 в `commands/`
- Тестовое покрытие: **0%** (нарушение RULES — исправляется в Этапе 6)
- CI: отсутствует
- Shellcheck warnings: unknown (замер в Этапе 1)

## Roadmap

### ✅ Завершено
- **Аудит skill v1**: выявлено 36 проблем, сгруппировано по критичности
- **План рефактора v2**: 10 этапов с DoD SMART, TDD, рисками, Gate

### 🔧 В работе
- **Этап 0: Dogfood init** — инициализация `.memory-bank/` в корне репозитория

### ⬜ Далее
- **Этап 1**: DRY-утилиты `_lib.sh` + language detection
- **Этап 2**: Language-agnostic `/mb update` и `mb-doctor`
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
