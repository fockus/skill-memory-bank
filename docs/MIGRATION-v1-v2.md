# Migration guide: v1 → v2

Этот документ описывает, как мигрировать существующую установку skill с версии 1.x на 2.0.0.

---

## TL;DR

```bash
# 1. Обновить исходник skill
cd ~/.claude/skills/skill-memory-bank
git fetch && git checkout v2.0.0

# 2. Переустановить (idempotent — существующие user hooks сохранятся)
./install.sh

# 3. В проектах, использующих .memory-bank/:
mv .planning/codebase .memory-bank/codebase 2>/dev/null || true
rm -f .memory-bank/index.json          # старый, будет пересоздан
python3 ~/.claude/skills/memory-bank/scripts/mb-index-json.py .memory-bank
```

Готово. Подробности ниже.

---

## Breaking changes

| # | Что | v1 | v2 | Действие |
|---|-----|-----|-----|----------|
| 1 | Команда инициализации | `/mb:setup-project` | `/mb init --full` | Обновить привычки / `.claude/commands/` — install.sh сам удалит `setup-project.md` |
| 2 | Агент маппинга | `codebase-mapper` (orphan, GSD-style) | `mb-codebase-mapper` | `install.sh` удаляет старый агент. В своих скриптах — заменить ссылки |
| 3 | Output codebase-документов | `.planning/codebase/` | `.memory-bank/codebase/` | `mv .planning/codebase .memory-bank/codebase` |
| 4 | Вызов subagent'ов из команд | `Task(prompt=..., subagent_type=...)` | `Agent(subagent_type=..., prompt=...)` | Автомат — install.sh заменит; в своих custom command'ах — обновить |
| 5 | Хардкод Python в `/mb update` | `.venv/bin/python -m pytest` | `bash mb-metrics.sh` | Автомат через install.sh |
| 6 | SKILL.md frontmatter | `user-invocable: false` (невалидно) | `name: memory-bank` | Автомат |

---

## Step-by-step миграция

### 1. Обновите исходник skill

```bash
cd ~/.claude/skills/skill-memory-bank
git fetch origin
git log HEAD..origin/main --oneline   # посмотреть что нового
git checkout v2.0.0                   # или `main` для bleeding-edge
```

Если вы модифицировали skill локально — сначала `git stash`.

### 2. Переустановите

```bash
./install.sh
```

Скрипт:
- Скопирует новые команды/агенты/хуки/скрипты
- **Сохранит ваши user hooks** в `settings.json` (протестировано e2e)
- **Сохранит ваши записи выше маркера** `[MEMORY-BANK-SKILL]` в `CLAUDE.md`
- Обновит `manifest` для последующего чистого uninstall

### 3. В каждом проекте с `.memory-bank/`

```bash
# (а) Перенести codebase-документы, если они были от старого codebase-mapper
if [ -d .planning/codebase ]; then
  mkdir -p .memory-bank/codebase
  mv .planning/codebase/*.md .memory-bank/codebase/ 2>/dev/null
fi

# (б) Удалить устаревший index.json (будет пересоздан при следующем /mb done)
rm -f .memory-bank/index.json

# (в) Пересоздать index под новый формат v2
python3 ~/.claude/skills/memory-bank/scripts/mb-index-json.py .memory-bank
```

### 4. Проверьте

```bash
# Все ли команды на месте
ls ~/.claude/commands/ | wc -l        # ожидаем 18

# Нет ли legacy-команды
ls ~/.claude/commands/setup-project.md 2>&1   # должна быть: No such file

# Агенты
ls ~/.claude/agents/                  # mb-codebase-mapper.md, не codebase-mapper.md

# VERSION marker
cat ~/.claude/skills/memory-bank/VERSION   # 2.0.0
```

### 5. Опционально: структурные маркеры в существующих планах

Если у вас есть активные планы в `.memory-bank/plans/*.md` без маркеров `<!-- mb-stage:N -->`, `mb-plan-sync.sh` использует fallback-regex и всё равно распарсит их. Но для будущих планов — `scripts/mb-plan.sh` шаблон уже включает маркеры автоматически.

Ручное добавление в старые планы:

```markdown
<!-- mb-stage:1 -->
### Этап 1: Существующий этап
```

---

## Что НЕ сломалось

- `.memory-bank/` структура (STATUS, plan, checklist, RESEARCH, BACKLOG, progress, lessons, notes/, plans/, experiments/, reports/) — 100% совместима
- Шаблоны core-файлов и их семантика
- Нумерация H-NNN, EXP-NNN, ADR-NNN, L-NNN — без изменений
- MB Manager action'ы (`context`, `search`, `note`, `actualize`, `tasks`) — тот же API
- `mb-doctor` сохранил интерфейс

---

## Rollback

Если что-то пошло не так — вернитесь к v1:

```bash
cd ~/.claude/skills/skill-memory-bank
./uninstall.sh               # снимет v2 установку (сохраняет backups)
git checkout v1.0.0
./install.sh                 # установит v1

# В проектах — `.memory-bank/` нетронут (uninstall не трогает project-level данные).
# Если перенесли `.planning/codebase/` → `.memory-bank/codebase/` — перенесите обратно.
```

Backup'ы ваших `CLAUDE.md` / `settings.json` создаются с суффиксом `.pre-mb-backup.<timestamp>`. Найти их:

```bash
ls ~/.claude/*.pre-mb-backup.*
```

---

## Известные проблемы

| Проблема | Workaround |
|----------|-----------|
| `PyYAML` не установлен — `mb-index-json.py` использует fallback-парсер. Он понимает `key: value` и `key: [a, b]`, но не вложенные структуры. | Установить `pip install pyyaml` для полной поддержки. Для простого frontmatter fallback достаточен. |
| В macOS `realpath -m` не работает (исправлено в v2) | Если использовали v1 на macOS — просто переустановите |
| `settings.json` может содержать дубликаты hook'ов от старых версий | `./uninstall.sh && ./install.sh` — идемпотентная переустановка очистит |

---

## Поддержка

- Issues: https://github.com/fockus/skill-memory-bank/issues
- CHANGELOG: [../CHANGELOG.md](../CHANGELOG.md)
- Версия: `cat ~/.claude/skills/memory-bank/VERSION`
