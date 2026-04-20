---
description: "Install Memory Bank cross-agent adapters into the current project"
allowed-tools: [Bash, Read, AskUserQuestion]
---

# /install — Install Memory Bank for this project

Устанавливает Memory Bank и/или cross-agent adapters в текущий проект. Работает в Claude Code, OpenCode, Codex и любом агенте с Bash-инструментом.

## Входные аргументы

`$ARGUMENTS` — опциональный список клиентов через запятую (обходит интерактив).

Допустимые клиенты: `claude-code`, `cursor`, `windsurf`, `cline`, `kilo`, `opencode`, `pi`, `codex`.

## Алгоритм

### Step 1 — Проверь что `memory-bank` CLI доступен

```bash
command -v memory-bank >/dev/null 2>&1 && memory-bank version
```

Если CLI **не установлен** — сообщи пользователю и предложи установить:

```
memory-bank CLI не найден. Установи одним из способов:

  pipx install memory-bank-skill           # рекомендуемый (cross-platform)
  brew install fockus/tap/memory-bank      # macOS / Linuxbrew
  pip install memory-bank-skill            # альтернатива

Затем перезапусти /install.
```

И завершай без запуска adapter'ов.

### Step 2 — Определи список клиентов

Если `$ARGUMENTS` пустой — спроси пользователя:

**В Claude Code:** используй `AskUserQuestion`:

```
Спроси multipleChoice: "Which AI coding agents should share this project's memory bank?"
Опции (multiSelect=true):
  - claude-code (recommended)
  - cursor
  - windsurf
  - cline
  - kilo
  - opencode
  - codex
  - pi
```

Если пользователь ничего не выбрал — дефолт `claude-code`.

**В другом агенте** (OpenCode, Codex и т.д.), без `AskUserQuestion`:

Выведи список, попроси ввести номера/имена:

```
Which agents do you want?
  [1] claude-code (recommended)
  [2] cursor
  [3] windsurf
  [4] cline
  [5] kilo
  [6] opencode
  [7] pi
  [8] codex

Reply with comma-separated names or numbers (e.g. "claude-code,cursor" or "1,2,5"),
"all" for every client, or press Enter for claude-code only.
```

Распарси ответ, нормализуй в список имён (через запятую).

Если `$ARGUMENTS` непустой — используй его напрямую, валидация произойдёт в CLI.

### Step 3 — Выполни установку

```bash
CLIENTS="<selected-list>"
memory-bank install --clients "$CLIENTS" --project-root "$PWD"
```

Покажи вывод пользователю (CLI сам делает красивый отчёт по шагам и итоговым adapter'ам).

### Step 4 — Resume hint

После успешной установки:

```
✓ Memory Bank installed for: <clients>
  Project root: <PWD>

Next steps:
  • Initialize the memory bank:   /mb init
  • Load context in this session: /mb start
  • Plan a feature:               /mb plan feature <topic>
```

Если был установлен клиент, отличный от текущего (например, user в Claude Code, выбрал `cursor`) — напомни что для того клиента нужно зайти в его IDE, он там подхватит `.cursor/` / `.windsurf/` / etc. автоматически.

## Примеры

```
User: /install
Agent: [spawns AskUserQuestion multiselect] → user picks claude-code + cursor + windsurf
Agent: [runs] memory-bank install --clients claude-code,cursor,windsurf --project-root /path/to/project
Agent: ✓ Installed. Next: /mb init
```

```
User: /install cursor,opencode
Agent: [runs directly] memory-bank install --clients cursor,opencode
Agent: ✓ Installed cursor + opencode adapters. Next: /mb init
```

## Не путай с

- `/mb init` — инициализирует `.memory-bank/` **внутри проекта** (после того как skill установлен глобально).
- `install.sh` — shell-скрипт, который `memory-bank install` вызывает под капотом. Обычно не дергают напрямую.
- Глобальная установка самого CLI (`pipx install memory-bank-skill`) — делается один раз, до любого `/install`.

## Ошибки

- `memory-bank: command not found` → см. Step 1 (установи CLI сначала).
- `invalid client 'X'` → проверь список допустимых в Step 2.
- `bash not found on PATH` (Windows) → установи Git for Windows или WSL.
