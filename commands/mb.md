---
description: "Memory Bank — управление долгосрочной памятью проекта"
allowed-tools: [Bash, Read, Write, Edit, Task, Glob, Grep]
---

# Memory Bank — /mb

Команда `/mb` — единая точка входа для управления Memory Bank проекта (`.memory-bank/`).

## Подкоманды

Аргументы: `$ARGUMENTS`

Определи подкоманду из первого слова `$ARGUMENTS`. Остальные слова — параметры подкоманды.

### Роутинг

| Подкоманда | Действие |
|-----------|---------|
| (пусто) или `context` | Собрать контекст проекта |
| `start` | Расширенный старт сессии |
| `search <query>` | Поиск информации в банке |
| `note <topic>` | Создать заметку |
| `update` | Актуализировать core files (с анализом текущего состояния кода) |
| `doctor` | Найти и исправить рассинхроны внутри MB (консистентность записей) |
| `tasks` | Показать незавершённые задачи |
| `index` | Реестр всех записей |
| `done` | Завершение сессии (actualize + note + progress) |
| `plan <type> <topic>` | Создать план |
| `verify` | Верификация выполнения плана (план vs код) |
| `map [focus]` | Просканировать кодовую базу и записать MD-документы в `.memory-bank/codebase/`. focus: stack / arch / quality / concerns / all (default: all) |
| `init` | Инициализировать Memory Bank в новом проекте |
| (нераспознанное) | Поиск по `$ARGUMENTS` |

---

## Реализация подкоманд

### context / start / search / note / tasks / done

Для этих подкоманд запусти MB Manager subagent:

```
Task(
  prompt="<содержимое ~/.claude/skills/memory-bank/agents/mb-manager.md>

action: <действие>

<описание задачи и контекст из текущей сессии>",
  subagent_type="general-purpose",
  model="sonnet",
  description="MB Manager: <действие>"
)
```

Конкретные actions:
- **context** / **(пусто)**: `action: context`
- **start**: `action: context` — расширенный, прочитай также активный план целиком
- **search <query>**: `action: search <query>` где query = остаток `$ARGUMENTS` после "search"
- **note <topic>**: `action: note <topic>` + передай описание что было сделано в текущей сессии
- **tasks**: `action: tasks`
- **done**: `action: actualize` + `action: note` — передай полное описание работы текущей сессии. MB Manager должен:
  1. Актуализировать все core files
  2. Создать заметку по выполненной работе
  3. Дописать progress.md

### update

Актуализация core files с автоматическим анализом текущего состояния проекта.

В отличие от `done`, **update** не создаёт заметку и не требует описания сессии — агент сам анализирует:

1. **Собери метрики через language-agnostic скрипт**:
```bash
# Детектит стек (python/go/rust/node/multi), выводит key=value формат:
#   stack=<stack>
#   test_cmd=<cmd>
#   lint_cmd=<cmd>
#   src_count=<N>
# Для unknown-стека возвращает пустые значения с warning на stderr (не падает).
# Override через .memory-bank/metrics.sh если нужны кастомные метрики.
bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh

# Опционально — запустить тесты и зафиксировать статус:
bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh --run

# Git-контекст
git log --oneline -5
git diff --stat HEAD~3 2>/dev/null | tail -5
```

2. **Запусти MB Manager** с собранными метриками:
```
Agent(
  prompt="<содержимое ~/.claude/skills/memory-bank/agents/mb-manager.md>

action: actualize

Текущие метрики из кода (из mb-metrics.sh):
- Stack: <detected>
- Tests: <test_status или предложить запустить вручную>
- Source files: <src_count>
- Lint: <lint output если запускался>
- Последние коммиты: <git log>
- Изменённые файлы: <git diff stat>

Обнови core files (STATUS метрики, checklist, plan фокус) на основе РЕАЛЬНЫХ данных из кода. Не полагайся на описание — проверяй через grep/find/bash.",
  subagent_type="general-purpose",
  model="sonnet"
)
```

3. Покажи пользователю что обновлено.

**Note:** если `mb-metrics.sh` вернул `stack=unknown`, предупреди пользователя что auto-метрики недоступны и предложи создать `.memory-bank/metrics.sh` с кастомной логикой (см. `references/templates.md`).

### doctor

Диагностика и исправление рассинхронов ВНУТРИ Memory Bank.

Запусти MB Doctor subagent:

```
Agent(
  prompt="<содержимое ~/.claude/skills/memory-bank/agents/mb-doctor.md>

action: doctor

Проверь консистентность всех core files в .memory-bank/:
- plan.md статусы vs checklist.md
- STATUS.md метрики vs реальные (pytest, source files)
- STATUS.md ограничения vs реальный код
- BACKLOG.md vs plan.md
- progress.md completeness
- Файлы планов в plans/ vs их статусы
- Дубликаты, устаревшие ссылки",
  subagent_type="general-purpose",
  model="sonnet"
)
```

Покажи отчёт пользователю: что найдено, что исправлено, что требует решения.

### index

Быстрая операция, без subagent:
```bash
bash ~/.claude/skills/memory-bank/scripts/mb-index.sh
```
Покажи результат пользователю.

### plan <type> <topic>

1. Создай файл плана:
```bash
bash ~/.claude/skills/memory-bank/scripts/mb-plan.sh <type> "<topic>"
```
2. **Сам заполни план** по правилам из `~/.claude/skills/memory-bank/SKILL.md` (секция "Правила создания планов"):
   - Контекст: проблема, причина, ожидаемый результат
   - Этапы: каждый с DoD по SMART, тестирование (TDD)
   - Риски и mitigation
   - Gate: критерий успеха

Если type не указан — спроси пользователя. Допустимые: feature, fix, refactor, experiment.

### verify

Верификация выполнения плана — проверка что код соответствует плану, все DoD выполнены, нет пропусков.

1. Найди активный план в `.memory-bank/plans/` (не в `done/`). Если планов несколько — используй самый свежий или тот, который указан в аргументах.
2. Запусти Plan Verifier subagent:

```
Task(
  prompt="<содержимое ~/.claude/skills/memory-bank/agents/plan-verifier.md>

Файл плана: <путь к плану>

Контекст: <описание текущей работы, какие этапы считаются завершёнными>",
  subagent_type="general-purpose",
  model="sonnet",
  description="Plan Verifier: проверка плана"
)
```

3. Получи отчёт от Plan Verifier. Покажи пользователю.
4. Если есть CRITICAL проблемы — **исправь их** перед продолжением.
5. Если есть WARNING — сообщи пользователю и спроси нужно ли исправлять.

**ВАЖНО:** `/mb verify` **ОБЯЗАТЕЛЬНО** вызывается перед `/mb done` если работа велась по плану. Не закрывай план без верификации.

### map [focus]

Сканирование кодовой базы и генерация структурированных MD-документов в `.memory-bank/codebase/`.

Значения `focus` (первое слово после `map`):
- `stack` — только STACK.md (языки, runtime, интеграции)
- `arch` — только ARCHITECTURE.md (слои, структура, точки входа)
- `quality` — только CONVENTIONS.md (naming, стиль, тестирование)
- `concerns` — только CONCERNS.md (tech debt, риски)
- `all` (default, если focus не указан) — все 4 документа

Запусти MB Codebase Mapper subagent:

```
Agent(
  prompt="<содержимое ~/.claude/skills/memory-bank/agents/mb-codebase-mapper.md>

focus: <stack|arch|quality|concerns|all>

Проанализируй текущий проект и запиши MD-документы напрямую в `.memory-bank/codebase/`. Используй `mb-metrics.sh` для детекции стека, следуй шаблонам ≤70 строк, возвращай только confirmation.",
  subagent_type="general-purpose",
  model="sonnet",
  description="MB Codebase Mapper: focus=<focus>"
)
```

**После завершения:**
- Новые/обновлённые MD лежат в `.memory-bank/codebase/{STACK,ARCHITECTURE,CONVENTIONS,CONCERNS}.md`
- `/mb context` теперь автоматически показывает 1-строчный summary каждого MD
- `/mb context --deep` показывает полное содержимое codebase-документов

Сообщи пользователю: какие документы созданы/обновлены, определённый стек, предложи `/mb context --deep` для полного контекста.

### init

Инициализация Memory Bank в новом проекте. Создай структуру:

```bash
mkdir -p .memory-bank/{experiments,plans/done,notes,reports}
```

Затем создай минимальные core файлы:
- `STATUS.md` — заголовок проекта, "Текущая фаза: Начало"
- `plan.md` — "Текущий фокус: определить"
- `checklist.md` — пустой чеклист
- `RESEARCH.md` — заголовок + пустая таблица гипотез
- `BACKLOG.md` — заголовок + пустые секции (Идеи HIGH/LOW, ADR)
- `progress.md` — заголовок
- `lessons.md` — заголовок

Шаблоны — в `~/.claude/skills/memory-bank/references/templates.md`.

---

## Общие правила

- Если `.memory-bank/` не существует и команда не `init` — сообщи `[MEMORY BANK: INACTIVE]` и предложи `/mb init`
- После выполнения — покажи пользователю краткое резюме результата
- progress.md = APPEND-ONLY
- Нумерация сквозная: H-NNN, EXP-NNN, ADR-NNN
