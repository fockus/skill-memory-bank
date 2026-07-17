---
topic: svp-contract-test-loop
group: sdd-vision-pipeline
ice: {impact: 9, confidence: 8, ease: 5}
ice_confirmed: false
blocked_by: [svp-sdd-core]
covers_umbrella: [REQ-049, REQ-050, REQ-051, REQ-052, REQ-053]
status: ready
---

# Requirements: svp-contract-test-loop

> Spec triple — see also: design.md, tasks.md.
> Слайс S8 группы `sdd-vision-pipeline` (ICE 360, blocked by svp-sdd-core, self-interview).
> Контекст: `context/svp-contract-test-loop.md`; решения подтверждены как **AGR-018**.
> Транскрипты: слайсовый + родительский.
> Ревизия 2 (2026-07-17): закрыты находки круга 2 (R2-001…R2-013); формулировка REQ-001 приведена
> к «до всех задач реализации» (не «первая в списке»); канонический владелец блока `layers` —
> frontmatter этого файла.
>
> EARS: Ubiquitous `THE SYSTEM SHALL` · Event `WHEN …` · State `WHILE …` · Optional `WHERE …` · Unwanted `IF … THEN …`

## Requirements (EARS)

### Requirement 1: Контрактная задача идёт до всех задач реализации

**User Story:** As an implementer, I want the contract and its deterministic checkers built before any business code, so that "done" is decided by code rather than by my own judgement.

#### Acceptance Criteria

- **REQ-001** (state-driven): While a spec declares `contract_first: true` and carries at least one gated requirement, the system shall generate exactly one contract task ordered before all implementation tasks. <!-- S8-D-01 -->
- **REQ-002** (ubiquitous): The contract task shall consist of five ordered steps — declare contracts from the spec, write unit tests for the checkers, implement the checkers, make the checker unit tests green, observe the checkers red against the unimplemented product — and shall contain no business code. <!-- S8-D-02 -->
- **REQ-003** (ubiquitous): The checker unit tests shall assert both halves on fixtures — the checker rejects a violating fixture and accepts a conforming one. <!-- S8-D-03 -->
- **REQ-004** (event-driven): When the checker unit tests are green, the system shall run the checkers against the real product and record the resulting red run before implementation starts. <!-- S8-D-04 -->
- **REQ-005** (unwanted): If a checker passes against the product before the covered implementation exists, then the system shall fail the contract task with `fake_red` and shall leave it open. <!-- S8-D-04 -->
- **REQ-006** (unwanted): If a requirement cannot be made observable by a checker, then the system shall escalate it as a spec defect instead of silently downgrading it to an LLM-only check. <!-- S8-D-04 -->

### Requirement 2: Слои тестов — отдельные задачи

**User Story:** As a spec author, I want integration and e2e tests to be their own tasks at the end of the spec, so that business behaviour is proven and not dissolved into per-task testing notes.

#### Acceptance Criteria

- **REQ-007** (state-driven): While a spec declares `integration_tests: true`, the system shall generate a dedicated integration-test task ordered after all implementation tasks. <!-- S8-D-05 -->
- **REQ-008** (state-driven): While a spec declares `e2e_tests: true`, the system shall generate one dedicated e2e-test task ordered after all implementation tasks and, when an integration task exists, after that integration task. <!-- S8-D-05, R3-003 -->
- **REQ-009** (ubiquitous): Each test-layer task shall cover the success scenario plus the spec's main edge scenarios, and its DoD shall name the covered scenario ids. <!-- S8-D-05 -->
- **REQ-010** (ubiquitous): The system shall allow contract checkers and test-layer tests to overlap in coverage and shall not report such overlap as a defect. <!-- S8-D-11 -->

### Requirement 3: Отключение слоёв — явное и машиночитаемое

**User Story:** As a user in a hurry, I want to switch layers off when I create the spec, so that speed is a recorded decision instead of a silently skipped step.

#### Acceptance Criteria

- **REQ-011** (event-driven): When the user declines a layer during spec creation, the system shall record `layers.<layer>: false` with a reason in the `requirements.md` frontmatter — the block's single canonical owner — and shall omit the corresponding task. <!-- S8-D-06 -->
- **REQ-012** (event-driven): When `/mb sdd` generates a new spec, the system shall write an explicit `layers` block, taking each default from `pipeline.yaml:sdd.layers` (all enabled when unset) and letting an explicit spec value win. <!-- S8-D-06, R3-001 -->
- **REQ-013** (ubiquitous): The system shall treat a spec without a `layers` block as legacy: all three layers disabled, source `legacy`, the file left unmutated, and the new layer gates and the Quality DoD obligation not applied to it. <!-- NFR-002, R3-001 -->
- **REQ-014** (unwanted): If a layer is disabled, then the system shall not require its task during spec validation and shall name the disabled layer in the run summary. <!-- S8-D-06, D-33 -->

### Requirement 4: Quality DoD — правила как критерий

**User Story:** As a reviewer and judge, I want the architecture and code-quality rules named in the spec, so that verdicts cite an agreed criterion instead of personal taste.

#### Acceptance Criteria

- **REQ-015** (ubiquitous): The system shall generate a Quality DoD section in every spec generated by the new SDD pipeline, referencing the resolved rule sources by path without copying their text. <!-- S8-D-07, R3-001 -->
- **REQ-016** (ubiquitous): The rule resolver shall prefer project rules — `<repo>/AGENTS.md`, `<repo>/RULES.md`, `<bank>/RULES.md` or the active rule profile — and shall fall back to the Memory Bank rules file, returning an identical result for implementer, reviewer and judge. <!-- S8-D-07, NFR-003 -->
- **REQ-017** (unwanted): If a declared project rule source is missing, then the system shall fail loudly instead of falling back silently to the Memory Bank rules. <!-- edge case -->
- **REQ-018** (ubiquitous): The system shall satisfy the Quality DoD with the existing deterministic rules checker and shall not introduce a new rule linter. <!-- S8-D-08 -->
- **REQ-019** (event-driven): When an implementer, reviewer or judge is dispatched, the system shall pass the resolved Quality DoD through the existing review rubric channel. <!-- S8-D-09 -->

### Requirement 5: Место в конвейере

**User Story:** As a pipeline owner, I want the new work to fit the fixed stage order, so that nothing in the existing workflow engine breaks.

#### Acceptance Criteria

- **REQ-020** (ubiquitous): The system shall execute the contract task and the test-layer tasks inside the `implement` stage and the checker run against the product inside the `verify` stage, leaving the canonical stage order unchanged. <!-- S8-D-10 -->
- **REQ-021** (event-driven): When `verify` runs on a spec whose contract task is closed, the system shall execute the contract checkers against the product and fail verification on any red checker. <!-- S8-D-10 -->

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: Contract task comes first
**Covers:** REQ-001, REQ-002

- GIVEN спека с двумя gated-требованиями и `contract_first: true`
- WHEN `/mb sdd` генерирует `tasks.md`
- THEN первой задачей стоит контрактная задача с пятью шагами и без бизнес-кода
- AND каждая последующая задача реализации идёт после неё
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: Fake red fails the contract task
**Covers:** REQ-004, REQ-005

- GIVEN чекер, который проходит против текущего репозитория до появления реализации
- WHEN исполнитель доходит до шага 5 контрактной задачи
- THEN задача падает с `fake_red`, чекбокс не закрывается
- AND чекер возвращается на переработку в поведенческую проверку
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: Checker without a negative fixture rejected
**Covers:** REQ-003

- GIVEN юнит-тесты чекера содержат только позитивную фикстуру
- WHEN проверяются шаги 2–4 контрактной задачи
- THEN шаг 4 не закрыт: тесты чекера объявлены неполными
- AND требуется тест, доказывающий, что чекер отвергает нарушающую фикстуру
<!-- /mb-scenario:3 -->

<!-- mb-scenario:4 -->
### Scenario: Unobservable requirement escalates
**Covers:** REQ-006

- GIVEN gated-требование, которое невозможно проверить кодом снаружи
- WHEN исполнитель пытается объявить для него чекер
- THEN поднимается эскалация «дефект спеки»
- AND требование переформулируется или явно помечается как проверяемое только LLM-ревью
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: Two test layers at the end of the spec
**Covers:** REQ-007, REQ-008, REQ-009

- GIVEN спека с `integration_tests: true` и `e2e_tests: true` и тремя сценариями
- WHEN генерируется `tasks.md`
- THEN после всех задач реализации идёт задача интеграционных тестов, затем задача e2e
- AND DoD каждой из них перечисляет id покрываемых сценариев
<!-- /mb-scenario:5 -->

<!-- mb-scenario:6 -->
### Scenario: Fast mode refusal is recorded
**Covers:** REQ-011, REQ-014

- GIVEN пользователь при создании спеки отказался от e2e ради скорости
- WHEN спека сгенерирована и запущена
- THEN frontmatter содержит `e2e_tests: false` с причиной, задачи e2e нет
- AND валидация не требует e2e-задачу, а итог прогона называет отключённый слой
<!-- /mb-scenario:6 -->

<!-- mb-scenario:7 -->
### Scenario: Legacy spec read without mutation
**Covers:** REQ-012, REQ-013

- GIVEN спека без блока `layers` в frontmatter
- WHEN её читает парсер
- THEN она трактуется как легаси: все три слоя `false`, `source=legacy`, файл не изменяется, новые layer-гейты и обязательность Quality DoD к ней не применяются
- AND спека с явным блоком берёт значения из него (spec wins), а недостающие ключи — из `pipeline.yaml:sdd.layers`
<!-- /mb-scenario:7 -->

<!-- mb-scenario:8 -->
### Scenario: Project rules beat bank rules
**Covers:** REQ-015, REQ-016, REQ-019

- GIVEN проект содержит собственный `RULES.md`
- WHEN резолвится Quality DoD для исполнителя, ревьюера и судьи
- THEN секция ссылается на проектный файл по пути, текст правил не копируется
- AND все трое получают идентичный резолв через существующий канал рубрики
<!-- /mb-scenario:8 -->

<!-- mb-scenario:9 -->
### Scenario: Missing rule source fails loudly
**Covers:** REQ-017

- GIVEN спека ссылается на `<repo>/RULES.md`, которого нет
- WHEN запускается резолвер правил
- THEN он завершается ошибкой с указанием отсутствующего пути
- AND тихого отката на правила банка не происходит
<!-- /mb-scenario:9 -->

<!-- mb-scenario:10 -->
### Scenario: Verify runs the contract checkers
**Covers:** REQ-020, REQ-021

- GIVEN контрактная задача закрыта, бизнес-код написан, юнит-тесты зелёные
- WHEN выполняется стадия `verify`
- THEN контрактные чекеры прогоняются против продукта
- AND любой красный чекер валит верификацию, порядок стадий при этом не меняется
<!-- /mb-scenario:10 -->

<!-- mb-scenario:11 -->
### Scenario: Quality DoD uses the existing checker
**Covers:** REQ-018

- GIVEN спека с Quality DoD и изменённые файлы
- WHEN проверяется пункт DoD о правилах
- THEN он исполняется существующим `mb-rules-check.sh`
- AND нового линтера правил в репозитории не появляется
<!-- /mb-scenario:11 -->

<!-- mb-scenario:12 -->
### Scenario: Coverage overlap is not a defect
**Covers:** REQ-010

- GIVEN контрактный чекер и интеграционный тест проверяют одно и то же требование
- WHEN спека валидируется и ревьюируется
- THEN пересечение не помечается как нарушение DRY
- AND оба остаются в спеке
<!-- /mb-scenario:12 -->
