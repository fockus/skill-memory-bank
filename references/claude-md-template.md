# CLAUDE.md Template

Шаблон для генерации CLAUDE.md через `/mb init --full`.
Переменные в `{VARIABLE}` заменяются автодетектом.

---

## Project

**{PROJECT_NAME}**

{PROJECT_DESCRIPTION}

### Constraints

- **Tech stack**: {LANGUAGE} {LANGUAGE_VERSION}+, {KEY_DEPS}
- **Testing**: 85%+ overall, 95%+ core/business coverage. TDD mandatory.
- **Architecture**: SOLID, KISS, DRY, YAGNI, Clean Architecture

## Technology Stack

## Languages
- {LANGUAGE} {LANGUAGE_VERSION}+ — all application source code in `{SRC_DIR}/`

## Runtime
- {RUNTIME_INFO}
- {PACKAGE_MANAGER} — primary manager

## Frameworks
- {FRAMEWORKS}

## Key Dependencies
{KEY_DEPENDENCIES}

## Configuration
{CONFIG_FILES}

## Conventions

## Naming Patterns
{NAMING_CONVENTIONS}

## Code Style
- Tool: `{LINTER}` (`{LINTER}>={LINTER_VERSION}`)
- Line length: {LINE_LENGTH} characters
- Target: {LANGUAGE} {LANGUAGE_VERSION} syntax

## Architecture

## Pattern Overview
- All cross-layer dependencies point inward: Infrastructure → Application → Domain
- Domain layer contains zero external dependencies
- All components receive dependencies via constructor injection

{ARCHITECTURE_DETAILS}

## Rules

Подробные правила: `~/.claude/RULES.md` + `.memory-bank/RULES.md`

### Критические правила (всегда соблюдать)

> **Contract-First** — Protocol/ABC → contract-тесты → реализация. Тесты проходят для ЛЮБОЙ корректной реализации.
> **TDD** — сначала тесты, потом код. Пропуск: только опечатки, форматирование, exploratory prototypes.
> **Clean Architecture** — `Infrastructure → Application → Domain` (никогда обратно). Domain = 0 внешних зависимостей.
> **SOLID пороги** — SRP: >300 строк или >3 публичных метода разной природы = разделить. ISP: Interface ≤5 методов. DIP: конструктор принимает абстракцию.
> **DRY / KISS / YAGNI** — дубль >2 раз → извлечь. Три одинаковых строки лучше преждевременной абстракции. Не писать код "на будущее".
> **Testing Trophy** — интеграционные > unit > e2e. Mock только внешние сервисы. >5 mock'ов → кандидат на интеграционный.
> **Качество тестов** — имя: `test_<что>_<условие>_<результат>`. Assert = бизнес-факт. Arrange-Act-Assert. `@parametrize` вместо копипасты.
> **Coverage** — общий 85%+, core/business 95%+, infrastructure 70%+.
> **Без placeholder'ов** — никаких TODO, `...`, псевдокода. Код copy-paste ready.
> **Язык** — ответы на русском, техтермины на английском.

## Memory Bank

**Если `./.memory-bank/` существует → `[MEMORY BANK: ACTIVE]`.**

**Команда:** `/mb`. **Workflow:** start → work → verify → done.

| Команда | Описание |
|---------|----------|
| `/mb` или `/mb context` | Собрать контекст проекта |
| `/mb start` | Расширенный старт сессии |
| `/mb update` | Актуализировать core files |
| `/mb done` | Завершение сессии |
| `/mb verify` | Верификация плана vs код |
| `/mb init --full` | Пересоздать CLAUDE.md с автодетектом стека |

### Структура .memory-bank/

| Файл | Назначение | Когда обновлять |
|------|-----------|-----------------|
| `STATUS.md` | Где мы, roadmap, метрики | Завершён этап |
| `checklist.md` | Задачи ✅/⬜ | Каждую сессию |
| `plan.md` | Приоритеты, направление | Смена фокуса |
| `RULES.md` | Правила проекта | При обновлении |
| `RESEARCH.md` | Гипотезы + findings | Новый finding |
| `progress.md` | Выполненная работа (append-only) | Конец сессии |
| `lessons.md` | Антипаттерны | Когда замечен паттерн |
