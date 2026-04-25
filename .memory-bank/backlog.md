# Backlog

## Ideas

### I-033 — `mb-checklist-prune.sh` — auto-archive completed sections to progress.md [HIGH, DONE, 2026-04-25]

**Outcome:** SHIPPED 2026-04-25. `scripts/mb-checklist-prune.sh` + 12 pytest tests + CI cap-test + wire-ins (`commands/done.md`, `mb-plan-done.sh`, `mb-compact.sh`). Repo checklist auto-pruned to 36 lines under hard cap of 120. Plan: `plans/done/2026-04-25_refactor_checklist-prune-i033.md`.

**Original sketch (kept for reference):**

**Problem:** `checklist.md` росла до 534 строк потому что `mb-plan-done.sh` только меняет `⬜` → `✅` в существующих секциях, но никогда не удаляет завершённые sprint-секции. Spec §3 (line 61, 67) явно говорит: "checklist.md ... ротируется ... после `/mb done` → `progress.md`". Spec §13 объявляет `mb-checklist-auto-update.sh` как non-hook script, вызываемый из `/mb done` — но он так и не был построен. В результате каждый закрытый Sprint оставался в checklist'е навсегда и дублировал то, что уже есть в `progress.md` + `roadmap.md "Recently completed"` + `plans/done/`.

**Sketch:**
1. `scripts/mb-checklist-prune.sh [--dry-run|--apply] [--mb <path>]`:
   - Сканирует `## ` секции в checklist.md.
   - Помечает к архивации: секцию, где все bullets имеют `✅` AND содержит ссылку на `plans/done/...`. Опционально дополнительный фильтр "old enough" (≥7d с момента закрытия плана — найти по mtime done-плана).
   - Compresses секцию в одну строку: `### <heading> ✅ — Plan: [path]`. Полный текст уже есть в plans/done и progress.md, дубль не нужен.
   - Hard cap: после prune файл ≤120 строк. Если всё ещё длинный — emit warning о ручном trim.
   - Pre-write backup: copy в `.checklist.md.bak.<timestamp>`.

2. Wire в `/mb done` flow (commands/done.md): после actualize + note + progress, run prune --apply automatically.

3. Wire в `/mb compact` (scripts/mb-compact.sh) как опциональный шаг при `--apply`.

4. Wire в `mb-plan-done.sh`: после flip checkmarks, проверить — если вся секция плана теперь зелёная, immediately collapse её в одну строку (instead of waiting for `/mb done`).

5. Test coverage: pytest для prune script (RED tests for >120 lines triggers warn, all-✅-section collapses, dry-run shows plan, --apply mutates).

6. Add explicit "Hard cap ≤120 lines" convention к header чеклиста (уже сделано вручную 2026-04-25, требуется инструментальное enforcement).

**Plan:** Фолды в Phase 4 Sprint 3 как pre-release polish, либо отдельным small refactor sprint после Phase 4 close.

### I-001 — Benchmarks (LongMemEval + custom 10 scenarios) [HIGH, DEFERRED, 2026-04-20]

**Problem:** нет baseline для recall/tokens/session/precision; public release заявляет преимущества без измерений.
**Sketch:** 3 configs — A (CLAUDE.md only), B (claude-mem stock, optional с API credits), C (наш skill). Вернуться после v3.0 с 1+ месяцем реального использования.
**Plan:** — (решение ADR-009)

### I-002 — sqlite-vec semantic search [HIGH, DEFERRED, 2026-04-20]

**Problem:** grep-based `mb-search.sh` не поднимает семантически близкие заметки.
**Sketch:** заменить на embedding-поиск через sqlite-vec + local MiniLM. Отложено до v3.1+ после того как реальные use-cases покажут недостаточность keyword+tags+codegraph.
**Plan:** — (решение ADR-007)

### I-003 — Bridge to native Claude Code memory [HIGH, NEW, 2026-04-19]

**Problem:** нет программной синхронизации ключевых записей между `.memory-bank/` и `~/.claude/projects/.../memory/` — только документация coexistence (Этап 5).
**Sketch:** двунаправленный mapper: MB `notes/` ↔ auto-memory entries.
**Plan:** —

### I-004 — Auto-commit hook после `/mb done` [HIGH, DONE, 2026-04-25]

**Outcome:** SHIPPED 2026-04-25. `scripts/mb-auto-commit.sh` — opt-in (`MB_AUTO_COMMIT=1` env or `--force` flag) auto-commit `.memory-bank/` после `/mb done`. Safety gates: refuses on dirty source outside bank, during rebase/merge/cherry-pick, on detached HEAD, no-op when bank clean. Subject из last `### ` heading в `progress.md` (truncated to 60 chars), fallback `chore(mb): session-end YYYY-MM-DD`. Never pushes. Wired into `commands/done.md` step 7. 10 pytest tests + registration test green. Plan: `plans/done/2026-04-25_feature_i004-auto-commit.md`.

**Original sketch (kept for reference):**
**Problem:** изменения в `.memory-bank/` теряются при переключении веток если не закоммичены руками.
**Sketch:** post-`/mb done` хук создаёт `chore(mb): <session-summary>` commit с дельтой `.memory-bank/`.
**Plan:** [plans/done/2026-04-25_feature_i004-auto-commit.md](plans/done/2026-04-25_feature_i004-auto-commit.md)

### I-005 — /mb graph — визуализация связей plan→checklist→STATUS→progress [HIGH, NEW, 2026-04-20]

**Problem:** для больших проектов сложно проследить откуда пришла задача и где она закрылась.
**Sketch:** SVG/DOT-граф с cross-references между core-файлами. Подпитывает contextual recall.
**Plan:** —

### I-006 — Tree-sitter adapter для non-Python языков [HIGH, DONE, 2026-04-20]

**Problem:** `mb-codegraph.py` был Python-only, не покрывал Go/JS/TS/Rust/Java в polyglot проектах.
**Outcome:** SHIPPED 2026-04-20. 6 языков через `HAS_TREE_SITTER` флаг (fallback на Python-only без зависимости). 14 bats/pytest тестов зелёные.
**Plan:** shipped as part of v2.2 / Stage 6.5.

### I-007 — i18n error-сообщений [LOW, NEW, 2026-04-19]

**Problem:** сейчас часть stderr сообщений на русском, часть на английском — несогласованность.
**Sketch:** единый source-of-truth строк + env `MB_LOCALE`. Отложено как LOW priority (v3.1+ backlog).
**Plan:** —

### I-008 — GUI/TUI для просмотра банка (`mb ui`) [LOW, NEW, 2026-04-19]

**Problem:** для adoption новым пользователям полезен overview без ручного `cat`.
**Sketch:** TUI через `gum` / fzf; возможно простой localhost dashboard. Пересмотреть если Gate v3.0 показывает что UI — bottleneck adoption.
**Plan:** —

### I-009 — Экспорт банка в Obsidian/Logseq vault [LOW, NEW, 2026-04-19]

**Problem:** пользователи Obsidian хотят читать MB в своём knowledge management.
**Sketch:** `mb export --format obsidian` — конвертирует frontmatter + backlinks.
**Plan:** —

### I-010 — Webhook integration: Slack-нотификация при изменении status.md [LOW, NEW, 2026-04-19]

**Problem:** команды не видят когда milestone/gate сдвинулись без проверки репо.
**Sketch:** опциональный post-commit hook, POST на webhook URL из env.
**Plan:** —

### I-011 — Auto-generate README.md проекта из .memory-bank/ data [LOW, NEW, 2026-04-19]

**Problem:** README проекта часто устаревает относительно plan/STATUS.
**Sketch:** `mb readme-gen` — пересобирает README.md из STATUS + tech stack из codebase.
**Plan:** —

### I-012 — Split skill на 3 плагина (core, dev-commands, hooks) [MED, DECLINED, 2026-04-19]

**Problem:** (рассмотрено) слишком много фрагментации UX для v2. Может быть в v3 если скилл вырастет.
**Decision:** DECLINED — единый skill проще для install/update.

### I-013 — Миграция bash → Python для всех скриптов [LOW, DECLINED, 2026-04-19]

**Problem:** (рассмотрено) shell-скрипты якобы плохо тестируются.
**Decision:** DECLINED — shell приемлем для lightweight ops; Python overhead не оправдан для `cat status.md`.

### I-014 — Drop YAML frontmatter, использовать JSON-only [LOW, DECLINED, 2026-04-19]

**Problem:** (рассмотрено) frontmatter якобы усложняет парсинг.
**Decision:** DECLINED — frontmatter industry standard для note-taking (Obsidian, Logseq); сохраняем совместимость.

### I-015 — Hash-based IDs для заметок/планов [LOW, DECLINED, 2026-04-20]

**Problem:** (предложено в ревью 2026-04-20) решает multi-device конфликты.
**Decision:** DECLINED — YAGNI. Single-user workflow; multi-device — теоретическая проблема. Sequential IDs (H-NNN, EXP-NNN, I-NNN) работают.

### I-016 — KB compilation (concepts/, connections/, qa/ иерархия) [MED, DECLINED, 2026-04-20]

**Problem:** (предложено в ревью) преждевременная структура a-la Karpathy.
**Decision:** DECLINED — у нас ≤50 notes, Karpathy-pattern имеет смысл при 300+.

### I-017 — GWT (Given/When/Then) в DoD [LOW, DECLINED, 2026-04-20]

**Problem:** (предложено из GSD) добавить BDD-секцию в DoD шаблона планов.
**Decision:** DECLINED — дублирует test requirements; BDD tests достаточны без редундантной markdown-секции.

### I-018 — Schema drift detection [MED, DECLINED, 2026-04-20]

**Problem:** (предложено из GSD) проверять DB schema migrations на drift.
**Decision:** DECLINED — domain-specific для fintech; не fits generic skill, оставляем pre-commit hooks пользователей.

### I-019 — /mb debug (4-phase systematic debugging) [LOW, DECLINED, 2026-04-20]

**Problem:** (предложено из Superpowers) встроить отладочный workflow.
**Decision:** DECLINED — дублирует `superpowers:debugging` skill. Tool composition > duplication.

### I-020 — REST API / daemon mode [HIGH, DECLINED, 2026-04-20]

**Problem:** (предложено из mcp-memory-service) серверный режим для shared memory.
**Decision:** DECLINED — ломает архитектурное преимущество (93% Shell, simplicity, offline). Ниша занята mcp-memory-service (1500+ тестов), не конкурируем.

### I-021 — Viewer UI / localhost dashboard [MED, DECLINED, 2026-04-20]

**Problem:** (предложено для adoption) веб-интерфейс для просмотра банка.
**Decision:** DECLINED — chrome over substance. Пересмотреть если Gate v3.0 покажет что UI — bottleneck adoption. Пересекается с I-008 (LOW/NEW), как LOW-severity альтернатива оставляем.

### I-022 — OpenAI/Cohere embeddings через API [LOW, DECLINED, 2026-04-20]

**Problem:** (рассмотрено как альтернатива I-002) SaaS embeddings вместо local MiniLM.
**Decision:** DECLINED — теряем детерминированность и оффлайн-работу. Local MiniLM (если когда-нибудь добавим sqlite-vec) достаточен.

### I-023 — Унифицировать v1-detection grep → find (commands/start.md, agents/mb-doctor.md) [MED, NEW, 2026-04-22]

**Problem:** (ревью Phase 1 Sprint 1) detection в `commands/start.md` и `agents/mb-doctor.md` использует `ls | grep -E '^(STATUS|BACKLOG|RESEARCH|plan)\.md$'` — на macOS APFS это чувствительно к кэшированию FS. Migrator уже использует корректный `find -maxdepth 1 -type f -name`. Три entry-точки должны давать одинаковый ответ.
**Sketch:** заменить `ls | grep` на `find .memory-bank -maxdepth 1 -type f -name STATUS.md` и аналоги в обоих файлах.
**Plan:** Sprint 2 (часть plan-verifier расширения).

### I-024 — Добавить `--` end-of-options handling в mb-migrate-v2.sh [LOW, NEW, 2026-04-22]

**Problem:** (ревью Phase 1 Sprint 1) `bash mb-migrate-v2.sh -- somepath` упадёт с `[error] unknown flag: --`, хотя GNU convention — `--` означает конец опций.
**Sketch:** в `case "$arg" in` добавить `--) shift ;;` до `--*)`. Одна строка.
**Plan:** Sprint 2 (low priority — one-shot скрипт, manual users unlikely to pass `--`).

### I-025 — Переименовать переменные `PLAN_MD` → `ROADMAP_MD` в mb-plan-sync.sh / mb-plan-done.sh [LOW, NEW, 2026-04-22]

**Problem:** (ревью Phase 1 Sprint 1) переменные `PLAN_MD="$MB_PATH/roadmap.md"` — имя устарело после переименования. Работает, но misleading при чтении.
**Sketch:** `sed -i '' 's/PLAN_MD/ROADMAP_MD/g'` в двух скриптах + визуальная проверка что нет коллизий с комментариями.
**Plan:** Sprint 2 (cleanup, вместе с обучением обоих скриптов парсить Phase/Sprint/Task структуру).

### I-026 — Научить mb-plan-done.sh / mb-plan-sync.sh парсить Phase/Sprint/Task структуру [MED, NEW, 2026-04-22]

**Problem:** (Sprint 1 carry-over) скрипты распознают только `### Stage N:` — новый формат `## Phase N / ### Sprint M / #### Task K` не парсится. В Sprint 1 пришлось вручную move'ить план в `plans/done/`.
**Sketch:** расширить regex в обоих скриптах: `^#{2,4} (Phase|Sprint|Stage|Task) [0-9]+`. Добавить тесты на новый формат.
**Plan:** Sprint 2 baseline item (перед новыми планами которые будут использовать новый формат).

### I-027 — Test-guard против bash 4+ конструкций в mb-migrate-v2.sh [LOW, NEW, 2026-04-22]

**Problem:** (ревью Phase 1 Sprint 1 recommendation) macOS bash намертво 3.2. Будущие edit'ы могут reintroduce `declare -A`, `${var,,}`, `${var^^}` и сломать миграцию на Mac.
**Sketch:** pytest который grep'ом ищет запрещённые конструкции и fail'ит если найдены.
**Plan:** Sprint 2 (часть расширения test-suite для migrator).

### I-028 — multi-active plan collision in checklist.md (Sprint 2 reviewer C1) [HIGH, DONE, 2026-04-22]

**Problem:** mb-plan-sync.sh keys checklist sections by `## Stage N: <name>` heading. Two active plans sharing a section name (e.g. both have `## Task 1: Setup`) collapse onto one checklist entry. When one plan is closed via mb-plan-done.sh, its removal takes the other plan's entry with it — silent data loss.
**Repro:** create two plans with `## Task 1: Setup`. `mb-plan-sync.sh p1.md && mb-plan-sync.sh p2.md && mb-plan-done.sh p1.md` → checklist now empty, p2 orphaned.
**Sketch:** emit `<!-- mb-plan:<basename> -->` marker above each `## Stage N:` section; key remove-logic by marker (plan-scoped), not section heading. Backward-compat: sections without markers are treated as owned by the currently-being-closed plan (conservative legacy behavior).
**Plan:** [plans/done/2026-04-25_refactor_sprint3-multi-active-fix.md](plans/done/2026-04-25_refactor_sprint3-multi-active-fix.md)
**Outcome:** SHIPPED 2026-04-25. Marker `<!-- mb-plan:<basename> -->` emitted above each checklist section by mb-plan-sync.sh; mb-plan-done.sh keys removal by marker (plan-scoped). Backward-compat path for legacy unmarked sections preserved (conservative removal — only when no marker conflict). pytest 289 → 293 (4 new collision tests + bats fixture refresh from Sprint-1 v2 rename catch-up). bats 479 → 515 passed (legacy-marker-aware contract update for `test_plan_sync.bats` line ~105).

### I-029 — mb-traceability-gen: extension list is hard-coded, no `.rb/.kt/.swift/.java/.c/.cpp/.h` [LOW, NEW, 2026-04-22]

**Problem:** (Batch C reviewer M1) `tf.suffix not in {".py", ".ts", ".tsx", ".js", ".go", ".rs", ".sh"}` — hard-coded list excludes common languages. Plan spec said "substrings in file content" without enumerating.
**Sketch:** move extensions to `_lib.sh` env variable `MB_TRACEABILITY_EXTENSIONS` with sensible default; document override.
**Plan:** Sprint 3 or later.

### I-030 — mb-roadmap-sync: `.md` file scan omitted from REQ detection [LOW, NEW, 2026-04-22]

**Problem:** (Batch C reviewer M1) Prose mentions of REQ-NNN in `.md` design documents are not counted as coverage. This is probably correct (too noisy), but not documented.
**Sketch:** add a comment in mb-traceability-gen.sh header explaining the intentional `.md` exclusion.
**Plan:** Sprint 3 polish.

### I-031 — mb-traceability-gen: traceability.md full-overwrite isn't documented [LOW, NEW, 2026-04-22]

**Problem:** (Batch C reviewer I4) Manual edits to `traceability.md` are silently clobbered. Current header says "Do not edit manually" but the write semantics ("FULL OVERWRITE — any manual edits are lost") should be in the script header comment too.
**Sketch:** one-line doc addition in `scripts/mb-traceability-gen.sh`.
**Plan:** Sprint 3 polish.

### I-032 — Phase/Sprint/Task parser: Phase and Sprint as container-only? [LOW, NEW, 2026-04-22]

**Problem:** (final reviewer recommendation) `^#{2,4} (Task|Stage|Phase|Sprint) [0-9]+:` accepts all four equally. In plans like Sprint 2's own (which has `## Phase 1 > Sprint 2 > Task N` nesting), both `Phase 1` and `Task N` become checklist entries. Probably tracking-correct, but semantically `Phase`/`Sprint` are containers, not executable units.
**Sketch:** decide — allow all four (current), or restrict to `Task|Stage` only with `Phase|Sprint` being document structure. If the latter: narrow regex to `^#{2,4} (Task|Stage) [0-9]+:`.
**Plan:** Sprint 3 design discussion.


### I-034 — Plugin-namespaced skill detection for mb-reviewer-resolve.sh + install.sh probe [MED, NEW, 2026-04-25]

**Problem:** Phase 4 Sprint 3 ship-нул `mb-reviewer-resolve.sh` который ищет `superpowers` skill только по path `~/.claude/skills/superpowers/`. В реальности у пользователей skill часто живёт в **plugin namespace** (например `superpowers:requesting-code-review`, `commit-commands:commit`, `gsd:*`, `kaizen:*`) — это plugin-bundled skills, и они НЕ создают `~/.claude/skills/<name>/` директорию. Probe в `install.sh` step 6.5 говорит "superpowers skill not detected", и `mb-reviewer-resolve.sh` всегда возвращает `mb-reviewer` даже когда plugin-version skill реально доступен. Validated на этой машине 2026-04-25 — `superpowers:requesting-code-review` есть в Skill list, но resolver его не видит.

**Sketch:**
1. **Inventory mechanism для plugin-namespaced skills.** Claude Code skills могут попасть в session тремя способами:
   - file-system skill: `~/.claude/skills/<name>/` (наш текущий probe).
   - plugin-bundled skill: `<plugin-root>/skills/<plugin>:<skill-name>/` (e.g. `~/.claude/plugins/superpowers/skills/requesting-code-review/`).
   - marketplace/installed plugin: location depends on plugin manager.
   
   Reliable detection: scan `~/.claude/plugins/*/skills/<name>/` AND `~/.claude/skills/<name>/`. If either matches, skill is "present".

2. **Update `scripts/mb-reviewer-resolve.sh`:**
   - Replace `if os.path.isdir(skill_dir)` block with helper `def skill_present(skill_name, roots)`.
   - `roots`: env-injected `MB_SKILLS_ROOT` + `MB_PLUGINS_ROOT` (default `~/.claude/skills` and `~/.claude/plugins`).
   - For plugin namespace `<plugin>:<inner>` syntax in pipeline.yaml (already supported in `agent` field), check `<plugins-root>/<plugin>/skills/<inner>/` first.
   - Fallback to legacy `<skills-root>/<skill>/` for back-compat.

3. **Update `install.sh` step 6.5:** mirror the same probe logic. Print which path matched: `superpowers detected via plugin (~/.claude/plugins/superpowers/skills/requesting-code-review/)` vs `via skill dir (~/.claude/skills/superpowers/)`.

4. **Tests:**
   - `test_mb_reviewer_resolve.py` — new cases: plugin-style skill present in `MB_PLUGINS_ROOT`, both present, neither.
   - Mirror in registration test.

5. **Risk:** plugin paths are not stable Claude Code public API yet. Document the assumption in `mb-reviewer-resolve.sh` header. If layout changes, the resolver still fails-safe (returns `mb-reviewer`).

**Effort estimate:** 1 short sprint (1-2 hours): resolver patch + 3-4 new tests + install.sh probe update + docs comment.

**Plan:** —

## ADR

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
