# Backlog

## Идеи

### HIGH

- **sqlite-vec semantic search**: заменить grep-based `mb-search.sh` на embedding-поиск через sqlite-vec. Отложено до v3 после стабилизации базового рефактора.
- **Bridge to native Claude Code memory**: двунаправленная синхронизация ключевых записей между `.memory-bank/` и `~/.claude/projects/.../memory/`. Сейчас только документация coexistence (Этап 5).
- **Auto-commit hook**: после `/mb done` автоматически создавать `chore(mb): ...` commit с дельтой `.memory-bank/`. Защищает от потери состояния при переключении веток.
- **`/mb graph`**: визуализация связей plan→checklist→STATUS→progress для больших проектов. Подпитывает contextual recall.

### LOW

- i18n error-сообщений (сейчас hardcoded русский)
- GUI/TUI для просмотра банка (`mb ui` через `gum` или fzf)
- Экспорт банка в Obsidian/Logseq vault
- Webhook integration: Slack-нотификация при изменении `STATUS.md`
- Auto-generate `README.md` проекта из `.memory-bank/` data

## Архитектурные решения (ADR)

- **ADR-001**: Оставить skill structure под `~/.claude/skills/memory-bank/` вместо переноса в plugin-формат. Контекст: native plugins пока недостаточно зрелые для multi-file distribution. Альтернативы: (а) plugin-based packaging — требует manifest rewrite и migration для пользователей; (б) keep as-is. Решение: (б), пересмотреть в v3. [2026-04-19]

- **ADR-002**: Использовать bats-core для shell-тестов, pytest для Python. Контекст: нужна unified testing story, но shell и Python имеют разные idioms. Альтернативы: (а) только bats, мокать Python через shell; (б) перевести merge-hooks.py → shell; (в) раздельные frameworks. Решение: (в), оба встроены в CI. [2026-04-19]

- **ADR-003**: `index.json` реализация будет минимальной (только tags/type/importance extract из frontmatter), без vector search. Контекст: sqlite-vec добавляет runtime dependency и усложняет install. Альтернативы: (а) полный semantic search; (б) только frontmatter index; (в) отказаться от index.json. Решение: (б) — покрывает 80% use cases при 20% сложности. [2026-04-19]

## Отклонено

- **Разделить skill на 3 плагина** (core, dev-commands, hooks): слишком много фрагментации UX для v2. Может быть в v3 если скил вырастет.
- **Заменить bash на Python для всех скриптов**: shell-скрипты приемлемы для lightweight ops; Python overhead не оправдан для `cat STATUS.md`.
- **Drop YAML frontmatter, использовать JSON-only**: frontmatter — industry standard для note-taking tools (Obsidian, Logseq), сохраняем совместимость.
