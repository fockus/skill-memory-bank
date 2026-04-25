# Cursor Global Parity — план

Дата: 2026-04-20
Тип: feature
Цель: вывести Cursor на уровень Claude Code и Codex по глобальной установке skill "memory-bank".

## Context

Текущая интеграция с Cursor ограничена проектным адаптером (`adapters/cursor.sh` → `.cursor/rules/*.mdc` + `.cursor/hooks.json`). Для Claude Code и Codex уже есть полноценная глобальная установка через `install.sh`:

- `~/.claude/skills/skill-memory-bank` (canonical bundle)
- `~/.claude/skills/memory-bank` (alias symlink)
- `~/.codex/skills/memory-bank` (alias symlink)
- `~/.claude/CLAUDE.md` и `~/.codex/AGENTS.md` с маркер-секцией глобальных правил
- `~/.claude/settings.json` / `~/.codex/hooks.json` с hooks
- `~/.claude/commands/*.md` / `~/.codex/commands/*.md` с slash-commands

Пользователь попросил довести Cursor до того же уровня.

## Что умеет Cursor глобально (подтверждено docs Cursor)

- `~/.cursor/hooks.json` + `~/.cursor/hooks/*` — user hooks (мёржатся с project hooks)
- `~/.cursor/commands/*.md` — user slash commands
- `~/.cursor/skills/<name>/SKILL.md` — personal skills (подгружаются агентом по description)
- **User Rules** (аналог `~/.claude/CLAUDE.md`) — только через Settings UI, файлового API нет

Поэтому для правил используем три комплементарных канала:
1. `~/.cursor/skills/memory-bank/` (skill discovery)
2. `~/.cursor/AGENTS.md` с маркер-секцией (для совместимости и будущих fork'ов)
3. `~/.cursor/memory-bank-user-rules.md` — готовый файл для ручной вставки в Settings → Rules → User Rules

## DoD

- [ ] `install.sh` создаёт `~/.cursor/skills/memory-bank` symlink на canonical bundle
- [ ] `install.sh` пишет `~/.cursor/AGENTS.md` с маркер-секцией `memory-bank-cursor:start/end`
- [ ] `install.sh` создаёт `~/.cursor/memory-bank-user-rules.md` для ручной вставки
- [ ] `install.sh` устанавливает `~/.cursor/hooks.json` + `~/.cursor/hooks/*.sh` (три хука: file-change-log, block-dangerous, session-end-autosave)
- [ ] `install.sh` копирует `commands/mb.md` в `~/.cursor/commands/`
- [ ] Финальный output `install.sh` содержит hint про pbcopy/xclip для User Rules
- [ ] `uninstall.sh` полностью очищает всё выше (idempotent, preserves user content)
- [ ] `adapters/cursor.sh`: убран дубликат `# Global Rules` в сгенерированном `.cursor/rules/memory-bank.mdc`
- [ ] `tests/e2e/test_cursor_global.bats`: install/uninstall/idempotency/preserve-user-content
- [ ] `tests/pytest/test_cli.py`: смок-тест что `memory-bank install/uninstall` не падает с Cursor-шагами
- [ ] `SKILL.md`: Cursor в «native full support», host alias, Host-specific notes → Cursor
- [ ] `docs/cross-agent-setup.md`: обновлена supported clients table, Cursor раздел переписан, matrix, troubleshooting
- [ ] `README.md`: пример install для Cursor (global auto + project optional)
- [ ] `VERSION` → `3.0.0-rc2`, CHANGELOG `### Added` + `### Fixed`

## Этапы (TDD bite-sized)

### Этап 1: RED — e2e тест <!-- mb-stage:1 -->
- ⬜ Написать `tests/e2e/test_cursor_global.bats`: install → asserts всех 5 артефактов, uninstall → всё удалено, idempotency (два install подряд), preserve user content в `~/.cursor/AGENTS.md`.
- ⬜ Запустить bats — красный.

### Этап 2: install.sh — Cursor global install <!-- mb-stage:2 -->
- ⬜ Константы `CURSOR_DIR`, `CURSOR_SKILL_ALIAS`, `CURSOR_START_MARKER`, `CURSOR_END_MARKER`.
- ⬜ Расширить `ensure_skill_aliases()`: добавить `install_symlink "$CANONICAL_SKILL_DIR" "$CURSOR_SKILL_ALIAS"`.
- ⬜ `cursor_agents_section()` по образцу `codex_agents_section()`.
- ⬜ `install_cursor_global_agents()` — трёхветочная идемпотентная запись `~/.cursor/AGENTS.md`.
- ⬜ `install_cursor_user_rules_paste()` — пишет `~/.cursor/memory-bank-user-rules.md` (чистый контент без маркеров).
- ⬜ `install_cursor_global_hooks()` — jq-merge hooks.json + copy hooks/*.sh в `~/.cursor/hooks/`.
- ⬜ Step 4 (Commands): третий `cp` для `$CURSOR_DIR/commands/`.
- ⬜ После Step 7 безусловные вызовы трёх новых функций.
- ⬜ Финальный output: alias + pbcopy/xclip hint.

### Этап 3: uninstall.sh — симметричная очистка <!-- mb-stage:3 -->
- ⬜ Константы + маркеры.
- ⬜ Case-ветки для `$HOME/.cursor/*` в removal и backup restore.
- ⬜ Блок cleanup `~/.cursor/AGENTS.md` по маркерам `memory-bank-cursor:start/end`.
- ⬜ Очистка `~/.cursor/hooks.json` от `_mb_owned: true` entries.
- ⬜ Удаление `~/.cursor/memory-bank-user-rules.md`.
- ⬜ `rmdir` пустых `~/.cursor/skills`, `~/.cursor/hooks`, `~/.cursor/commands`.

### Этап 4: Fix double heading <!-- mb-stage:4 -->
- ⬜ `adapters/cursor.sh`: убрать локальную печать `# Global Rules` (строки 75-81), `rules/RULES.md` уже содержит этот заголовок.
- ⬜ Bats assertion в новом e2e: `.cursor/rules/memory-bank.mdc` содержит ровно один `# Global Rules`.

### Этап 5: GREEN — bats + pytest <!-- mb-stage:5 -->
- ⬜ Прогнать `tests/e2e/test_cursor_global.bats` до зелени.
- ⬜ Расширить `tests/pytest/test_cli.py` смок-тестом install/uninstall с mocked `$HOME`.
- ⬜ Full suite: `bats tests/bats tests/e2e` + `pytest -q` — зелёные.

### Этап 6: Docs <!-- mb-stage:6 -->
- ⬜ `SKILL.md`: Cursor в native full support tier, добавить host alias, раздел Host-specific notes → Cursor.
- ⬜ `docs/cross-agent-setup.md`: таблица, раздел Cursor переписать (global auto + project optional), resource availability matrix, troubleshooting про User Rules.
- ⬜ `README.md`: примеры install.

### Этап 7: Release <!-- mb-stage:7 -->
- ⬜ `VERSION`: `3.0.0-rc1` → `3.0.0-rc2`.
- ⬜ `CHANGELOG.md` `### Added`: Cursor global parity (5 артефактов).
- ⬜ `CHANGELOG.md` `### Fixed`: double `# Global Rules` heading.
- ⬜ `/mb verify` перед `/mb done`.

## Риски

- **Cursor User Rules** — нет файлового API, остаётся ручной копи-паст. Частично митигируется через skill + AGENTS.md.
- **AGENTS.md refcount collision** — избегается отдельными маркерами `memory-bank-cursor:start/end` (не пересекаются с shared `memory-bank:start/end` для OpenCode/Codex).
- **Прежняя Cursor установка** — idempotency-тест гарантирует что повторный install не ломает существующие hooks пользователя.
