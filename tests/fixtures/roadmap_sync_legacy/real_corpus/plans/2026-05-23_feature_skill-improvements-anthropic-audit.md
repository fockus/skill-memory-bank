---
type: feature
topic: skill-improvements-anthropic-audit
status: queued
created: 2026-05-23
baseline_commit: 6fc6a504a6dfdb3ead9f98e0be569098fe6235a7
level: sprint
linked_report: .memory-bank/reports/2026-05-23_anthropic-best-practices-audit.md
parallel_safe: true
depends_on: ["2026-05-24_fix_ci-baseline-wave-0.md"]
---

# Plan: feature — skill-improvements-anthropic-audit

**Baseline commit:** 6fc6a504a6dfdb3ead9f98e0be569098fe6235a7

## Context

**Problem:** В аудите `reports/2026-05-23_anthropic-best-practices-audit.md` выявлены формальные расхождения скила с Anthropic best-practices (skill authoring, Claude Code, memory model). После обсуждения с автором установлено, что ключевые расхождения (размер global CLAUDE.md, широкий description trigger, opt-in ceremony в `/mb work`, `/mb init` lifecycle) являются **осознанными design-решениями**, обоснованными конкретными use cases (глобальный rules-delivery, агент должен знать правила заранее, opt-in choice). Однако эти решения **нигде не задокументированы** — для нового пользователя они выглядят как нарушения best-practices, а не как намеренные trade-offs. Также не зафиксирован skill-testing matrix (Haiku/Sonnet/Opus), отсутствует discovery-eval suite, новичкам трудно ориентироваться в 25 командах.

**Expected result:** Шесть атомарных артефактов, повышающих maintainability и onboarding:
1. `docs/DESIGN-DECISIONS.md` — обоснование намеренных отклонений от Anthropic guidance.
2. `CONTRIBUTING.md` дополнен skill-testing matrix.
3. `evaluations/skill-discovery/` — 3+ JSON-сценария для проверки триггеринга.
4. README дополнен Quick-start блоком (5 базовых команд).
5. README дополнен разделом "Vibe coding mode" (rules-only режим как first-class).
6. `install.sh` дополнен interactive prompt: `minimal` vs `full` install profile.

После выполнения скил остаётся backward-compatible by default, но P1-риски больше не маскируются как «только документация»: plan должен либо реально снизить risk (install profile / autoload opt-in / slim global-rules source), либо явно записать accepted-risk с owner и revisit date.

**Related files:**
- `.memory-bank/reports/2026-05-23_anthropic-best-practices-audit.md` — источник рекомендаций
- `SKILL.md`, `README.md`, `CONTRIBUTING.md`, `install.sh` — модифицируются
- `~/.claude/CLAUDE.md` (user-global) — НЕ трогается (осознанный размер, см. DESIGN-DECISIONS.md)
- `docs/` — новая директория для дизайн-документации

**Non-goals (explicit):**
- НЕ удалять команды, subagents, хуки в этом docs/evals sprint.
- НЕ ломать поведение `/mb work`, `/mb plan`, `/mb verify`, `/mb done` без explicit opt-in.
- НЕ редактировать user-local `~/.claude/CLAUDE.md` напрямую; изменения идут через repo-owned source/templates/install profile.

**Scope correction (2026-05-24 audit):** P1 findings from the audit are in scope as risk-reduction work. At minimum Stage 1 must document accepted deviations, Stage 5 must make rules-only/vibe mode first-class, and Stage 6 must provide install profiles that make heavy context/hooks opt-in. If global rules slimming or `MB_AUTOLOAD_CONTEXT=off` is rejected, record it as accepted risk with owner + revisit date in `docs/DESIGN-DECISIONS.md`.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: DESIGN-DECISIONS.md — обоснование намеренных отклонений

**What to do:**
- Создать `docs/DESIGN-DECISIONS.md` со структурой: одна секция на одно осознанное отклонение.
- Покрыть минимум 5 решений:
  1. **Wide description trigger** — почему `code rules`, `workflow`, `dev-toolkit` намеренно широкие (глобальный rules-delivery даже без `.memory-bank/`).
  2. **Global CLAUDE.md ~190 строк** — почему агент должен знать правила и команды заранее, без on-demand load.
  3. **25 slash-команд** — разделение на canonical path (`/mb plan → /mb work → /mb verify → /mb done`) и advanced path (`/discuss → /sdd → /work`); overlap намеренный для разных сценариев.
  4. **16 subagents** — почему ролевые специализации (`mb-ios`, `mb-android`, `mb-frontend`, `mb-backend`, ...) присутствуют сразу, а не лениво создаются.
  5. **`MB_AUTOLOAD_CONTEXT=auto` default** — почему авто-инжект включён по умолчанию (нужно знать состояние с первого хода).
- Каждая секция: формат `## <Decision> — <one-line summary>` + поля **Anthropic recommendation**, **Our choice**, **Why**, **Trade-off accepted**, **When to revisit**.
- Добавить ссылку на этот документ из:
  - `README.md` (раздел Architecture или FAQ);
  - `SKILL.md` (в шапке, рядом с `Design contract`);
  - `CONTRIBUTING.md` (как первый чек-лист «перед PR прочитай»).

**Testing (TDD — tests BEFORE implementation):**
- Добавить `tests/bats/test_design_decisions_doc.bats` с проверками:
  - `docs/DESIGN-DECISIONS.md` существует;
  - содержит минимум 5 секций уровня H2;
  - каждая секция содержит ключевые поля (`Anthropic recommendation`, `Our choice`, `Why`, `Trade-off`, `When to revisit`);
  - `README.md`, `SKILL.md`, `CONTRIBUTING.md` содержат относительную ссылку на `docs/DESIGN-DECISIONS.md`.
- Red команда: `bats tests/bats/test_design_decisions_doc.bats` — все тесты падают до создания файла.

**DoD (Definition of Done):**
- [ ] `docs/DESIGN-DECISIONS.md` создан, содержит минимум 5 design decisions с полным заполнением полей.
- [ ] Каждая секция ≤ 30 строк (компактность).
- [ ] Внутренние ссылки на Anthropic docs (с явным `[best-practices]` / `[memory]` маркером).
- [ ] Минимум одна цитата verbatim из Anthropic guidance per decision.
- [ ] Ссылки из README/SKILL.md/CONTRIBUTING.md проверены (`grep` находит их).
- [ ] `bats tests/bats/test_design_decisions_doc.bats` зелёный.

**Code rules:** No placeholders, no TODO. Цитаты Anthropic — verbatim, с источником. Принцип «documentation as code» — изменения проходят через тесты.

**Edge cases:**
- Если Anthropic обновит guidance — secondary review через 6 месяцев (отметить как `When to revisit: 2026-11-23`).
- Решение может быть пересмотрено в будущем (поле `When to revisit` обязательно).

---

<!-- mb-stage:2 -->
### Stage 2: CONTRIBUTING.md — skill testing matrix

**What to do:**
- Добавить в `CONTRIBUTING.md` секцию `## Testing matrix` после существующего контента.
- Зафиксировать поддерживаемые модели: `claude-haiku-4-5`, `claude-sonnet-4-6`, `claude-opus-4-7`.
- Для каждой модели описать:
  - **Discovery test** — скил подгружается на ожидаемые триггер-фразы;
  - **Rules adherence** — правила TDD/Clean Architecture применяются;
  - **Command behaviour** — `/mb start`, `/mb plan`, `/mb done` работают как описано.
- Описать процедуру manual testing: чек-лист перед релизом + how-to запустить eval-сценарии из Stage 3.
- Указать минимальное покрытие для PR: должны пройти discovery-eval (Stage 3) на минимум одной модели (Sonnet как baseline).

**Testing (TDD):**
- Расширить `tests/bats/test_contributing_doc.bats` (создать, если нет) с проверками:
  - `CONTRIBUTING.md` содержит секцию `## Testing matrix`;
  - перечислены минимум 3 модели Claude по их exact model IDs;
  - присутствует ссылка на `evaluations/skill-discovery/`.
- Red команда: `bats tests/bats/test_contributing_doc.bats` падает на отсутствии секции.

**DoD:**
- [ ] `CONTRIBUTING.md` § Testing matrix присутствует.
- [ ] Перечислены exact model IDs: `claude-haiku-4-5-20251001`, `claude-sonnet-4-6`, `claude-opus-4-7`.
- [ ] Описан минимальный test scope для PR.
- [ ] Ссылка на eval-suite (Stage 3) присутствует.
- [ ] `bats tests/bats/test_contributing_doc.bats` зелёный.

**Code rules:** Testing-trophy mindset — describe matrix как контракт, не как «when convenient».

**Edge cases:**
- Если в Anthropic выйдет новая модель (например, Haiku 4.6) — обновление матрицы становится частью release-checklist (отметить в CONTRIBUTING).
- Eval suite Stage 3 — единственный automated tier; manual testing описан, но не enforced в CI.

---

<!-- mb-stage:3 -->
### Stage 3: evaluations/skill-discovery — JSON eval suite

**What to do:**
- Создать директорию `evaluations/skill-discovery/`.
- Минимум 5 JSON-сценариев (`evaluations/skill-discovery/NN_<name>.json`):
  1. `01_memory_bank_active_project.json` — запрос «расскажи статус проекта» в проекте с `.memory-bank/` → скил должен активироваться.
  2. `02_rules_only_project.json` — запрос «как мне писать тесты по TDD?» в проекте без `.memory-bank/` → скил должен активироваться (rules-only mode).
  3. `03_unrelated_task.json` — запрос «напиши hello world на Python» → скил **не должен** доминировать (можно загрузиться, но не навязывать `/mb` workflow).
  4. `04_explicit_mb_command.json` — запрос «запусти `/mb start`» → скил активируется явно.
  5. `05_explicit_anti_trigger.json` — запрос «расскажи про Vim shortcuts» → скил **не** активируется.
- Формат каждого файла:
  ```json
  {
    "id": "01_memory_bank_active_project",
    "skills": ["memory-bank"],
    "query": "...",
    "context": {"project_has_memory_bank": true},
    "expected_behavior": [
      "Skill memory-bank is invoked",
      "First response line is [MEMORY BANK: ACTIVE]",
      "Agent reads .memory-bank/status.md or checklist.md"
    ],
    "anti_expected": [
      "Skill memory-bank is NOT invoked for unrelated queries"
    ]
  }
  ```
- Создать `evaluations/README.md` с инструкцией: как запускать вручную (т.к. Anthropic пока не предоставляет built-in eval runner).
- Создать `scripts/mb-eval-check.sh` — скелет CLI, который принимает JSON и проверяет наличие required fields (`id`, `query`, `expected_behavior`).

**Testing (TDD):**
- Добавить `tests/pytest/test_eval_suite.py` с проверками:
  - все JSON в `evaluations/skill-discovery/` парсятся как valid JSON;
  - каждый содержит fields: `id`, `skills`, `query`, `expected_behavior`;
  - минимум 5 файлов;
  - `scripts/mb-eval-check.sh` существует и `chmod +x`;
  - запуск `mb-eval-check.sh evaluations/skill-discovery/01_*.json` exit 0 на valid файлe.
- Дополнительный bats: `tests/bats/test_mb_eval_check.bats` — exit 1 на invalid JSON (отсутствует `id` или `expected_behavior`).
- Red команда: `pytest tests/pytest/test_eval_suite.py` падает.

**DoD:**
- [ ] `evaluations/skill-discovery/` содержит ≥ 5 JSON-сценариев с указанной структурой.
- [ ] `evaluations/README.md` объясняет цель и как запускать.
- [ ] `scripts/mb-eval-check.sh` валидирует JSON-формат.
- [ ] Все pytest + bats тесты зелёные.
- [ ] Один из сценариев покрывает rules-only mode (`[MEMORY BANK: ABSENT]`).
- [ ] Один сценарий — anti-trigger (скил не должен активироваться).

**Code rules:** Eval как код. Шелл-скрипт фейлится с ясной ошибкой («missing field: expected_behavior»), не «punt to Claude».

**Edge cases:**
- Когда Anthropic выпустит built-in eval runner — миграция через `scripts/mb-eval-check.sh` будет thin wrapper.
- Запуск evals не блокирует CI (manual tier), но `mb-eval-check.sh` структурной валидацией ловит regressions JSON-файлов.

---

<!-- mb-stage:4 -->
### Stage 4: README — Quick-start с 5 базовыми командами

**What to do:**
- В `README.md` найти существующий раздел установки/quick-start; если нет — создать.
- Добавить блок **"## Quick start — 5 commands to know"** в самом начале (после badges/intro):
  ```
  1. `/mb init` — first-time setup in a project
  2. `/mb start` — load context at session begin
  3. `/mb plan <type> <topic>` — create plan with DoD
  4. `/mb verify` — verify code vs plan
  5. `/mb done` — close session, save progress
  ```
- Остальные 20 команд — переместить под `<details><summary>Advanced commands (20+)</summary>...</details>` дальше в README.
- Добавить ссылку «Why so many commands?» → `docs/DESIGN-DECISIONS.md#25-slash-commands`.

**Testing (TDD):**
- Расширить `tests/bats/test_readme_structure.bats` (создать, если нет):
  - `README.md` содержит секцию `## Quick start`;
  - в Quick-start ровно 5 команд (regex match `^\d\. \`/mb`);
  - присутствует `<details>` блок с `Advanced commands`;
  - присутствует ссылка на `docs/DESIGN-DECISIONS.md`.
- Red команда: `bats tests/bats/test_readme_structure.bats` падает.

**DoD:**
- [ ] `README.md` § Quick start — 5 команд, в указанном порядке.
- [ ] Advanced commands перенесены в `<details>` (не удалены).
- [ ] Ссылка на DESIGN-DECISIONS.md присутствует.
- [ ] Существующий контент README **не потерян** (diff проверен).
- [ ] `bats tests/bats/test_readme_structure.bats` зелёный.

**Code rules:** Progressive disclosure (Anthropic-стиль): newcomer видит 5 команд, advanced пользователь раскрывает `<details>`.

**Edge cases:**
- Если README редактируется параллельно — merge conflict разрешается в пользу Quick-start (приоритет — onboarding).

---

<!-- mb-stage:5 -->
### Stage 5: README — раздел "Vibe coding mode"

**What to do:**
- Добавить в `README.md` после Quick-start раздел **"## Vibe coding mode (no Memory Bank)"**:
  - Объяснить что `[MEMORY BANK: ABSENT]` — валидное состояние, а не ошибка.
  - Указать что rules (TDD, Clean Architecture, SOLID) **продолжают применяться** даже без `/mb init`.
  - Дать сценарий «когда НЕ нужен Memory Bank»: прототипы ≤ 1 дня, one-shot скрипты, exploratory работа.
  - Дать сценарий «когда нужен»: фичи > 1 дня, командная работа, проекты с roadmap.
- Закрепить решение: «Если ты сомневаешься — не запускай `/mb init`; правила работают и так».
- Ссылку на `docs/DESIGN-DECISIONS.md#rules-only-mode` (если в Stage 1 секция называется иначе — синхронизировать имя).

**Testing (TDD):**
- Расширить `tests/bats/test_readme_structure.bats`:
  - `README.md` содержит секцию с заголовком включающим `Vibe coding` (case-insensitive);
  - присутствует фраза о rules-only / `[MEMORY BANK: ABSENT]`;
  - присутствует «when NOT to use» / «when to use» дихотомия.

**DoD:**
- [ ] `README.md` § Vibe coding mode присутствует.
- [ ] Описаны both scenarios (when to use / when not).
- [ ] Явное утверждение что rules остаются активными без `/mb init`.
- [ ] Ссылка на DESIGN-DECISIONS.md.
- [ ] `bats tests/bats/test_readme_structure.bats` зелёный.

**Code rules:** Documentation-as-contract — раз vibe-mode заявлен first-class, тесты ловят регрессию.

**Edge cases:**
- Stage 5 зависит от Stage 1 (DESIGN-DECISIONS.md секция `rules-only-mode` должна существовать для рабочей ссылки). Если Stage 1 ещё не сделан — Stage 5 либо ждёт, либо использует временно anchor `#vibe-coding`.

---

<!-- mb-stage:6 -->
### Stage 6: install.sh — interactive minimal/full profile prompt

**What to do:**
- Проанализировать существующий `install.sh` на наличие install-profile логики (есть упоминание в `references/design-principles.md`: `minimal | core | goals | autopilot | full`).
- Добавить в начало `install.sh` interactive prompt (если уже есть — улучшить):
  ```
  Choose install profile:
    [1] minimal   — bank structure only, no hooks, no rules in global CLAUDE.md
    [2] core      — bank + commands + rules (recommended for solo devs)
    [3] full      — bank + commands + rules + hooks + subagents (recommended for teams)
  Default: [2] core
  ```
- Сохранить выбор в `.installed-manifest.json` (поле `install_profile`).
- Если `--profile=<name>` передан как CLI флаг — пропустить interactive prompt.
- Документировать в `install.sh --help`.

**Testing (TDD):**
- Расширить `tests/bats/test_install.bats`:
  - `install.sh --help` упоминает `--profile`;
  - `install.sh --profile=minimal --dry-run` exit 0;
  - `install.sh --profile=invalid` exit 1 с понятной ошибкой;
  - после установки `.installed-manifest.json` содержит поле `install_profile`.
- Red команда: `bats tests/bats/test_install.bats` падает на новых тестах.

**DoD:**
- [ ] `install.sh` поддерживает `--profile=minimal|core|full`.
- [ ] Interactive prompt появляется при отсутствии флага.
- [ ] Default = `core` (явно документирован).
- [ ] `.installed-manifest.json` хранит выбранный профиль.
- [ ] `bats tests/bats/test_install.bats` зелёный.
- [ ] Существующая логика установки не сломана (idempotent re-install проверен).

**Code rules:** Backwards-compat (старые манифесты без `install_profile` должны парситься). Fail-fast на invalid профиле. No silent fallbacks.

**Edge cases:**
- Non-interactive shell (CI) — fail с понятным сообщением «pass --profile=<name> in non-interactive mode» (не fallback на дефолт молча).
- Если в существующем `install.sh` уже есть `--profile` логика — Stage 6 сводится к улучшению UI и тестам.
- Сами хуки/subagents/CLAUDE.md edits — НЕ меняются между профилями в этом плане; только **что устанавливается** меняется. Конкретный mapping profile→files выносится в `install.sh` constants и документируется в `docs/DESIGN-DECISIONS.md` (доп. секция).

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| `docs/DESIGN-DECISIONS.md` со временем расходится с реальным поведением | M | Поле `When to revisit: YYYY-MM-DD` в каждой секции + 6-месячный review-cycle |
| Quick-start конфликтует с существующим README content | M | Stage 4 явно проверяет «existing content not lost» через diff |
| install.sh profile logic ломает идемпотентность ре-инсталла | M | bats-тест на idempotent re-install в Stage 6 DoD |
| Eval JSON формат разойдётся с Anthropic built-in eval runner (когда выйдет) | L | `scripts/mb-eval-check.sh` как thin wrapper — миграция через adapter pattern |
| Stage 1 (DESIGN-DECISIONS) → Stage 5 (vibe coding ссылка) — coupling | L | Stage 1 первым, anchor `rules-only-mode` зафиксирован contract'ом тестов |
| Изменение README ломает downstream-документацию (Wiki, Notion копии) | L | README остаётся source of truth; вне-репо копии обновляются вручную (вне scope) |

## Gate (plan success criterion)

Plan complete когда:
1. Все 6 stages прошли `/mb verify` (plan-verifier APPROVED).
2. Все red→green тесты переведены в зелёные (bats + pytest).
3. `docs/DESIGN-DECISIONS.md` содержит ≥ 5 design decisions с заполненными полями.
4. `CONTRIBUTING.md` содержит testing matrix.
5. `evaluations/skill-discovery/` содержит ≥ 5 JSON-сценариев + README + валидатор.
6. `README.md` содержит Quick-start (5 команд) + Vibe coding mode + ссылку на DESIGN-DECISIONS.
7. `install.sh` поддерживает `--profile=minimal|core|full` + interactive prompt + manifest persistence.
8. **Non-goals соблюдены:** ни одна строка не удалена из global `~/.claude/CLAUDE.md`, description trigger не сужен, дефолты не сменены, команды/хуки/subagents не удалены (diff-проверка перед `/mb done`).
9. CHANGELOG обновлён с entry «docs: anthropic best-practices audit follow-through».
