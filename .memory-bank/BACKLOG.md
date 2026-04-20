# Backlog

## Идеи

### HIGH

- **Benchmarks (LongMemEval + custom 10 scenarios)**: вернуться после v3.0 с 1+ месяцем реального использования для baseline. 3 configs: A (CLAUDE.md only), B (claude-mem stock, optional если будут API credits), C (наш skill). Метрики: recall@5, tokens/session, precision. Отложено решением 2026-04-20 (ADR-008).
- **sqlite-vec semantic search**: заменить grep-based `mb-search.sh` на embedding-поиск через sqlite-vec. Отложено до v3.1+ после того как реальные use-cases покажут недостаточность keyword+tags+codegraph.
- **Bridge to native Claude Code memory**: двунаправленная синхронизация ключевых записей между `.memory-bank/` и `~/.claude/projects/.../memory/`. Сейчас только документация coexistence (Этап 5).
- **Auto-commit hook**: после `/mb done` автоматически создавать `chore(mb): ...` commit с дельтой `.memory-bank/`. Защищает от потери состояния при переключении веток.
- **`/mb graph`**: визуализация связей plan→checklist→STATUS→progress для больших проектов. Подпитывает contextual recall.
- ✅ **Stage 6.5 — Tree-sitter adapter для non-Python языков**: **SHIPPED 2026-04-20.** Реализовано в `mb-codegraph.py` — 6 языков (Go/JS/TS/Rust/Java + Python). `HAS_TREE_SITTER` флаг проверяет наличие; без него Python-only (v1 behavior). 14 bats (pytest) тестов зелёные. User install: `pip install tree-sitter tree-sitter-python tree-sitter-go tree-sitter-javascript tree-sitter-typescript tree-sitter-rust tree-sitter-java`. Future additions (C/C++, Ruby, PHP, Kotlin, Swift) — просто добавить запись в `_TS_LANG_CONFIG` по запросу.

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

- **ADR-004**: Профиль развития — **гибрид C** (personal сейчас, public через v3.0). Контекст: skill опубликован на GitHub, но не рекламируется; пользователь хочет продолжать для себя, затем публично продвигать. Альтернативы: (а) только personal — minimal invest, теряем потенциал; (б) сразу public — преждевременные npm/benchmarks без отработки на себе; (в) гибрид — v2.1/v2.2 для себя, v3.0 для public. Решение: (в). [2026-04-20]

- **ADR-005**: Auto-capture через SessionEnd hook + Haiku, не Sonnet. Контекст: Haiku дешевле в 4×, а для append-only progress.md достаточно. Альтернативы: (а) Sonnet — overhead на каждой сессии; (б) без LLM (только bash append) — теряем summary; (в) Haiku с ограниченной областью (только progress.md). Решение: (в), полный actualize остаётся в manual `/mb done` с Sonnet. [2026-04-20]

- **ADR-006**: Code graph через tree-sitter — **opt-in** через extras, не default. Контекст: tree-sitter = C-extensions, install может быть heavy на Windows/legacy систем. Альтернативы: (а) всегда включено — ломает install в 10% случаев; (б) separate package — users пропустят; (в) opt-in через `install.sh --with-codegraph` / `pip install memory-bank[codegraph]`. Решение: (в) — default skill работает без codegraph, advanced users включают явно. [2026-04-20]

- **ADR-007**: Отказ от sqlite-vec в v2.1/v2.2. Контекст: обратная связь настаивала на semantic search, но: (1) keyword + YAML tags + code graph покрывают 80%; (2) sqlite-vec + MiniLM добавляет ~100MB download + Python dep chain; (3) benchmark покажет, нужно ли вообще. Альтернативы: (а) включить в v2.2 — preemptive complexity; (б) v3.1 backlog — ждём реальной потребности. Решение: (б), пересмотреть после реальных use cases v3.0. [2026-04-20]

- **ADR-008**: Distribution strategy — **pipx/PyPI primary**, Homebrew tap secondary, Anthropic plugin tertiary. Контекст: mix-stack skill (88% bash + 12% Python). Альтернативы рассмотрены: (а) **npm** — требует Node.js runtime при отсутствии JS-кода, overhead без value; (б) **pipx/PyPI** — Python уже in-stack, `pipx` изолирует env, `pipx upgrade` решает update story out-of-the-box, standard для CLI с mix deps; (в) **Homebrew tap** — native macOS/linuxbrew, но ограниченная аудитория; (г) **curl \| bash** — простейший, но security concerns. Решение: (б) primary + (в) secondary + Anthropic plugin manifest tertiary. npm убран полностью. Scope `@fockus/memory-bank` на npm зарезервирован на случай возврата (свободен на 2026-04-20). Имя `memory-bank-skill` на PyPI свободно. [2026-04-20]

- **ADR-009**: Benchmarks (LongMemEval + custom 10 scenarios) отложены в v3.1+ backlog. Контекст: ревью настаивало на benchmarks как обязательная фича v3.0 для public release. Но: (1) для valid baseline нужно 1+ месяц реального использования v3.0; (2) без реальной baseline цифры искусственные; (3) без сравнения с claude-mem/compiler (требует API credits) — только single-point measurement. Альтернативы: (а) сделать synthetic benchmark сразу — low-value; (б) отложить до реальной usage-baseline; (в) skip навсегда — теряем adoption. Решение: (б), вернуться через 1-2 месяца после v3.0 release. Differentiator сейчас — TDD/plan-verifier/cross-agent, не recall цифры. [2026-04-20]

- **ADR-010**: Codex CLI добавлен 7-м adapter в Stage 8 (v3.0). Контекст: OpenAI Codex CLI (`openai/codex`) — популярный terminal coding agent, использует `AGENTS.md` как стандарт конфига (совпадает с OpenCode). Альтернативы: (а) не добавлять — пропустим заметную аудиторию; (б) `AGENTS.md` shared с OpenCode — конфликт при одновременной установке; (в) `AGENTS.md` + optional `.codex/config.toml` — явный marker владения. Решение: (в). Manifest фиксирует ownership per-client, совместная установка с OpenCode — shared `AGENTS.md` (no-conflict при identical content). Uninstall одного из {opencode, codex} не затирает файл пока второй active. Counts: 6 → 7 adapters, 14 → 16 e2e tests. [2026-04-20]

- **ADR-011**: Repository migration `claude-skill-memory-bank` → `skill-memory-bank` как Stage 8.5 (перед pipx/PyPI release). Контекст: после Stage 8 skill работает с 7 клиентами, имя `claude-skill-*` misleading. Альтернативы: (а) оставить старое имя + rebrand в README — запутано; (б) fresh public repo с clean-break history — теряем ADR/research transparency; (в) full history migration в новый `skill-memory-bank` + archive старого — canonical path, сохраняет authorship. Решение: (в). Таймирование: **до Stage 9** (pipx/PyPI), иначе PyPI/Homebrew нужен перевыпуск с новым URL. **PyPI имя остаётся `memory-bank-skill`** (ADR-008) — не переименовываем в `skill-memory-bank`: (1) избегаем PyPI name conflicts; (2) pip install tokens уже в статьях/docs; (3) GitHub repo name и PyPI package name не обязаны совпадать. URL в PyPI metadata (`project_urls.Repository`) указывает на `fockus/skill-memory-bank`. Homebrew formula source → новый URL. [2026-04-20]

## Отклонено

- **Разделить skill на 3 плагина** (core, dev-commands, hooks): слишком много фрагментации UX для v2. Может быть в v3 если скил вырастет.
- **Заменить bash на Python для всех скриптов**: shell-скрипты приемлемы для lightweight ops; Python overhead не оправдан для `cat STATUS.md`.
- **Drop YAML frontmatter, использовать JSON-only**: frontmatter — industry standard для note-taking tools (Obsidian, Logseq), сохраняем совместимость.
- **Hash-based IDs для заметок/планов** (предложено в ревью 2026-04-20): YAGNI. У нас single-user workflow; multi-device конфликты — теоретическая проблема. Sequential IDs (H-NNN, EXP-NNN) работают.
- **KB compilation** (`concepts/`, `connections/`, `qa/` иерархия, предложено в ревью): преждевременная структура. У нас ≤50 notes, Karpathy-pattern имеет смысл при 300+.
- **GWT (Given/When/Then) в DoD** (предложено из GSD): дублирует test requirements в текущем шаблоне плана. BDD tests достаточны без редундантной markdown-секции.
- **Schema drift detection** (предложено из GSD): domain-specific для fintech migrations. Не fits generic skill, оставляем pользовательским pre-commit hooks.
- **`/mb debug`** (4-phase systematic debugging из Superpowers): дублирует `superpowers:debugging` skill. Tool composition > duplication.
- **REST API / daemon mode** (предложено из mcp-memory-service): ломает архитектурное преимущество (93% Shell, simplicity, offline). Эта ниша занята mcp-memory-service (1500+ тестов), не конкурируем.
- **Viewer UI / localhost dashboard** (предложено для adoption): chrome over substance. Пересмотреть если Gate v3.0 показывает что UI — bottleneck adoption.
- **OpenAI/Cohere embeddings через API**: не деремся с детерминированностью и оффлайн-работой. Local MiniLM (если когда-нибудь добавим sqlite-vec) достаточен.
