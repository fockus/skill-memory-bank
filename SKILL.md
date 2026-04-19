---
name: memory-bank
description: "Long-term project memory через `.memory-bank/` + RULES (TDD/SOLID/Clean Architecture/FSD) + 19 dev commands. Use when working in a project with .memory-bank/ directory or when user explicitly asks for /mb, code rules, or dev-toolkit commands."
---

# Memory Bank Skill

Skill для управления долгосрочной памятью проекта через `.memory-bank/` директорию. Обеспечивает сохранение знаний между сессиями: статус, планы, задачи, исследования, уроки, заметки.

---

## Workspace Resolution

Memory Bank поддерживает внешнее хранение через `.claude-workspace`:

1. Если в корне проекта есть `.claude-workspace` с `storage: external`:
   → mb_path = `~/.claude/workspaces/{project_id}/.memory-bank`
2. Иначе: mb_path = `./.memory-bank` (default, backward compatible)

При вызове MB Manager — передавай resolved mb_path.
При вызове скриптов — передавай resolved mb_path как аргумент.

---

## Metadata Protocol

Все заметки в `notes/` создаются с YAML frontmatter для семантического поиска и targeted recall.

### Frontmatter формат

```yaml
---
type: lesson | note | decision | pattern
tags: []
related_features: []
sprint: null
importance: high | medium | low
created: YYYY-MM-DD
---
```

### Правила

1. **Все новые notes/** получают YAML frontmatter при создании (MB Manager генерирует автоматически)
2. **Tags** извлекаются LLM из содержимого заметки: 3-7 ключевых технических терминов, lowercase, singular
3. **Importance**:
   - `high` -- patterns, decisions, critical architectural insights
   - `medium` -- general notes, knowledge
   - `low` -- minor observations, одноразовые фиксы
4. **Шаблон**: `~/.claude/skills/memory-bank/references/templates.md`
5. **Старые заметки** (без frontmatter) продолжают работать -- index.json обрабатывает их с default tags

### Index Protocol

Memory Bank поддерживает `index.json` для быстрого поиска без чтения всех файлов.

**Формат `{mb_path}/index.json`:**
```json
{
  "version": 1,
  "updated": "YYYY-MM-DDTHH:MM:SS",
  "notes": [
    {
      "file": "notes/2026-03-29_14-30_topic.md",
      "type": "pattern",
      "tags": ["sqlite-vec", "embedding"],
      "importance": "high",
      "summary": "Local semantic search pattern via sqlite-vec"
    }
  ],
  "lessons": [
    {
      "id": "L-001",
      "tags": ["mock", "testing"],
      "summary": "Avoid mocking more than 5 dependencies"
    }
  ]
}
```

**Regeneration**: index.json пересоздаётся при `/mb done` (MB Manager action: actualize).
**Usage**: Agent читает index.json → фильтрует по tags/importance → читает только релевантные файлы.
**Fallback**: если index.json не существует → grep по frontmatter tags.

---

## Быстрый старт

### Начало сессии
1. Запусти `/mb start` или `bash ~/.claude/skills/memory-bank/scripts/mb-context.sh`
2. Получишь: фазу, фокус, задачи, метрики, активный план, последнюю заметку

### Во время работы
- Обновляй checklist.md по мере выполнения задач (⬜ → ✅)
- Для поиска информации: `/mb search <query>`
- Для создания плана: `/mb plan <type> <topic>`

### Завершение сессии
1. Запусти `/mb done` — актуализирует core files, создаст заметку, допишет progress
2. Или вручную: `/mb update` + `/mb note <topic>`

---

## Инструменты (bash-скрипты)

Все скрипты в `~/.claude/skills/memory-bank/scripts/`. По умолчанию работают с `.memory-bank/` в текущей директории.

### mb-context.sh — сборка контекста
```bash
bash ~/.claude/skills/memory-bank/scripts/mb-context.sh [mb_path]
```
Читает STATUS.md, plan.md, checklist.md, RESEARCH.md. Показывает активные планы и последнюю заметку.

### mb-search.sh — поиск по банку
```bash
bash ~/.claude/skills/memory-bank/scripts/mb-search.sh "<query>" [mb_path]
```
ripgrep с fallback на grep. Case-insensitive, только .md файлы.

### mb-index.sh — реестр записей
```bash
bash ~/.claude/skills/memory-bank/scripts/mb-index.sh [mb_path]
```
Core files с числом строк и датой. Notes, Plans, Experiments, Reports — списки с количеством.

### mb-note.sh — создание заметки
```bash
bash ~/.claude/skills/memory-bank/scripts/mb-note.sh "<topic>" [mb_path]
```
Создаёт `notes/YYYY-MM-DD_HH-MM_<topic>.md` с шаблоном. Возвращает путь к файлу.

### mb-plan.sh — создание файла плана
```bash
bash ~/.claude/skills/memory-bank/scripts/mb-plan.sh <type> "<topic>" [mb_path]
```
Types: `feature`, `fix`, `refactor`, `experiment`. Создаёт `plans/YYYY-MM-DD_<type>_<topic>.md` с шаблоном (DoD, TDD, риски).

---

## MB Manager — subagent (Sonnet)

MB Manager — subagent на Sonnet для механической работы с Memory Bank. Prompt: `~/.claude/skills/memory-bank/agents/mb-manager.md`.

### Когда запускать MB Manager

**ДЕЛЕГИРУЙ MB Manager (Task tool, model: sonnet):**

| Ситуация | Action | Пример |
|----------|--------|--------|
| Нужен контекст проекта | `context` | `/mb context`, `/mb start` |
| Поиск информации в банке | `search <query>` | `/mb search curiosity` |
| Завершена задача/этап | `actualize` | `/mb update`, `/mb done` |
| Нужна заметка по работе | `note <topic>` | `/mb note encoder-refactor` |
| Список незавершённых задач | `tasks` | `/mb tasks` |
| Конец сессии | `actualize + note` | `/mb done` |
| Перед compaction | `actualize` | Hook PreCompact |
| Рассинхрон в банке | `doctor` | `/mb doctor` |

**НЕ ДЕЛЕГИРУЙ MB Manager — делай сам:**

| Ситуация | Почему |
|----------|--------|
| Создание планов (plans/) | Требует глубокого понимания задачи, TDD, DoD |
| Архитектурные решения | Требует анализа trade-offs, контекста проекта |
| Оценка ML результатов | Требует интерпретации, статистики, выводов |

После архитектурного решения или ML эксперимента — вызови MB Manager (`actualize`) чтобы сохранить результаты в банк.

### Формат вызова MB Manager

```
Agent(
  subagent_type="general-purpose",
  model="sonnet",
  description="MB Manager: <краткое описание>",
  prompt="<содержание agents/mb-manager.md>\n\naction: <действие>\n\n<описание задачи и контекст>"
)
```

---

## Правила создания планов

При создании плана (главный агент, не MB Manager):

1. Создай файл: `bash ~/.claude/skills/memory-bank/scripts/mb-plan.sh <type> "<topic>"`
2. Заполни секции:
   - **Контекст**: проблема, что промптило, ожидаемый результат
   - **Этапы**: каждый с DoD по SMART (конкретный, измеримый, достижимый, реалистичный, с временными рамками)
   - **Тестирование**: unit + integration тесты ПЕРЕД реализацией (TDD)
   - **Каждый этап**: что тестировать, какие edge cases, lint requirements
   - **Правила кода**: SOLID, DRY, KISS, YAGNI, Clean Architecture — по `RULES.MD`
   - **Риски**: вероятность (H/M/L), mitigation
   - **Gate**: критерий успеха плана целиком
3. Этапы атомарны и упорядочены по зависимостям
4. Нет placeholder'ов — каждый шаг конкретен
5. Каждый assert в тестах должен проверять бизнес-требование или edge case

### Консистентность — ОБЯЗАТЕЛЬНО при создании плана

**После создания файла плана** обнови ВСЕ связанные core files:

```
plans/<файл>.md  → создан (шаг 1-2 выше)
plan.md          → обновить "Active plan" (ссылка на файл) + фокус
STATUS.md        → обновить roadmap (секция "В процессе")
checklist.md     → добавить задачи/этапы из плана как ⬜ пункты
```

**Цепочка source of truth:**
```
plan.md (Active plan → ссылка) → plans/<файл>.md (задачи, DoD) → checklist.md (трекинг) → STATUS.md (фаза)
```

Нарушение консистентности = баг. Все 4 файла ОБЯЗАНЫ быть синхронизированы.

**При завершении плана:** перенести в `plans/done/`, убрать из plan.md, обновить STATUS.md и checklist.md.
**При смене активного плана:** обновить plan.md + STATUS.md + checklist.md.

---

## Plan Verifier — верификация планов

Plan Verifier — subagent на Sonnet для проверки соответствия кода плану. Prompt: `~/.claude/skills/memory-bank/agents/plan-verifier.md`.

### Когда запускать

**ОБЯЗАТЕЛЬНО** перед закрытием плана (`/mb done` при работе по плану):
1. Вызови `/mb verify`
2. Plan Verifier перечитает план, проверит `git diff`, найдёт расхождения
3. Исправь все CRITICAL проблемы
4. WARNING — на усмотрение (спроси пользователя)
5. Только после этого — `/mb done`

### Формат вызова

```
Agent(
  subagent_type="general-purpose",
  model="sonnet",
  description="Plan Verifier: проверка плана",
  prompt="<содержание agents/plan-verifier.md>\n\nФайл плана: <путь>\n\nКонтекст: <что сделано>"
)
```

### Категории проблем

| Категория | Что значит | Действие |
|-----------|-----------|----------|
| CRITICAL | Этап не реализован, DoD не выполнен, тесты отсутствуют | Исправить обязательно |
| WARNING | Частичное покрытие, отклонение от плана | Спросить пользователя |
| INFO | Дополнительная работа не из плана | Принять к сведению |

---

## Ключевые правила Memory Bank

1. **Core files = истина о проекте**. STATUS.md, plan.md, checklist.md — всегда актуальны.
2. **progress.md = APPEND-ONLY**. Никогда не удалять и не редактировать старые записи.
3. **Нумерация сквозная**: H-NNN (гипотезы), EXP-NNN (эксперименты), ADR-NNN (решения).
4. **notes/ = знания, не хронология**. 5-15 строк. Выводы, паттерны, переиспользуемые решения.
5. **Чеклист**: ✅ = выполнено, ⬜ = не выполнено. Обновлять каждую сессию.
6. **Не вставляй логи, stacktraces, большие блоки кода**. Только дистиллированные заметки.
7. **ML эксперименты**: гипотеза (SMART) → baseline → одно изменение → run → результат (p-value, Cohen's d).
8. **Архитектурные решения** → ADR в BACKLOG.md (контекст → решение → альтернативы → последствия).

---

## Coexistence с native Claude Code memory

Claude Code имеет встроенный `auto memory` (кросс-проектный профиль пользователя в `~/.claude/projects/.../memory/`). Этот skill **не заменяет** его — они дополняют друг друга:

| Аспект | `.memory-bank/` (этот skill) | Native `auto memory` |
|--------|------------------------------|----------------------|
| Scope | Проект | Пользователь, кросс-проектно |
| Контент | Status, plans, checklists, research, ADR, lessons | Предпочтения, роль, обратная связь |
| Где | `.memory-bank/` в репо (commit или gitignore) | `~/.claude/projects/.../memory/` (machine-local) |
| Владелец | Проект (команда через git) | Пользователь (лично) |
| Когда использовать | Всё о проекте: цели, решения, state, WIP | Всё о том как вы любите работать: стиль, тон, ограничения |

**Правило:** если информация полезна *коллеге, который завтра возьмёт проект* — в `.memory-bank/`. Если полезна *вам в другом проекте на следующей неделе* — в native memory.

Оба механизма загружаются параллельно. Ни один не отключает другой.

---

## Ссылки

- Структура файлов: `~/.claude/skills/memory-bank/references/structure.md`
- Workflow: `~/.claude/skills/memory-bank/references/workflow.md`
- Шаблоны: `~/.claude/skills/memory-bank/references/templates.md`
- Prompt MB Manager: `~/.claude/skills/memory-bank/agents/mb-manager.md`
- Prompt Plan Verifier: `~/.claude/skills/memory-bank/agents/plan-verifier.md`
- Slash-команда: `/mb` (роутинг подкоманд)
