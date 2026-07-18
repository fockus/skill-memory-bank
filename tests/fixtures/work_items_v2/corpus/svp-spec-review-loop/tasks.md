# Tasks: svp-spec-review-loop

> Слайс S9 (ICE 336 не подтверждён, blocked by S2 `svp-sdd-core` — Task'и потребляют C5-журнал,
> `mb-sdd-review-result.sh` и pipeline-блок `sdd.*`, создаваемые S2#7). `review: waived` (AGR-022).
> Eval материализуется первым (red), затем реализация (green) — D-05 родительской группы.
> Red-условия описывают состояние **после** материализации теста: `bats <missing>` даёт exit 1 +
> `not ok 1 bats-gather-tests` — тот же код, что настоящий провал, поэтому red доказывается якорем
> `output~:` по имени теста, а не exit-кодом (норма X-05, S2-C1). Имена bats-тестов — ASCII,
> несут токены из якорей `output~:`. Роли — bare (парсер добавляет `mb-` сам).
> Бюджеты: Stage 1 = 350000 (≤ 400000 stage; задачи ≤ 120000).

<!-- mb-task:1 -->
## Task 1: C1 — pipeline-схема `sdd.spec_judge` + валидация

**Stage:** 1
**Covers:** REQ-001
**Role:** backend
**Blocked-by:** svp-sdd-core#7
**Scope:** references/pipeline.default.yaml, scripts/mb-pipeline-validate.sh, tests/bats/test_spec_judge_config.bats
**Budget:** 60000

**What to do:**
- Инлайн-мапа `spec_judge: {enabled: false, agent: mb-judge, model: <exact>, thinking: medium, max_cycles: 2}`
  в `references/pipeline.default.yaml` рядом с `spec_review` (обязательно PyYAML-optional пути
  `parse_simple_mapping`+`parse_inline_map`); опциональный ключ `rubric:` добавляется в мапу `spec_review`.
- Проверки в `mb-pipeline-validate.sh` рядом с существующими `sdd.*`: типы полей, `max_cycles` ≥ 1,
  закрытый набор ключей, правило `spec_judge_requires_spec_review` (enabled-судья при выключенном ревью → ошибка).

**Eval:** `bats tests/bats/test_spec_judge_config.bats` — red: bats-файл материализован, в `references/pipeline.default.yaml` нет ключа `spec_judge` и валидатор его не знает, каждый кейс падает; exit: 1; output~: `not ok [0-9]+ spec_judge_(schema_default|inline_map|requires_spec_review|max_cycles_invalid)`

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_spec_judge_config.bats` ДО правок: `spec_judge_schema_default` (дефолтный файл
  парсится, enabled=false); `spec_judge_inline_map` (значения читаются без PyYAML);
  `spec_judge_requires_spec_review` (enabled-судья + выключенное ревью → ошибка валидации с сигнатурой);
  `spec_judge_max_cycles_invalid` (0 и нечисло → ошибка); `spec_judge_unknown_key` (лишний ключ → ошибка);
  `spec_review_rubric_key` (ключ `rubric` валиден и опционален).
- shellcheck clean; Bash 3.2 (macOS) + Linux.

**DoD:**
- [ ] Схема в дефолтном pipeline + валидация полей и связки review↔judge; поведение без правок конфига байт-идентично
- [ ] bats green (был red по заявленному якорю); shellcheck clean
<!-- /mb-task:1 -->

<!-- mb-task:2 -->
## Task 2: C2 — журнал: `record --kind judge|override`, `check --judge`, `status`

**Stage:** 1
**Covers:** REQ-002, REQ-003, REQ-006
**Role:** backend
**Blocked-by:** 1, svp-sdd-core#7
**Scope:** scripts/mb-sdd-review-result.sh, tests/bats/test_spec_judge_journal.bats
**Budget:** 90000

**What to do:**
- Расширить `scripts/mb-sdd-review-result.sh` по C2: `record --kind judge --decision …[--items]`,
  `record --kind override`, `check --judge` (тройная same_model-проверка, stderr `same_model`, exit 2;
  отсутствие `generated_by` → предупреждение `generator_model_unknown`, не ошибка),
  `status` (одна строка `spec_review=… judge=… override=…` по последним валидным строкам, exit 0).
- Существующие подкоманды S2 не менять; журнал append-only.

**Eval:** `bats tests/bats/test_spec_judge_journal.bats` — red: bats-файл материализован, у `scripts/mb-sdd-review-result.sh` нет подкоманд judge/override/status (usage error), каждый кейс падает; exit: 1; output~: `not ok [0-9]+ judge_journal_(record_go|record_no_go|items_required|override|same_model_triple|status_line|status_empty)`

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_spec_judge_journal.bats` ДО правок: `judge_journal_record_go` (строка с ts/attempt/kind/decision,
  exit 0); `judge_journal_record_no_go` (exit 1); `judge_journal_items_required` (GO_WITH_BACKLOG без
  `--items` при выживших → exit 1); `judge_journal_override` (kind=override, exit 0);
  `judge_journal_same_model_triple` (judge=review-модель и judge=генератор → `same_model`, exit 2;
  без `generated_by` → предупреждение, exit 0); `judge_journal_status_line` (полный журнал → одна
  строка точного формата); `judge_journal_status_empty` (журнала нет → все `none`/`no`, exit 0);
  append-only: повторный record не меняет прежних строк (байтовое сравнение префикса).
- shellcheck clean; путь банка с пробелами.

**DoD:**
- [ ] Все подкоманды C2 с точными exit-кодами и сигнатурами; журнал append-only доказан тестом
- [ ] bats green (был red по заявленному якорю); shellcheck clean
<!-- /mb-task:2 -->

<!-- mb-task:3 -->
## Task 3: C4+C6 — промпт-сборщик, рубрика, реестр отклонений

**Stage:** 1
**Covers:** REQ-007, REQ-008, REQ-012, REQ-013
**Role:** backend
**Blocked-by:** 1
**Scope:** scripts/mb-sdd-review-prompt.sh, references/spec-review-rubric.md, references/templates.md, tests/bats/test_spec_review_prompt.bats, tests/bats/fixtures/spec-review/**
**Budget:** 80000

**What to do:**
- `references/spec-review-rubric.md` — bundled default (11-пунктовая рубрика трёх кругов, перенос
  из `reports/2026-07-17_review_spec-group-round3-raw/rubric.md` с очисткой групповых частностей).
- `scripts/mb-sdd-review-prompt.sh` по C4: рубрика (pipeline `rubric:` | дефолт; отсутствие
  кастомного файла → `rubric_not_found path=…`, exit 2) + блок отклонений из
  `specs/<topic>/review-deviations.md` (только непустой) + список файлов спеки + схема вердикта;
  детерминированный stdout.
- Шаблон реестра C6 (таблица id/source/decision/evidence/date) — в `references/templates.md`.

**Eval:** `bats tests/bats/test_spec_review_prompt.bats` — red: bats-файл материализован, `scripts/mb-sdd-review-prompt.sh` и `references/spec-review-rubric.md` не существуют, каждый кейс падает на вызове; exit: 1; output~: `not ok [0-9]+ review_prompt_(default_rubric|custom_rubric|rubric_not_found|deviations_block|no_deviations|deterministic)`

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_spec_review_prompt.bats` ДО реализации на фикстурах `fixtures/spec-review/**`:
  `review_prompt_default_rubric` (без ключа — bundled-рубрика в stdout); `review_prompt_custom_rubric`
  (ключ задан — кастомная, bundled отсутствует); `review_prompt_rubric_not_found` (битый путь →
  сигнатура, exit 2); `review_prompt_deviations_block` (непустой реестр → блок с инструкцией
  do-not-re-raise); `review_prompt_no_deviations` (нет файла/пустой → блока нет);
  `review_prompt_deterministic` (два прогона → байт-идентичный stdout).
- shellcheck clean.

**DoD:**
- [ ] Сборщик детерминирован, рубрика и реестр включаются по правилам C4; шаблон реестра в templates
- [ ] bats green (был red по заявленному якорю); shellcheck clean
<!-- /mb-task:3 -->

<!-- mb-task:4 -->
## Task 4: C3 — петля review→judge→fix в `commands/sdd.md`

**Stage:** 1
**Covers:** REQ-004, REQ-005
**Role:** developer
**Blocked-by:** 2, 3
**Scope:** commands/sdd.md, tests/bats/test_sdd_review_loop.bats
**Budget:** 60000

**What to do:**
- Расширить шаг 9 конвейера в `commands/sdd.md` до 9a/9b/9c по C3: сборка промпта ТОЛЬКО через C4;
  судья получает вердикт+триплет+реестр+рубрику; NO_GO → fix-проход → новый независимый review
  (следующий attempt); GO_WITH_BACKLOG → I-NNN через `mb-idea.sh` до принятия; счётчик циклов и
  honest stop `spec=not_accepted reason=review_cycles_exhausted topic=<t>`; канонический порядок
  стадий не меняется.

**Eval:** `bats tests/bats/test_sdd_review_loop.bats` — red: bats-файл материализован, в `commands/sdd.md` нет клауз 9a/9b/9c, каждый кейс падает; exit: 1; output~: `not ok [0-9]+ sdd_loop_(judge_after_review|no_go_refix_rereview|cycles_exhausted_signature|backlog_before_accept|prompt_via_builder)`

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_sdd_review_loop.bats` ДО правок — структурные проверки клауз командного файла
  (по образцу `test_sdd_spec_review.bats` S2#7, НЕ голый `grep -q` одного слова: каждый тест
  проверяет полную клаузу с её операционными токенами): `sdd_loop_judge_after_review` (9b после 9a,
  состав входов судьи); `sdd_loop_no_go_refix_rereview` (NO_GO → fix → новый attempt);
  `sdd_loop_cycles_exhausted_signature` (точная строка сигнатуры); `sdd_loop_backlog_before_accept`
  (GO_WITH_BACKLOG → mb-idea.sh до принятия); `sdd_loop_prompt_via_builder` (9a ссылается на
  `mb-sdd-review-prompt.sh`, ручная сборка запрещена).

**DoD:**
- [ ] Шаг 9a/9b/9c в `commands/sdd.md` полностью соответствует C3; сигнатура honest stop дословная
- [ ] bats green (был red по заявленному якорю)
<!-- /mb-task:4 -->

<!-- mb-task:5 -->
## Task 5: C5 — work-гейт `mb-work-spec-gate.sh` + врезка `commands/work.md`

**Stage:** 1
**Covers:** REQ-009, REQ-010, REQ-011
**Role:** backend
**Blocked-by:** 2
**Scope:** scripts/mb-work-spec-gate.sh, commands/work.md, tests/bats/test_work_spec_gate.bats
**Budget:** 60000

**What to do:**
- `scripts/mb-work-spec-gate.sh` по C5: молчание при выключенном ревью/пустом статусе;
  `work=blocked reason=spec_review_pending topic=<t>` + exit 3 при действующем CHANGES_REQUESTED
  без judge GO/GO_WITH_BACKLOG; `--skip-spec-gate` → `record --kind override` (через C2) +
  `work=proceed reason=override topic=<t>`, exit 0. Статус ТОЛЬКО через `status` C2 (ADR-S9-4).
- Врезка в `commands/work.md`: вызов гейта после резолва spec-target'а, до первого диспатча;
  plan-target'ы без linked_spec не затрагиваются.

**Eval:** `bats tests/bats/test_work_spec_gate.bats` — red: bats-файл материализован, `scripts/mb-work-spec-gate.sh` не существует и в `commands/work.md` нет клаузы гейта, каждый кейс падает; exit: 1; output~: `not ok [0-9]+ work_spec_gate_(blocked|override_journaled|silent_disabled|silent_no_journal|command_clause)`

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_work_spec_gate.bats` ДО реализации: `work_spec_gate_blocked` (CHANGES_REQUESTED
  без judge → точная строка + exit 3); `work_spec_gate_override_journaled` (флаг → proceed, в журнале
  строка kind=override); `work_spec_gate_silent_disabled` (`enabled: false` → stdout пуст, exit 0);
  `work_spec_gate_silent_no_journal` (журнала нет → stdout пуст, exit 0); `work_spec_gate_command_clause`
  (клауза вызова в `commands/work.md` после резолва, до диспатча).
- shellcheck clean; Bash 3.2 + Linux.

**DoD:**
- [ ] Гейт с точными сигнатурами/exit-кодами; единственный источник статуса — `status` C2; врезка в work.md
- [ ] bats green (был red по заявленному якорю); shellcheck clean
<!-- /mb-task:5 -->
