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
| `upgrade` | Обновить skill из GitHub (git pull + re-install). Флаги: `--check` (только проверить), `--force` (без подтверждения) |
| `init [--minimal\|--full]` | Инициализировать Memory Bank. `--full` (default): + RULES copy + CLAUDE.md с автодетектом стека. `--minimal`: только структура |
| (нераспознанное) | Поиск по `$ARGUMENTS` |

---

## Реализация подкоманд

### context / start / search / note / tasks / done

Для этих подкоманд запусти MB Manager subagent:

```
Agent(
  subagent_type="general-purpose",
  model="sonnet",
  description="MB Manager: <действие>",
  prompt="<содержимое ~/.claude/skills/memory-bank/agents/mb-manager.md>

action: <действие>

<описание задачи и контекст из текущей сессии>"
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
  4. **После успешного agent call** — выполнить `touch .memory-bank/.session-lock`. Это маркер для SessionEnd hook: ручной `/mb done` выполнен, auto-capture пропустит эту сессию (см. `hooks/session-end-autosave.sh`, `MB_AUTO_CAPTURE` env var).

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
# → выводит путь к созданному файлу, например:
# .memory-bank/plans/2026-04-19_refactor_skill-v2.md
```
2. **Сам заполни план** по правилам из `~/.claude/skills/memory-bank/SKILL.md` (секция "Правила создания планов"):
   - Контекст: проблема, причина, ожидаемый результат
   - Этапы: каждый с DoD по SMART, тестирование (TDD). Используй маркеры `<!-- mb-stage:N -->` перед каждым `### Этап N: <name>` — они нужны для автосинхронизации.
   - Риски и mitigation
   - Gate: критерий успеха
3. Запусти синхронизацию с checklist.md + plan.md:
```bash
bash ~/.claude/skills/memory-bank/scripts/mb-plan-sync.sh <путь к плану>
```
   Скрипт добавит отсутствующие секции `## Этап N: <name>` в checklist.md и обновит блок `<!-- mb-active-plan -->` в plan.md. Идемпотентно — можно повторять при правке плана.

Если type не указан — спроси пользователя. Допустимые: feature, fix, refactor, experiment.

### verify

Верификация выполнения плана — проверка что код соответствует плану, все DoD выполнены, нет пропусков.

1. Найди активный план в `.memory-bank/plans/` (не в `done/`). Если планов несколько — используй самый свежий или тот, который указан в аргументах.
2. Запусти Plan Verifier subagent:

```
Agent(
  subagent_type="general-purpose",
  model="sonnet",
  description="Plan Verifier: проверка плана",
  prompt="<содержимое ~/.claude/skills/memory-bank/agents/plan-verifier.md>

Файл плана: <путь к плану>

Контекст: <описание текущей работы, какие этапы считаются завершёнными>"
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

### upgrade

Обновление skill до актуальной версии из GitHub. Требует `git clone`-установку.

Флаги (первое слово после `upgrade`):
- (без флагов) — проверить и с подтверждением применить
- `--check` — только проверить (exit 1 если доступно обновление, exit 0 если up-to-date)
- `--force` — применить без интерактивного подтверждения

Выполни напрямую (без subagent — это systems-level операция, LLM не нужен):

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-upgrade.sh $ARGS_AFTER_UPGRADE
```

Скрипт выполняет:
1. Pre-flight: проверяет что `~/.claude/skills/claude-skill-memory-bank` — git repo с чистым working tree
2. Читает `VERSION` файл и local commit hash
3. `git fetch origin` + сравнивает local vs remote (ahead/behind)
4. Показывает список ожидающих коммитов (`git log HEAD..origin/main`)
5. Если `--check` — exit с кодом состояния
6. Если есть обновления и не `--force` — запрашивает подтверждение
7. При подтверждении: `git pull --ff-only` + re-run `install.sh` (идемпотентный merge hooks / команд)
8. Выводит `local → new` версию

**Типичный сценарий:**
```
User: /mb upgrade
→ скрипт fetch, показывает: "3 behind, 0 ahead"
→ показывает 3 последних коммита
→ запрашивает: "Применить 3 обновлений? (y/n)"
→ user: y
→ git pull + bash install.sh → manifest обновлён
→ "Skill обновлён: 2.0.0-dev (cd65d0a) → 2.1.0 (abc1234)"
```

**Ошибки:**
- Skill не git-clone → hint на переустановку через clone
- Dirty working tree → hint на `git stash`/`git checkout --`
- Divergent branches → hint на manual pull
- Non-interactive без `--force` → error

**ВАЖНО:** Skill repo (`~/.claude/skills/claude-skill-memory-bank/`) — это ИСХОДНИК skill'а. После `git pull` нужно re-run `install.sh` чтобы скопировать новые файлы в `~/.claude/{commands,agents,hooks,skills}/`. Скрипт делает это автоматически.

### init [--minimal|--full]

Инициализация Memory Bank в новом проекте.

**Режимы** (первое слово после `init`):
- `--minimal` — только `.memory-bank/` структура + core-файлы. Для продвинутых пользователей, которые сами напишут CLAUDE.md.
- `--full` (default, если флаг не указан) — `.memory-bank/` + `RULES.md` copy + авто-детект стека + генерация `CLAUDE.md` + предложение symlink `.planning/`.

---

#### Step 1: Создай структуру

```bash
mkdir -p .memory-bank/{experiments,plans/done,notes,reports,codebase}
```

Core файлы (шаблоны — `~/.claude/skills/memory-bank/references/templates.md`):
- `STATUS.md` — заголовок проекта, "Текущая фаза: Начало"
- `plan.md` — "Текущий фокус: определить", секция `## Active plan` с маркерами `<!-- mb-active-plan -->` / `<!-- /mb-active-plan -->` (для автосинхронизации)
- `checklist.md` — пустой чеклист
- `RESEARCH.md` — заголовок + пустая таблица гипотез
- `BACKLOG.md` — заголовок + пустые секции (Идеи HIGH/LOW, ADR)
- `progress.md` — заголовок
- `lessons.md` — заголовок

**Если `--minimal` — остановись здесь.** Сообщи: `[MEMORY BANK: INITIALIZED]` + подсказка `/mb start`.

---

#### Step 2: Copy RULES (только `--full`)

```bash
cp ~/.claude/RULES.md .memory-bank/RULES.md
# Если уже существует — сравни через diff, спроси пользователя прежде чем перезаписывать
```

---

#### Step 3: Auto-detect стека (только `--full`)

Запусти `mb-metrics.sh` для детекции стека + дополни более детальной информацией:

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh
# → stack, test_cmd, lint_cmd, src_count
```

Дополни информацией о фреймворках (grep imports/deps):
- Python: FastAPI, Django, Flask (pyproject.toml + imports)
- Node: Next.js, Express, Nest (package.json deps)
- Go: gin, echo, fiber (go.mod)
- Frontend: React/Vue/Angular/Svelte + FSD слои (проверь `src/app/`, `src/pages/`, `src/features/`, `src/entities/`, `src/shared/`)

Сохрани результаты: `{LANGUAGE}`, `{FRAMEWORK}`, `{STRUCTURE}`, `{TOOLS}`.

---

#### Step 4: Сгенерируй CLAUDE.md (только `--full`)

Используй шаблон из `~/.claude/skills/memory-bank/references/claude-md-template.md`. В шаблон подставь `{LANGUAGE}`, `{FRAMEWORK}`, `{TOOLS}`, структуру проекта, список ключевых зависимостей.

Обязательные секции в сгенерированном CLAUDE.md:
- **Project** — название, описание
- **Technology Stack** — языки, runtime, фреймворки, package manager
- **Conventions** — naming patterns (детектируй из существующего кода), code style
- **Architecture** — для backend: Clean Architecture направление; для frontend: FSD layers
- **Rules** — ссылка на `~/.claude/RULES.md` + `.memory-bank/RULES.md` + краткие критические правила (TDD, Contract-First, Clean Arch/FSD, SOLID пороги, coverage)
- **Memory Bank** — команда `/mb`, ключевые файлы

**Покажи пользователю draft перед записью.** Спроси: "Записать CLAUDE.md? Нужно что-то добавить/изменить?"

---

#### Step 5: `.planning/` symlink (только `--full`, опционально)

Если `.planning/` уже существует (от GSD/других tools) и `.memory-bank/.planning/` не существует:

```
Предлагаю перенести .planning/ внутрь .memory-bank/:
  mv .planning .memory-bank/.planning
  ln -s .memory-bank/.planning .planning

Это объединит артефакты проекта в одной директории.
Symlink сохранит совместимость с GSD.

Сделать? (y/n)
```

Если `y` — выполни. Если `n` — оставить как есть.

---

#### Step 6: Резюме

Выведи:
- Созданные файлы: `.memory-bank/` + `CLAUDE.md` (если `--full`)
- Detected stack: `{language}`, `{framework}`, `{tools}`
- Сообщи: `[MEMORY BANK: ACTIVE]`
- Предложи следующий шаг: `/mb start` или (если в проекте есть план) `/mb plan feature "<topic>"`

---

## Общие правила

- Если `.memory-bank/` не существует и команда не `init` — сообщи `[MEMORY BANK: INACTIVE]` и предложи `/mb init`
- После выполнения — покажи пользователю краткое резюме результата
- progress.md = APPEND-ONLY
- Нумерация сквозная: H-NNN, EXP-NNN, ADR-NNN
