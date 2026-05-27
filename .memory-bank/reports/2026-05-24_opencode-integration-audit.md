# Отчёт: аудит интеграции OpenCode

Дата: 2026-05-24
Автор: AI-аудитор
Статус: готов к ревью

## Executive summary

Интеграция Memory Bank с OpenCode (самый мощный из 6 поддерживаемых хостов) имеет **8 продакшен-разрывов**.
2 критических (возможны runtime-ошибки или деградация UX), 4 средних (функциональные ограничения), 2 низких (документация/гигиена).
В рамках текущей сессии уже закрыты 2 критических (адаптер `adapters/opencode.sh` и тесты). Остальные требуют решения: либо фикс в рамках W0/W1, либо перенос в backlog.

---

## 1. Критические (HIGH)

### 1.1 Commands frontmatter — Claude-only поля

**Где:** `commands/*.md` (24 файла).
**Проблема:** Frontmatter содержит `allowed-tools: [..., Edit, Bash, Read]` — формат Claude Code. OpenCode ожидает `agent: <role>` и `subtask: true/false` для работы через Subtask API.
**Влияние:** OpenCode может игнорировать `allowed-tools` (не ломается), но не получает ролевой контекст при вызове через `opencode run`.
**Фикс:** Добавить `agent:` и `subtask:` в каждый command, либо ввести generic-поле `role:` которое парсится всеми хостами.
**Трудоёмкость:** ~1h (sed/awk массовая правка + review).
**Риски:** Низкие. Обратная совместимость с Claude Code сохраняется.

### 1.2 Отсутствует global skill alias

**Где:** `install.sh`.
**Проблема:** Для Claude Code `install.sh` создаёт `~/.claude/skills/memory-bank/` (symlink). Для OpenCode не делает `~/.config/opencode/skills/memory-bank/`.
**Влияние:** Пользователи OpenCode не могут вызвать skill как `/mb` без ручного `opencode skill install`.
**Фикс:** Добавить в `install.sh` блок для OpenCode: `mkdir -p ~/.config/opencode/skills/ && ln -s <skill_path> ~/.config/opencode/skills/memory-bank`.
**Трудоёмкость:** 10 мин.
**Риски:** Низкие.

---

## 2. Средние (MEDIUM)

### 2.1 SKILL.md — нет секции OpenCode

**Где:** `SKILL.md`.
**Проблема:** SKILL.md имеет секции "For Claude Code", "For Codex", "For Pi", "For Cursor", "For Windsurf". OpenCode отсутствует.
**Влияние:** Пользователи не знают, что OpenCode поддерживается и как включить (auto-discovery плагина).
**Фикс:** Добавить секцию с описанием `.opencode/plugins/*.js` auto-discovery и примером `opencode.json` если нужно.
**Трудоёмкость:** 15 мин.

### 2.2 Plugin hooks — недостаточная паритетность

**Где:** `adapters/opencode.sh` генерирует JS.
**Проблема:** Текущий плагин реализует: `onReady`, `tool.execute.before`, `experimental.session.compacting`, `event` (session idle/deleted).
Но в `references/hooks.md` задокументированы дополнительные bash-hooks: `mb-protected-paths-guard`, `mb-plan-sync-post-write`, `mb-ears-pre-write`, `mb-context-slim-pre-agent`, `mb-sprint-context-guard`, `file-change-log`.
OpenCode plugin их не имеет.
**Влияние:** Некоторые защитные механизмы (например, `mb-protected-paths-guard`) работают только через git-hooks-fallback, что менее надёжно.
**Фикс:** Расширить plugin JS дополнительными хуками, отображая bash-логику на TS обработчики. Это эпик, требует mapping каждого hook.
**Трудоёмкость:** 2–3h.
**Риски:** Средние. Ошибки в plugin JS сломают OpenCode для всех пользователей skill.

### 2.3 AGENTS.md — не оптимизирован под OpenCode

**Где:** `AGENTS.md`.
**Проблема:** `AGENTS.md` содержит generic инструкции ("plugin writes to `.opencode/`"), но не упоминает auto-discovery и не даёт примера `.opencode/commands/`.
**Влияние:** Новые пользователи не понимают, как команды регистрируются в OpenCode.
**Фикс:** Добавить 3 строки про auto-discovery и пример `.opencode/commands/mb-*.md`.
**Трудоёмкость:** 5 мин.

### 2.4 OpenCode agent definitions

**Где:** `agents/`.
**Проблема:** Нет `.opencode/agent/*.md` или глобального `~/.config/opencode/agent/` с определениями агентов (manager, verifier и т.д.).
**Влияние:** OpenCode не знает о role-based агентах skill; может использовать generic assistant.
**Фикс:** Создать `agents/opencode/*.md` с frontmatter под OpenCode.
**Трудоёмкость:** 30 мин.
**Риски:** Низкие. Фича, не баг.

---

## 3. Низкие (LOW)

### 3.1 Tests — нет syntax-check generated plugin JS

**Где:** `tests/bats/test_opencode_adapter.bats`.
**Проблема:** Тесты проверяют shell-логику генерации JS, но не запускают `node --check` на сгенерированном файле.
**Влияние:** Синтаксические ошибки в JS (например, unclosed brace) не ловятся в CI.
**Фикс:** Добавить `command -v node && node --check "$plugin_path"` в test setup.
**Трудоёмкость:** 5 мин.

### 3.2 tool.execute.before — review regex logic

**Где:** `adapters/opencode.sh` → plugin JS.
**Проблема:** `tool.execute.before` получает `(input, output)`. `input.args` содержит аргументы. Нынешняя реализация проверяет dangerous commands по `input.tool` и `input.args.cmd`. Нужно убедиться, что `output` не мутируется некорректно.
**Влияние:** Потенциальный bypass защиты если `output.args` имеет другую структуру.
**Фикс:** Написать unit test на plugin JS (mock input/output) и убедиться, что guard отрабатывает.
**Трудоёмкость:** 20 мин.

---

## 4. Найденные и исправленные в рамках текущей сессии

| ID | Проблема | Статус | Коммит/изменение |
|---|---|---|---|
| C-01 | Plugin возвращал `{ hooks: { ... } }` вместо top-level hooks | ✅ Исправлено | `adapters/opencode.sh` — возвращает callbacks напрямую |
| C-02 | Plugin использовал `app.path.cwd` вместо `directory` | ✅ Исправлено | `adapters/opencode.sh` — использует `directory` param |
| C-03 | Adapter создавал `opencode.json` для регистрации плагина | ✅ Исправлено | `adapters/opencode.sh` — больше не пишет `opencode.json` |
| C-04 | Тесты ожидали старый `{ hooks: ... }` контракт | ✅ Исправлено | `tests/bats/test_opencode_adapter.bats` — 15/15 passed |
| C-05 | Adapter оставлял stale legacy plugin entry в `opencode.json` | ✅ Исправлено | cleanup block добавлен в adapter install |

---

## 5. Gaps в планах и спецификациях

### 5.1 Cross-agent research note

**Файл:** `notes/2026-04-20_03-36_cross-agent-research.md`
**Проблема:** Утверждает "6 clients full native hooks", включая Pi. **Pi не имеет native hooks** (FR #5827 открыт; текущая реализация — git-hooks-fallback).
**Действие:** Добавить disclaimer в note. В `specs/parallel-pipeline/design.md` §17 Pi subagent API упоминается как "unstable" — нужно переписать на "not available as first-class; fallback only".

### 5.2 Parallel pipeline plan

**Файл:** `plans/2026-05-24_feature_parallel-pipeline.md`
**Проблема:** Stage 4 (Adapter layer) создаёт `adapters/opencode/dispatch.sh`, но не учитывает нынешние fixes в `adapters/opencode.sh`. Также `adapters/opencode/dispatch.sh` может дублировать логику уже существующего адаптера.
**Действие:** При старте Stage 4 провести рефакторинг: `adapters/opencode.sh` — install/project-level, `adapters/opencode/dispatch.sh` — pipeline runtime dispatch. Убедиться, что нет дублирования.

---

## 6. Приоритизация и рекомендации

### Блокер для v4.0.1 (можно влить в W0):
- 1.2 Global skill alias (10 мин, низкий риск).
- 2.1 SKILL.md секция (15 мин).
- 2.3 AGENTS.md дополнение (5 мин).

### W1 совместим с reviewer-v2:
- 1.1 Commands frontmatter (1h, массовая правка).
- 3.1 Tests syntax check (5 мин).
- 3.2 tool.execute.before review (20 мин).

### W1–W2 (feature work):
- 2.2 Plugin hooks parity (эпик, 2–3h).
- 2.4 OpenCode agent definitions (30 мин).

### Docs cleanup (параллельно):
- 5.1 Cross-agent research fix (10 мин).
- 5.2 Parallel pipeline adapter dedup (при старте Stage 4).

---

## 7. Ключевые файлы

- `adapters/opencode.sh` — адаптер (исправлен).
- `tests/bats/test_opencode_adapter.bats` — тесты (исправлены).
- `install.sh` — global install (нужен fix для alias).
- `SKILL.md` — metadata (нужен OpenCode раздел).
- `AGENTS.md` — хост-инструкции (нужен OpenCode раздел).
- `commands/*.md` — 24 файла frontmatter (нужен `agent`/`subtask`).
- `agents/` — нет OpenCode поддиректории.

---

## 8. Закрытие отчёта

Рекомендуется:
1. Принять HIGH fixes (1.2, 2.1, 2.3) в текущую ветку до закрытия W0.
2. MEDIUM fixes (1.1, 2.2, 2.4) запланировать в W1/W2.
3. LOW fixes (3.1, 3.2) — good first issue для contributor.
4. Обновить `notes/2026-04-20_03-36_cross-agent-research.md` с Pi disclaimer.

После принятия fixes — `/mb verify` → `/mb done`.
