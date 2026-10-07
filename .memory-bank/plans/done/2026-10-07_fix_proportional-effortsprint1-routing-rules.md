---
type: fix
topic: proportional-effortsprint1-routing-rules
status: done
depends_on: ["2026-10-06_feature_key-rules-onboarding.md", "2026-10-07_feature_pipeline-presets-cost-tiers.md"]
parallel_safe: false
linked_specs: []
created: 2026-10-07
---
# Plan: fix — proportional-effort · Sprint 1 «уровни задачи, роутинг, правила тестов и документации»

**Baseline commit:** e351a17b8f114bb985dcc2efbdd5709c731736e6

## Context

**Problem.** На простых задачах скил делает работу уровня большой фичи. Пример из реального отзыва
(2026-10-07): интеграция Telegram API заняла ~2 часа, 40 автотестов, 10 страниц документации.
Правила не различают размер задачи. Найденные источники в нашем тексте:
- always-loaded: «Multi-stage work → a plan first», «Every task carries SMART DoD», «Coverage 85%+»
  (`rules/CLAUDE-GLOBAL.md`, `rules/RULES.md` § Core rules / Coverage);
- проектный `CLAUDE.md` и шаблон: «Mandatory `/mb work` Gate» на любое «implement/fix», даже без плана;
- нет правила против новых документов;
- правила тестов не запрещают мок-тесты склейки/конфигов/внешнего SDK.

Решения владельца: AGR-067 (5 уровней), AGR-069 (gate только при плане/спеке), AGR-070 (тесты, coverage
отдельно с порогом), AGR-071 (документация, пропорциональная проверка). Источники: Anthropic skill best
practices («Claude is already very smart», «degrees of freedom»), Claude Code best practices («if you can
describe the diff in one sentence, skip the plan»), prompting best practices для Claude 4.x (avoid
over-engineering, не создавать лишние файлы).

**Expected result.**
1. Один источник уровней — `references/effort-tiers.md`: trivial / small / standard / large / extra, признаки
   каждого уровня и что на нём делается (план, тесты, документация, проверка, workflow).
2. `SKILL.md` § Task routing (≤ 25 строк): оценить уровень до старта, назвать его одной строкой, действовать
   по таблице; при сомнении между соседними уровнями — выбрать нижний и поднять, если всплыл риск.
3. Уровень → workflow берётся из `pipeline.yaml` (`effort_tiers:`), а не зашит в текст: standard →
   `execution`, large → `full-cycle`, extra → `governed-execution` (review ensemble + judge, полные правила).
4. Key rules: `effort-tiers` (locked), `test-behavior`, `docs-minimal`, `targeted-verification`;
   `coverage` — default off, порог настраивается (`overall/core/infra`).
5. Gate `/mb work` срабатывает только при существующем плане/спеке; always-loaded файлы без безусловных
   «план на всё», «SMART DoD на каждую задачу», «Coverage 85%».

**Related files:** `references/effort-tiers.md` (new), `SKILL.md`, `references/pipeline.default.yaml`,
`scripts/mb-workflow.sh`, `rules/key-rules.json`, `memory_bank_skill/key_rules.py`,
`references/rules-profile.schema.md`, `scripts/mb-rules.sh`, `rules/CLAUDE-GLOBAL.md`, `rules/RULES.md`,
`references/claude-md-template.md`, `CLAUDE.md`, тесты.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Контракт уровней + роутинг в SKILL.md + `effort_tiers` в pipeline

**What to do:**
- `references/effort-tiers.md`: таблица 5 уровней × (признаки, план, тесты, документация, проверка, workflow).
  - trivial — опечатка, конфиг, переименование: без плана, без новых тестов, проверка одной командой;
  - small — одна фича в 1–3 файлах (интеграция внешнего API): без плана и `/mb work`, один тест на заявленное
    поведение, без новых документов, целевые тесты + линт изменённых файлов;
  - standard — несколько модулей: `/mb plan` → `/mb work` (workflow `effort_tiers.standard`);
  - large — новая подсистема или неясные требования: `discuss → sdd → work`;
  - extra — безопасность, деньги, данные, надёжность, точность: `/mb work` с `effort_tiers.extra`
    (review ensemble + judge), полные правила по коду, coverage включён на время задачи.
  - Явная просьба пользователя (`/mb work`, «сделай план», «без тестов») важнее оценки уровня.
- `SKILL.md` § Task routing — короткий указатель на справочник + правило «оцени до старта».
- `effort_tiers` в `pipeline.yaml` и `mb-workflow.sh --tier` перенесены в план
  `2026-10-07_feature_pipeline-presets-cost-tiers.md` Stage 2 (пресеты simple/medium/complex/governed, AGR-074).
  Справочник и роутинг ссылаются на эти пресеты: small → simple, standard → medium, large → sdd + complex,
  extra → governed.

**Testing (TDD — tests BEFORE implementation):**
- pytest `test_effort_tiers.py`: справочник содержит ровно 5 уровней в порядке; каждый упомянутый пресет
  существует в `pipeline.default.yaml`; `SKILL.md` ссылается на справочник;
  `test_skill_guide_compliance.py` зелёный (SKILL.md ≤ 300 строк).

**DoD:**
- [x] тесты красные до, зелёные после; `mb-pipeline-validate.sh` проходит на default и на этом репо
  - частично (2026-10-07): `references/effort-tiers.md` + `test_effort_tiers.py` RED→GREEN, pipeline-validate rc=0 на обоих; открыто — указатель § Task routing в SKILL.md (`test_repo_files_mentioned_in_skill` красный до него)
- [x] SKILL.md ≤ 300 строк, § Task routing ≤ 25 строк
  - 2026-10-07: SKILL.md 250 строк, § Task routing 3 строки; `test_effort_tiers.py` + `test_repo_files_mentioned_in_skill` зелёные; pipeline-validate rc=0 на default и `.memory-bank/pipeline.yaml`

**Code rules:** одно место для уровней (справочник), одно место для маппинга (pipeline); KISS.

---

<!-- mb-stage:2 -->
### Stage 2: Key rules — уровни, тесты, документация, coverage с порогом

**What to do:**
- `rules/key-rules.json`:
  - process: `effort-tiers` (locked) — «Size the task first (trivial/small/standard/large/extra) and match
    plan, tests, docs and checks to the tier — SKILL.md § Task routing»;
  - process: `targeted-verification` — во время работы целевые тесты и линт изменённых файлов, полный набор —
    в `/mb verify` и перед коммитом, не перезапускать то, что уже показано; заменяет/уточняет
    `evidence-before-done`;
  - process: `docs-minimal` — новые документы только по просьбе; README/CHANGELOG — 1–2 строки;
  - tests: `test-behavior` — тест на поведение, не на строки; не мокать склейку, конфиги и вызовы внешнего SDK;
  - tests: `coverage` → `default:false`, текст с плейсхолдерами порогов.
- Пороги coverage и команда их настройки — в плане `2026-10-07_feature_project-quality-settings.md`
  (`quality.coverage`, `/mb rules set coverage 80/95/70`, AGR-076). Здесь только `coverage` → `default:false`.
- Бюджет всего блока (маркеры + самый длинный указатель хоста) ≤ 3 072 байт сохраняется. На 2026-10-07
  запас 26–60 байт: место под 3 новых правила — за счёт `coverage` → off и слияния/сжатия формулировок
  (например, KISS/YAGNI в одну строку, naming+AAA в `test-behavior`), а не подъёма лимита.

**Testing (TDD):**
- pytest: новые id есть, `effort-tiers` locked, `coverage` default off.

**DoD:**
- [x] тесты красные до, зелёные после; бюджет рендера в лимите (тест) — блок 3022 / 3072 байт

**Code rules:** расширение каталога и профиля из key-rules-onboarding, без второго механизма.

---

<!-- mb-stage:3 -->
### Stage 3: Gate `/mb work` и always-loaded тексты без безусловных требований

**What to do:**
- Проектный `CLAUDE.md` § Mandatory `/mb work` Gate и `references/claude-md-template.md`: gate срабатывает,
  когда задача ссылается на существующий план/спеку банка; иначе — роутинг по уровню (AGR-069).
- `rules/CLAUDE-GLOBAL.md`, `rules/RULES.md` (Core rules, TDD, Coverage, Planning): формулировки привязать к
  уровню — «план для standard+», «SMART DoD в плане», TDD для trivial не нужен, для small — один тест на
  поведение; Coverage — «когда включён в профиле, пороги из профиля».
- Сверка: те же строки в `adapters/_lib_agents_md.sh` не трогать — их заменит рендер Key rules (agents-md-diet).

**Testing (TDD):**
- pytest-гард `test_proportional_effort_texts.py`: в always-loaded файлах (CLAUDE-GLOBAL, шаблон, проектный
  CLAUDE.md) нет безусловных «Every task carries SMART DoD», «Coverage — overall 85%», «Mandatory» gate без
  условия плана/спеки; есть ссылка на § Task routing. `test_global_prompt_guard.py` и
  `test_claude_md_template.py` зелёные.

**DoD:**
- [x] гард красный до, зелёный после; `rules/CLAUDE-GLOBAL.md` ≤ 60 строк
  - 2026-10-07: `test_proportional_effort_texts.py` 7 failed → 21 passed; CLAUDE-GLOBAL 31 строка
- [x] переустановка в temp HOME пересобирает глобальный блок без потери маркеров
  - 2026-10-07: `install.sh --non-interactive` дважды в temp HOME (rc=0/0): `mb-key-rules:start/end` и `[MEMORY-BANK-SKILL]`…`<!-- /memory-bank-skill -->` по одному разу, пользовательский текст после блока сохранён, новая строка про уровни на месте

**Code rules:** правило в одном месте (Key rules / справочник), always-loaded — ссылка, не пересказ.

---

<!-- mb-stage:4 -->
### Stage 4: Parallel execution of independent tasks (AGR-073)

**What to do:**
- `references/effort-tiers.md` + the `effort-tiers` rule: independent tasks have no shared files and no ordering dependency. They are dispatched as one wave of parallel subagents, with one owner per shared file. This is faster, not cheaper; the user can decline.
- `/mb work`:
  - `mb-work-plan.sh` returns a `wave` field for each item, computed from the `Files:` lines and the stage dependencies. Items whose `Files:` sets intersect, or which depend on each other, go into different waves. An item without a `Files:` line goes into its own wave.
  - The orchestrator dispatches each wave in parallel, using the existing per-run mode `MB_WORK_PARALLEL` (single-file discipline, `mb-work-progress-append.sh`).
  - When every wave contains one item, behaviour is byte-identical to the current flow.
- `/mb plan` template: stages declare `Files:` so that waves can be computed.

**Testing (TDD):**
- bats/pytest `mb-work-plan.sh`, three cases:
  - 3 items with disjoint `Files:` → one wave;
  - an intersection → two waves;
  - no `Files:` → separate waves.
- Without parallelism the JSON matches the old output, apart from the new `wave` field.

**DoD:**
- [x] the tests above are green; `commands/work.md` describes the waves in at most 15 lines; the `/mb plan` template includes `Files:`

**Code rules:** reuse the existing `MB_WORK_PARALLEL` infrastructure; no second scheduler.

---

<!-- mb-stage:5 -->
### Stage 5: Декомпозиция планов без лишнего дробления (AGR-078)

**Problem.** Источник — признание агента на Codex: «я слишком дробил работу и запускал независимые проверки на каждом небольшом этапе». Причины в правилах:
- `commands/plan.md:116` и `references/templates.md:169`: «Stages must be atomic (1–5 files, ~5–15 tests, 5–30 min)».
- Даже простой план требует 3–5 этапов, Sprint — 3–7.
- У каждого этапа свои DoD, TDD и сценарии.

**What to do:**
- Определение этапа. Этап — это одно из:
  - граница зависимости, когда следующее требует готового предыдущего;
  - смена слоя или владельца;
  - рискованная контрольная точка;
  - параллелизуемый кусок с непересекающимися `Files:`.

  Этап — не единица размера. Убрать лимиты «1–5 files / 5–30 min» и минимум этапов. Один этап допустим и предпочтителен для small/standard. Sprint — до ~7 этапов как ориентир, а не требование.
- DoD и тесты задаются на план целиком. На отдельном этапе — только если у него своя проверяемая граница. Независимая проверка на каждом этапе не требуется: верификатор по умолчанию запускается в конце плана (AGR-075).
- Лимит 200k на Sprint остаётся ориентиром по контексту, а не поводом дробить.
- Затронуть файлы: `commands/plan.md`, `references/templates.md` (§ Plan decomposition), `references/planning-and-verification.md`, `rules/RULES.md` (§ Planning / Phase 2), шаблон `scripts/mb-plan.sh` (1 этап по умолчанию + комментарий «добавляй этап, только если…»).
- Проверить и при необходимости смягчить: `agents/mb-architect.md` (planner), `commands/sdd.md` / `tasks.md`.
- Строку Planning в `rules/CLAUDE-GLOBAL.md` правит Stage 3.

**Testing (TDD):**
- pytest-гард: в перечисленных файлах нет «1-5 files», «5-30 min», «3-7 stages» как требования и «Stages must be atomic».
- Определение этапа через границы присутствует.
- `mb-plan.sh` создаёт план с одним `<!-- mb-stage:1 -->`; `mb-plan-sync.sh`, `mb-work-plan.sh` и plan-verifier работают с планом из одного этапа (bats).

**DoD:**
- [x] гард и bats зелёные; существующие тесты планов (`test_mb_plan*`, `test_plan_*`) зелёные

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Модель занижает уровень и пропускает тесты на рискованном коде | M | признаки extra перечислены явно (безопасность, деньги, данные); при сомнении — нижний уровень с подъёмом при всплывшем риске; замер на боевых задачах (Sprint 2) |
| Конфликт с key-rules-onboarding по `key-rules.json`/`mb-rules.sh` | M | план стартует после его Stage 4 (`depends_on`) |
| Пользователи с включённым coverage потеряют проверку | L | coverage включается одной командой (`/mb rules set coverage …`, project-quality-settings); CHANGELOG |

## Gate (plan success criterion)

Уровни описаны в одном справочнике и роутятся из SKILL.md; extra резолвится в workflow с review и judge из
`pipeline.yaml`; always-loaded файлы не требуют план/SMART DoD/coverage для каждой задачи; gate `/mb work`
условный; все тесты зелёные.
