# Architecture Decision Records

### ADR-001 — Оставить skill structure под ~/.claude/skills/memory-bank/ [2026-04-19]

**Context:** native plugins пока недостаточно зрелые для multi-file distribution.
**Options:**
- A: plugin-based packaging — требует manifest rewrite и migration
- B: keep as-is — zero migration cost

**Decision:** B.
**Rationale:** скорость выпуска важнее canonical form; пересмотреть в v3.
**Consequences:** users продолжают клонировать skill repo; нет CI/CD через Anthropic plugin marketplace (пока).

### ADR-002 — Bats-core для shell, pytest для Python [2026-04-19]

**Context:** нужна unified testing story, но shell и Python имеют разные idioms.
**Options:**
- A: только bats, мокать Python через shell
- B: перевести merge-hooks.py → shell
- C: раздельные frameworks

**Decision:** C.
**Rationale:** native test idioms побеждают искусственную унификацию.
**Consequences:** CI запускает оба набора; developers знают оба framework'а.

### ADR-003 — index.json минимальная реализация (без vector) [2026-04-19]

**Context:** sqlite-vec добавляет runtime dependency и усложняет install.
**Options:**
- A: полный semantic search
- B: только frontmatter index (tags/type/importance)
- C: отказаться от index.json

**Decision:** B.
**Rationale:** покрывает 80% use-cases при 20% сложности.
**Consequences:** semantic queries невозможны без отдельного opt-in (ADR-007).

### ADR-004 — Профиль развития — гибрид C (personal → public через v3.0) [2026-04-20]

**Context:** skill опубликован на GitHub, но не рекламируется; пользователь хочет продолжать для себя, затем публично продвигать.
**Options:**
- A: только personal — minimal invest, теряем потенциал
- B: сразу public — преждевременные npm/benchmarks без отработки на себе
- C: гибрид — v2.1/v2.2 для себя, v3.0 для public

**Decision:** C.
**Rationale:** dogfooding даёт реальный signal до public commitment.
**Consequences:** двухфазный release cycle; Stage 9 готовит PyPI/Homebrew к public.

### ADR-005 — Auto-capture через SessionEnd + Haiku [2026-04-20]

**Context:** `progress.md` append-only; нужен cheap auto-summary без полного actualize.
**Options:**
- A: Sonnet — overhead на каждой сессии
- B: без LLM (bash append) — теряем summary
- C: Haiku с ограниченной областью (только progress.md)

**Decision:** C.
**Rationale:** Haiku 4× дешевле; full actualize остаётся в manual `/mb done` с Sonnet.
**Consequences:** две точки записи (auto + manual); доп. сложность в coordination.

### ADR-006 — Code graph через tree-sitter — opt-in через extras [2026-04-20]

**Context:** tree-sitter = C-extensions, install может быть heavy на Windows/legacy системах.
**Options:**
- A: всегда включено — ломает install в 10% случаев
- B: separate package — users пропустят
- C: opt-in через `pip install memory-bank[codegraph]`

**Decision:** C.
**Rationale:** default работает без codegraph; advanced users включают явно.
**Consequences:** документация должна чётко показать когда нужен extras.

### ADR-007 — Отказ от sqlite-vec в v2.1/v2.2 [2026-04-20]

**Context:** ревью настаивало на semantic search, но benefits не подтверждены реальным usage.
**Options:**
- A: включить в v2.2 — preemptive complexity
- B: v3.1+ backlog — ждём реальной потребности

**Decision:** B.
**Rationale:** (1) keyword+tags+codegraph покрывают 80%; (2) sqlite-vec+MiniLM ~100MB download; (3) benchmark покажет нужно ли.
**Consequences:** I-002 остаётся DEFERRED; пересмотр после реальных v3.0 use cases.

### ADR-008 — Distribution — pipx/PyPI primary, Homebrew secondary [2026-04-20]

**Context:** mix-stack skill (88% bash + 12% Python).
**Options:**
- A: npm — требует Node.js runtime при отсутствии JS-кода
- B: pipx/PyPI — Python уже in-stack, `pipx` изолирует env, `pipx upgrade` решает update story
- C: Homebrew tap — native macOS/linuxbrew, но ограниченная аудитория
- D: `curl | bash` — простейший, но security concerns

**Decision:** B primary + C secondary + Anthropic plugin tertiary.
**Rationale:** pipx канонично для CLI с mix deps; Homebrew — secondary для macOS-only пользователей.
**Consequences:** npm убран; scope `@fockus/memory-bank` зарезервирован. PyPI имя `memory-bank-skill` (не `skill-memory-bank`) — избегаем rename pain.

### ADR-009 — Benchmarks отложены в v3.1+ backlog [2026-04-20]

**Context:** ревью настаивало на benchmarks как обязательная фича v3.0 для public release.
**Options:**
- A: synthetic benchmark сразу — low-value
- B: отложить до реальной usage-baseline
- C: skip навсегда — теряем adoption

**Decision:** B.
**Rationale:** для valid baseline нужно 1+ месяц реального использования v3.0; без сравнения с claude-mem — single-point measurement.
**Consequences:** I-001 остаётся DEFERRED; differentiator сейчас — TDD/plan-verifier/cross-agent, не recall цифры.

### ADR-010 — Codex CLI 7-м adapter в Stage 8 [2026-04-20]

**Context:** OpenAI Codex CLI использует `AGENTS.md` как стандарт конфига (совпадает с OpenCode).
**Options:**
- A: не добавлять — пропустим аудиторию
- B: `AGENTS.md` shared с OpenCode — конфликт при одновременной установке
- C: `AGENTS.md` + optional `.codex/config.toml` — явный marker владения

**Decision:** C.
**Rationale:** manifest фиксирует ownership per-client; совместная установка с OpenCode возможна при shared `AGENTS.md`.
**Consequences:** 6→7 adapters; 14→16 e2e tests; uninstall одного не затирает файл пока второй active.

### ADR-011 — Repository migration claude-skill-memory-bank → skill-memory-bank [2026-04-20]

**Context:** после Stage 8 skill работает с 7 клиентами, имя `claude-skill-*` misleading.
**Options:**
- A: оставить старое имя + rebrand в README — запутано
- B: fresh public repo с clean-break history — теряем ADR/research transparency
- C: full history migration в новый `skill-memory-bank` + archive старого

**Decision:** C.
**Rationale:** canonical path; сохраняет authorship и link continuity.
**Consequences:** Stage 8.5 до Stage 9 (иначе PyPI/Homebrew нужен перевыпуск). PyPI имя остаётся `memory-bank-skill` (ADR-008 — не переименовываем). URL в project_urls.Repository → `fockus/skill-memory-bank`.

### ADR-012 — Opt-in SDK-managed Pi startup для строгой Nico/Tintin-интеграции [2026-10-05]

**Context:** При интеграции Nico/Tintin обычный Pi ExtensionAPI не даёт authoritative session-bound inventory и настройки конкретного Tintin factory. У Tintin 0.19.0 settings_loaded не содержит owner/session identity, а автоматические mentions могут обойти MB-маршрутизацию. Producer path в неизменённом обычном startup не продемонстрирован; fixture-only результат не доказывает совместимость.

**Options:**
- A: отдельный opt-in bootstrap публичного Pi SDK, существующие runtime/TUI и Nico/Tintin executors — появляется известная composition root, но нужен дополнительный явный entrypoint и приёмка его поведения.
- B: ослабить provenance/absence проверки обычного startup — меньше кода, но строгая гарантия одного выбранного backend остаётся недоказанной.
- C: отложить dual-backend до нового upstream API — не менять startup, но не поставить согласованную интеграцию сейчас.

**Decision:** A, выбран владельцем 2026-10-05, AGR-058; Q-002 разрешён. Обычный pi, чужие настройки и child executor не заменяются. Отдельный entrypoint принадлежит MB и устанавливается явно после Stage 5 gates.

**Rationale:** SDK экспортирует DefaultResourceLoader, session/runtime, event bus и InteractiveMode. Владелец этой composition root может связать действительно загруженные компоненты и factory settings с живой session/runtime generation, не выводя их из косвенных признаков. Это ещё требует реализации и независимой проверки, а не подтверждает live compatibility само по себе.

**Consequences:** Stage 1 получает минимальный bootstrap/binding producer/consumer и реальный model-free SDK smoke через TDD. Stage 5 проверяет установку, существующий TUI, оба backend, модели и сохранение пользовательской конфигурации. Unknown/stale bindings, неизвестные mentions и unsupported isolation блокируют запуск; private imports, второй executor и provider/backend fallback запрещены. Остальные хосты и обычный Pi не меняются; исторические receipts/RED и latest retained writer сохраняются.

### ADR-013 — Pi-native: Tintin by default, Nico opt-in under a capability ceiling [2026-10-08] · status: accepted

**Context:** Stage 1 of pi-native-integration requires public proof of a child's effective tools and loaded resources. Tintin exposes the child SDK session through its public registry (actual leaf probe passed); Nico 0.76 exposes only launch intent (preflight plan, `launchContractDigest`, `toolCount`) and no public child-session getter.
**Decision:** Tintin is the default backend (`--backend` → `.mb-config pi_subagent_backend` → tintin); Nico stays opt-in, runs under `registerSubagentCapabilityCeiling` (`allowedTools`, `allowedAgents: []`, `denyExtensions: true`) next to the digest checks, and its runtime inventory is reported UNVERIFIED instead of blocking (AGR-088).
**Alternatives:** keep Nico default and block the stage until upstream adds a child inventory (no timeline); inject a child-side self-report extension (plan forbids observer extensions, still cannot list loaded extensions); private imports (forbidden).
**Consequences:** Stage 1 can close with full runtime evidence on the default path; Nico users get enforced limits but no verified inventory until Nico ships a public one. Supersedes the "Nico by default" part of AGR-057.

### ADR-014 — Explicit ESM launcher [2026-10-08] · status: accepted

**Context:** Node parses the installed extensionless mb-pi as CommonJS and rejects its imports.
**Decision:** Keep the existing installer fix: an owned shell launcher executes an adjacent mb-pi.mjs with Pi's Node runtime.
**Alternatives:** Changing the user's package.json would affect unrelated modules; shell aliases would not fix installation.
**Consequences:** Both files require ownership tracking and install/uninstall tests; ordinary pi stays untouched.

### ADR-015 — Extension-owned ordinary Pi dispatch [2026-10-08] · status: accepted

**Context:** AGR-090 requires MB roles in ordinary Pi; the current dispatcher only accepts an SDK-root binding.
**Decision:** Activate the pinned Tintin public factory inside the opted-in MB extension and bind its attributed service to the live public session context. Retain model, tool-scope, lifecycle and no-fallback checks.
**Alternatives:** Replacing pi would alter the host; removing the binding guard would allow unverified services; a second executor would duplicate Tintin.
**Consequences:** The extension owns startup and teardown, refuses duplicate services and stale contexts, and needs actual ordinary-Pi acceptance. mb-pi remains optional.
