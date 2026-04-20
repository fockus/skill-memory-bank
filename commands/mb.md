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
| `compact [--dry-run\|--apply]` | Status-based decay: plans в done/ >60d → BACKLOG archive, low-importance notes >90d → notes/archive/. Active планы НЕ трогаются. `--dry-run` (default) — reasoning only |
| `import --project <path> [--since YYYY-MM-DD] [--apply]` | Bootstrap MB из Claude Code JSONL (`~/.claude/projects/<slug>/*.jsonl`). Extract: progress.md (daily), notes/ (arch discussions heuristic), PII auto-wrap. Dedup SHA256 + resume state |
| `graph [--apply] [src_root]` | Multi-language code graph: Python (stdlib `ast`, always on) + Go/JS/TS/Rust/Java (via tree-sitter, opt-in через `pip install tree-sitter tree-sitter-go ...`). Output: `codebase/graph.json` (JSON Lines) + `codebase/god-nodes.md` (top-20 by degree). Incremental SHA256 cache |
| `tags [--apply] [--auto-merge]` | Normalize frontmatter tags: detect synonyms via Levenshtein ≤2 vs closed vocabulary, propose merges. `--auto-merge` применяет только distance ≤1. Vocabulary в `.memory-bank/tags-vocabulary.md` (fallback — `references/tags-vocabulary.md`). `mb-index-json.py` авто-kebab-case |
| `init [--minimal\|--full]` | Инициализировать Memory Bank. `--full` (default): + RULES copy + CLAUDE.md с автодетектом стека. `--minimal`: только структура |
| `help [subcommand]` | Справка. Без аргумента — список всех подкоманд. С аргументом — детали конкретной (`/mb help compact`, `/mb help tags`, ...) |
| `deps [--install-hints]` | Проверка зависимостей (required: python3/jq/git; optional: rg/shellcheck/tree-sitter/PyYAML). `--install-hints` — OS-specific install commands |
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
1. Pre-flight: проверяет что `~/.claude/skills/skill-memory-bank` — git repo с чистым working tree
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

### compact [--dry-run|--apply]

Status-based archival decay. Очищает старые выполненные планы и неиспользуемые low-importance заметки, **не трогая активную работу**.

**Критерии (AND, не OR):**

| Кандидат | Age threshold | Done-signal (обязателен) |
|----------|---------------|---------------------------|
| Plan в `plans/done/` | `>60d` mtime | Primary: уже физически в `plans/done/` |
| Plan в `plans/*.md` (active location) | `>60d` mtime | Метка `✅` / `[x]` в `checklist.md` строки с basename, ИЛИ упоминание в `progress.md`/`STATUS.md` как `завершён\|done\|closed\|shipped` |
| Note в `notes/*.md` | `>90d` mtime | `importance: low` в frontmatter + **нет** референсов basename в `plan.md`/`STATUS.md`/`checklist.md`/`RESEARCH.md`/`BACKLOG.md` |

**Safety-net:** active plans (not done) — **НЕ архивируются** даже >180d. Вместо этого warning "план X старше 180d, но не done — проверь актуальность".

**Эффекты `--apply`:**
- Plans → компрессия в 1 строку в `BACKLOG.md ## Archived plans` секцию, файл удалён. Ссылка на исходник в формате `(was: plans/done/<file>.md)` — git history сохраняет полный текст.
- Notes → move в `notes/archive/` + body сжат до 3 непустых строк + marker `<!-- archived on YYYY-MM-DD -->`. Entries получают `archived: true` в `index.json`.
- Touched `.memory-bank/.last-compact` timestamp.

`--dry-run` (default) — reasoning per candidate на stdout, 0 file changes.

Выполни напрямую (systems-level, LLM не нужен для decision logic — она deterministic):

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-compact.sh $ARGS_AFTER_COMPACT
```

**Поиск в архиве:** default `mb-search` НЕ находит archived. Opt-in через `mb-search.sh --include-archived <query>` или `--include-archived --tag <tag>`.

**Типичный сценарий:**
```
User: /mb compact
→ dry-run output:
  mode=dry-run
  plans_candidates=2
  notes_candidates=5
  candidates=7

  # Plans to archive:
    archive: plans/done/2026-01-10_feature_x.md (reason=in_done_dir, age=100d)
    archive: plans/done/2026-02-01_fix_auth.md (reason=in_done_dir, age=78d)

  # Notes to archive:
    archive: notes/2025-12-15_experiment.md (reason=low_age_unref, age=125d)
    ...

  # Warnings — active plans older than 180d:
    warning: plans/2025-09-01_long_feature.md is 230d old but not done — проверь актуальность

User: /mb compact --apply
→ [apply] archived plan: plans/done/2026-01-10_feature_x.md (reason=in_done_dir)
  [apply] archived note: notes/2025-12-15_experiment.md → notes/archive/
  ...
```

### import --project <path> [--since YYYY-MM-DD] [--apply]

Bootstrap Memory Bank из транскриптов Claude Code JSONL. Cold-start за секунды вместо недель наработки вручную.

**Источник:** `~/.claude/projects/<slug>/*.jsonl` — Claude Code хранит там все session transcripts. Slug строится из путей проекта (например `-Users-fockus-Apps-X` для `/Users/fockus/Apps/X`).

**Extract strategy:**
- `progress.md` — daily-grouped секции `## YYYY-MM-DD (imported)` с summary (N user turns + M assistant replies + первые 120 chars первого user-запроса)
- `notes/` — heuristic architectural discussions: ≥3 consecutive assistant messages >1K chars → note `YYYY-MM-DD_NN_<topic-slug>.md` с frontmatter `importance: medium`, tags `[imported, discussion]`, body = first + last message compressed

**Safety:**
- `--dry-run` (default) — stdout summary (jsonls/events/days/notes counts), 0 file changes
- `--apply` — выполняет writes + touches `.memory-bank/.import-state.json`
- **Dedup:** SHA256(timestamp + first 500 chars text) persisted в state — 2 запуска подряд идемпотентны
- **PII auto-wrap:** email + API-key (`sk-...`, `sk-ant-...`, `Bearer <long>`, `gh[pousr]_<long>`) regex → `<private>...</private>`. Intersection с Этапом 3 — imported данные защищены от leak в index.json/search
- **Resume:** `.import-state.json` содержит `seen_hashes` — повторный импорт пропускает already-seen events
- **Broken JSONL line:** skip с warning, остальное продолжает парситься

Выполни напрямую:

```bash
python3 ~/.claude/skills/memory-bank/scripts/mb-import.py $ARGS_AFTER_IMPORT
```

**Типичный сценарий (cold-start):**
```
User: /mb import --project ~/.claude/projects/-Users-fockus-Apps-myproject/ --since 2026-03-01
→ dry-run output:
  jsonls=5
  events=342
  days=18
  notes=12
  mode=dry-run

User: /mb import --project ~/.claude/projects/-Users-fockus-Apps-myproject/ --since 2026-03-01 --apply
→ writes progress.md (18 daily sections) + 12 notes → state saved
  jsonls=5 events=342 days=18 notes=12 mode=apply
```

**Ограничения v2.2:**
- Summarization сейчас deterministic (first+last chars), не LLM. Haiku-powered compression — backlog для v2.3+ если качество summaries окажется недостаточным
- Debug-session detection для `lessons.md` — TODO (v2.2+)
- STATUS.md seed — только manual

### graph [--apply] [src_root]

Построение code graph для Python-части проекта через stdlib `ast` (0 new deps). Заменяет `grep` для вопросов "где вызывается X?", "какие classes наследуются от Y?", "что импортируется из model.py?" — детерминистично, быстро, incremental.

**Что парсит:**
- **Nodes:** module (per file), function (top-level + nested), class
- **Edges:** `import` (import X / from Y import Z), `call` (func() / obj.method()), `inherit` (class Child(Parent))

**Output (`--apply`):**
- `<mb>/codebase/graph.json` — JSON Lines (одна node/edge на строку, grep-friendly, streamable)
- `<mb>/codebase/god-nodes.md` — топ-20 узлов по degree (in + out), с file:line + kind
- `<mb>/codebase/.cache/<hash>.json` — per-file SHA256 → parsed entities

**Incremental:** если `sha256(file_content)` совпадает с cached — skip re-parse. На большом repo второй прогон моментальный.

**Safety:**
- `--dry-run` (default) — stdout summary (nodes/edges/reparsed/cached), 0 file changes
- `--apply` — пишет все outputs + обновляет cache
- Broken syntax → skip с warning, батч продолжается
- `.venv/`, `__pycache__/`, `.*/` — исключены

Выполни напрямую:

```bash
python3 ~/.claude/skills/memory-bank/scripts/mb-codegraph.py $ARGS_AFTER_GRAPH
```

**Типичный сценарий:**
```
User: /mb graph
→ dry-run output:
  nodes=52
  edges=388
  reparsed=3
  cached=0
  mode=dry-run

User: /mb graph --apply
→ nodes=52 edges=388 reparsed=3 cached=0 mode=apply
  [writes codebase/graph.json + god-nodes.md + .cache/]

# Изменил 1 файл, перезапустил:
User: /mb graph --apply
→ reparsed=1 cached=2 — один файл re-parsed, два из кеша
```

**Пример top god-nodes (dogfood на этом repo):**
```
| # | Name          | Kind     | File:Line            | Degree |
|---|---------------|----------|----------------------|--------|
| 1 | run_import    | function | mb-import.py:185     | 60     |
| 2 | main          | function | mb-index-json.py:187 | 23     |
| 3 | _atomic_write | function | mb-import.py:157     | 22     |
```

**Интеграция с `mb-codebase-mapper`:** агент использует `graph.json` как источник для разделов CONVENTIONS и CONCERNS вместо grep (backlog для v2.3).

**Поддержка языков (v2.2 + Stage 6.5):**
- **Всегда работает** (stdlib ast): Python (`.py`)
- **Opt-in** (требует tree-sitter + grammars): Go (`.go`), JavaScript (`.js`/`.jsx`/`.mjs`), TypeScript (`.ts`/`.tsx`), Rust (`.rs`), Java (`.java`)
- Install tree-sitter: `pip install tree-sitter tree-sitter-go tree-sitter-javascript tree-sitter-typescript tree-sitter-rust tree-sitter-java`
- Без tree-sitter: non-Python файлы тихо пропускаются (graceful degradation). `HAS_TREE_SITTER` флаг в скрипте отражает статус
- Skipped directories: `.venv`, `node_modules`, `__pycache__`, `.git`, `target`, `dist`, `build`, любые `.*`

**Ограничения:**
- Type inference отсутствует — edges работают на именах (call к `foo()` не различает модули с одноимённой функцией). Разрешение имён через imports — TODO v2.3+
- Tree-sitter extractor упрощён (MVP): не все edge cases языка — если увидишь пропущенный узел, open issue
- `god-nodes.md` wiki/ per-node documentation — отложено (YAGNI до реального запроса)
- C/C++/Ruby/PHP/Kotlin/Swift — не поддержаны (добавить по требованию через новую запись в `_TS_LANG_CONFIG`)

### deps [--install-hints]

Проверка всех required + optional зависимостей skill'а. Выполняется автоматически перед `install.sh` (step 0), доступна standalone через `/mb deps`.

**Required (exit 1 если отсутствуют):**
- `bash` — runtime для shell-скриптов
- `python3` — для `mb-index-json.py`, `mb-import.py`, `mb-codegraph.py`, hooks
- `jq` — для `session-end-autosave.sh`, `block-dangerous.sh`, `file-change-log.sh` (JSON parse из hook stdin)
- `git` — для `mb-upgrade.sh`, version tracking

**Optional (warning, не blocker):**
- `rg` (ripgrep) — ускоряет `mb-search`, fallback на grep
- `shellcheck` — только для dev (CI lint)
- `tree_sitter` (Python package) + grammars — multi-language `/mb graph` (Go/JS/TS/Rust/Java). Без него работает только Python
- `PyYAML` — strict YAML в frontmatter, fallback на simple parser

**Output format** (key=value, machine-parseable):
```
dep_bash=ok
dep_python3=ok
dep_jq=missing
dep_git=ok
...
deps_required_missing=1
deps_optional_missing=2
```

**Install hints** — `--install-hints` выводит OS-specific команды (brew/apt/dnf/pacman detected через `/etc/os-release`).

Выполни напрямую:

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-deps-check.sh $ARGS_AFTER_DEPS
```

**Типичный сценарий — первая установка:**
```
User: bash install.sh
→ [0/7] Dependency check
  ❌ dep_jq=missing
  ═══ Required tools missing — install before proceeding ═══
    jq: brew install jq
  Exit 1

User: brew install jq && bash install.sh
→ [0/7] ✅ All required dependencies present.
  [1/7] Rules → ...continues
```

**Override:** `MB_SKIP_DEPS_CHECK=1 bash install.sh` — пропускает preflight (CI / isolated envs где tools проверяются иначе).

### help [subcommand]

Справка по подкомандам `/mb`. Single source of truth — читает `~/.claude/skills/memory-bank/commands/mb.md` напрямую.

**Режимы (первое слово после `help`):**

1. **`/mb help`** (без аргумента) — вывести router-таблицу всех подкоманд с кратким описанием одной строкой.
2. **`/mb help <subcommand>`** — извлечь и показать детальный блок реализации конкретной подкоманды (разделы вида `### <subcommand>`).

**Алгоритм для агента:**

```bash
SKILL_MD="$HOME/.claude/skills/memory-bank/commands/mb.md"
SUB="$SUBCOMMAND_ARG"  # первое слово после "help", может быть пустым

SKILL_MD="$SKILL_MD" SUB="$SUB" python3 - <<'PY'
import os, sys
path = os.environ["SKILL_MD"]
sub = os.environ.get("SUB", "").strip()
lines = open(path, encoding="utf-8").read().splitlines()

if not sub:
    # Mode 1: router table — between "### Роутинг" and next "---"
    in_section = False
    for line in lines:
        if line.startswith("### Роутинг"):
            in_section = True
            continue
        if in_section and line.startswith("---"):
            break
        if in_section:
            print(line)
    print("\nDetails: /mb help <subcommand>  (e.g. /mb help compact)")
    sys.exit(0)

# Mode 2: extract "### SUB" block (exact, space-after, or bracket-after)
header = f"### {sub}"
in_block = False
for line in lines:
    is_header = line == header or line.startswith(header + " ") or line.startswith(header + "[")
    if is_header:
        in_block = True
        print(line)
        continue
    if in_block and line.startswith("### "):
        break
    if in_block and line.rstrip() == "---":
        break
    if in_block:
        print(line)
PY
```

**Примеры:**

```
User: /mb help
→ выводит роутер-таблицу с 18 подкомандами

User: /mb help compact
→ выводит полную секцию "### compact [--dry-run|--apply]" с логикой,
  примерами, ограничениями

User: /mb help tags
→ выводит секцию "### tags [--apply] [--auto-merge]"
```

**Не путай с:**
- `/help` — built-in Claude Code команда (не skill).
- `commands/catchup.md` / `commands/start.md` / `commands/done.md` — standalone top-level slash-команды (lightweight), не подкоманды `/mb`.

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
