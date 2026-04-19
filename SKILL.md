---
name: memory-bank
description: "Long-term project memory через `.memory-bank/` + RULES (TDD/SOLID/Clean Architecture/FSD/Mobile) + 18 dev commands. Use when working in a project with .memory-bank/ directory or when user explicitly asks for /mb, code rules, or dev-toolkit commands."
---

# Memory Bank Skill

Three-in-one skill для Claude Code:

1. **Memory Bank** — долговременная память проекта через `.memory-bank/` (STATUS, plan, checklist, RESEARCH, BACKLOG, progress, lessons, notes/, plans/, experiments/, reports/, codebase/).
2. **RULES** — глобальные правила разработки: TDD, Clean Architecture (backend), FSD (frontend), Mobile (iOS/Android UDF), SOLID, Testing Trophy.
3. **Dev toolkit** — 18 команд: `/mb`, `/commit`, `/review`, `/test`, `/plan`, `/pr`, `/adr`, `/contract`, `/security-review`, `/db-migration`, `/api-contract`, `/observability`, `/refactor`, `/doc`, `/changelog`, `/catchup`, `/start`, `/done`.

---

## Quick start

```bash
# Инициализация (auto-detect стека + генерация CLAUDE.md)
/mb init                 # то же что /mb init --full
/mb init --minimal       # только структура .memory-bank/

# Сессия
/mb start                # загрузить контекст
# ... работа, checklist.md обновляется по мере выполнения ...
/mb verify               # проверить соответствие плану (если был план)
/mb done                 # актуализировать + заметка + progress
```

---

## Workspace resolution

Memory Bank поддерживает внешнее хранение через `.claude-workspace`:

- Если в корне проекта есть `.claude-workspace` с `storage: external` и `project_id: <id>` → `mb_path = ~/.claude/workspaces/<id>/.memory-bank`
- Иначе → `mb_path = ./.memory-bank` (default).

При вызове MB Manager и скриптов — передавай resolved `mb_path`.

---

## Инструменты — shell-скрипты

Все в `~/.claude/skills/memory-bank/scripts/`. Работают с `.memory-bank/` в текущей директории или через `mb_path` аргумент.

| Скрипт | Назначение |
|--------|-----------|
| `mb-context.sh [--deep]` | Собрать контекст (STATUS + plan + checklist + RESEARCH + codebase summary). `--deep` показывает полный codebase |
| `mb-search.sh <q> [--tag t]` | Поиск. `--tag` — фильтрация через `index.json` |
| `mb-note.sh <topic>` | Создать `notes/YYYY-MM-DD_HH-MM_<topic>.md`. Collision-safe (`_2`/`_3`) |
| `mb-plan.sh <type> <topic>` | Создать `plans/YYYY-MM-DD_<type>_<topic>.md` с `<!-- mb-stage:N -->` маркерами |
| `mb-plan-sync.sh <plan>` | Синхронизировать план ↔ checklist + plan.md (идемпотентно) |
| `mb-plan-done.sh <plan>` | Закрыть план: `⬜→✅` + `mv` в `plans/done/` |
| `mb-metrics.sh [--run]` | Language-agnostic метрики (12 стеков). `--run` для `test_status=pass\|fail` |
| `mb-index.sh` | Реестр всех записей (core + notes/plans/experiments/reports) |
| `mb-index-json.py` | Построить `index.json` (frontmatter notes + lessons H3). Atomic |
| `mb-upgrade.sh [--check\|--force]` | Самообновление skill из GitHub |
| `_lib.sh` | Общие утилиты (source из других скриптов) |

---

## Агенты — subagents (sonnet)

| Agent | Когда вызывать | Prompt |
|-------|----------------|--------|
| `mb-manager` | `/mb context`, `search`, `note`, `tasks`, `done`, `update`, PreCompact hook | `agents/mb-manager.md` |
| `mb-doctor` | `/mb doctor` — рассинхроны в банке (через `mb-plan-sync.sh` сначала, Edit только для семантики) | `agents/mb-doctor.md` |
| `mb-codebase-mapper` | `/mb map [focus]` — сканирование кода → `.memory-bank/codebase/{STACK,ARCHITECTURE,CONVENTIONS,CONCERNS}.md` | `agents/mb-codebase-mapper.md` |
| `plan-verifier` | `/mb verify` — обязательно перед `/mb done` если работа по плану | `agents/plan-verifier.md` |

**НЕ ДЕЛЕГИРУЙ** subagent'у: создание планов, архитектурные решения, оценка ML-результатов — это работа главного агента.

### Формат вызова

```
Agent(
  subagent_type="general-purpose",
  model="sonnet",
  description="<описание>",
  prompt="<содержание agents/<agent>.md>\n\naction: <действие>\n\n<контекст>"
)
```

---

## Coexistence с native Claude Code memory

Claude Code имеет встроенный `auto memory` (кросс-проектный профиль пользователя в `~/.claude/projects/.../memory/`). Этот skill **не заменяет** его — они дополняют друг друга:

| Аспект | `.memory-bank/` | Native `auto memory` |
|--------|-----------------|----------------------|
| Scope | Проект | Пользователь, кросс-проектно |
| Что хранит | Status, plans, checklists, research, ADR, lessons | Предпочтения, роль, обратная связь |
| Владелец | Команда (через git) | Лично пользователь |

**Правило:** полезно коллеге, который завтра возьмёт проект → `.memory-bank/`. Полезно вам в другом проекте → native memory. Оба загружаются параллельно, не конфликтуют.

---

## Private content — `<private>...</private>` (since v2.1)

Markdown-синтаксис для исключения чувствительной информации (клиентские данные, API-ключи, partner names) из индекса и поиска:

```markdown
---
type: note
tags: [auth, partner-x]
importance: high
---

Обсудили с клиентом <private>Иван Иванов, +7-900-***</private>.
Интеграция с <private>api_key=sk-abc123...</private> запланирована на вторник.
```

**Защита:**
- Содержимое `<private>...</private>` **не попадает** в `index.json` (ни в `summary`, ни в `tags`)
- При `mb-search` выводе вместо секрета показывается `[REDACTED]` (inline) или `[REDACTED match in private block]` (multi-line)
- Entry получает флаг `has_private: true` для downstream фильтрации
- Unclosed `<private>` без `</private>` → весь хвост считается приватным (fail-safe)
- `hooks/file-change-log.sh` warn'ит при коммите файла с `<private>` блоком (напоминание проверить git)

**Двойное подтверждение для показа:**
```bash
# Отказ без env:
mb-search --show-private <query>
# [error] --show-private требует MB_SHOW_PRIVATE=1 env

# Только при явном opt-in:
MB_SHOW_PRIVATE=1 mb-search --show-private <query>
```

**Важно:** `<private>` защищает от утечки через `index.json` / `mb-search`, но **НЕ** фильтрует git-diff. Для полной защиты рассмотри `.gitattributes` фильтры или git hooks.

---

## Auto-capture (since v2.1)

SessionEnd hook автоматически дописывает placeholder-entry в `progress.md`, если сессия завершилась без явного `/mb done`. Никакой работы не теряется даже при забытом ручном actualize.

**Режимы (env `MB_AUTO_CAPTURE`):**
- `auto` (default) — hook пишет запись при закрытии сессии
- `strict` — hook пропускает, но выводит предупреждение в stderr (для команд где важен ручной actualize)
- `off` — полный noop

**Как это работает:**
- `/mb done` после успешного actualize пишет `.memory-bank/.session-lock` → hook видит свежий lock (<1h) и пропускает auto-capture (ручной уже выполнен)
- Без lock → hook добавляет короткую заметку в `progress.md`. Детали восстановит `/mb start` в следующей сессии (MB Manager дочитает JSONL-транскрипт).
- Concurrent-safe через короткий `.auto-lock` (30 сек) — не создаёт дубли при параллельных вызовах
- Идемпотентен по `session_id` — тот же session + день = одна запись

**Opt-out:** `export MB_AUTO_CAPTURE=off` в `~/.zshrc` или uninstall hook через `/mb upgrade` с флагом отключения (TBD).

---

## Ссылки

- Metadata protocol + `index.json` + 8 ключевых правил: `references/metadata.md`
- Создание планов + Plan Verifier: `references/planning-and-verification.md`
- Шаблоны: `references/templates.md`
- Структура файлов: `references/structure.md`
- Workflow: `references/workflow.md`
- CHANGELOG: `CHANGELOG.md`
- Migration v1→v2: `docs/MIGRATION-v1-v2.md`
- Slash-команда: `/mb` (роутинг)
