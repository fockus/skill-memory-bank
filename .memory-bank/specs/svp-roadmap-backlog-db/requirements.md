---
topic: svp-roadmap-backlog-db
group: sdd-vision-pipeline
ice: {impact: 8, confidence: 9, ease: 6}
ice_confirmed: false
blocked_by: []
covers_umbrella: [REQ-024, REQ-025, REQ-026, REQ-027, REQ-028, REQ-029, REQ-041]
status: ready
---

# Requirements: svp-roadmap-backlog-db

> Spec triple — see also: design.md, tasks.md.
> Слайс S4 группы `sdd-vision-pipeline` (ICE 432, self-interview). Контекст: `context/svp-roadmap-backlog-db.md`;
> транскрипты: `context/svp-roadmap-backlog-db-interview.md` + родительский.
> Ревизия 3 (2026-07-17, spec-review круг 2): REQ-001 и REQ-004 переформулированы под ICE-**компоненты**
> (`{impact, confidence, ease}`, score считает скрипт — родительский Interfaces п.4, D-14) и под
> валидацию питающего frontmatter; сценарии 8/9 исправлены на реальные источники данных и на
> машинную грамматику `list` (R2-005, F-005); добавлены сценарии 11–15 (легаси-порядок F-003,
> ICE-компоненты, глобальный аллокатор F-012, promote-миграция R2-002, typed SPEC-writer R2-004).
> Нумерация REQ и mb-task не менялась; новые REQ не заводились — см. отчёт ревизии.
> Ревизия 4 (2026-07-18, spec-review круг 3): REQ-006 `parent` приведён к `<I-NNN|none>` (design/tasks
> уже так, R3-006); добавлен REQ-013 + сценарий 16 (наблюдаемый `unconfirmed_ice=` + флип
> `ice_confirmed` оркестратором, AGR-021 — приземление UNFIXED:D-14-ICE-SCHEMA). Максимум локального
> REQ проверен вручную (был REQ-012 → новый REQ-013; баг `mb-req-next-id.sh --spec` I-130 обойдён).
>
> EARS: Ubiquitous `THE SYSTEM SHALL` · Event `WHEN …` · State `WHILE …` · Optional `WHERE …` · Unwanted `IF … THEN …`

## Requirements (EARS)

### Requirement 1: Роадмеп — ICE, проценты, группы

**User Story:** As a project owner, I want the roadmap ordered by ICE with script-computed progress and group sections, so that it reads as the single deterministic master plan.

#### Acceptance Criteria

- **REQ-001** (ubiquitous): The roadmap-sync script shall order the Next queue by an ICE score the script itself computes as `impact × confidence × ease` from the frontmatter components (each `1..10`, per design.md C1), honoring an explicit `pin: N` override, and shall preserve today's ordering byte-for-byte in any section where no item carries `ice` or `pin`. <!-- D-14 -->
- **REQ-002** (ubiquitous): The roadmap-sync script shall render per-spec and per-plan progress — percentage plus counters of stages/tasks planned, in progress and done — computed from checkbox state. <!-- D-14 -->
- **REQ-003** (event-driven): When specs share a `group:` frontmatter value, the roadmap-sync script shall render a group section with intra-group ICE order, member statuses, blockers and aggregated progress. <!-- D-31 -->
- **REQ-012** (ubiquitous): The system shall compute counters, percentages and ICE scores exclusively by script — hand-edits to generated numbers shall be flagged by the lint. <!-- D-14 -->
- **REQ-013** (event-driven): When the rendered roadmap order uses at least one valid but unconfirmed ICE (a member whose `ice_confirmed` is not `true`), the roadmap-sync script shall emit an observable `unconfirmed_ice=<slugs>` signal and shall not change the computed order because of the unconfirmed state, so that the orchestrator can escalate the priorities to the user for confirmation; a confirmation flips `ice_confirmed` to `true` in the spec frontmatter, written only by the orchestrator. <!-- D-14, AGR-021 -->

### Requirement 2: Беклог — стейт-машина и иерархия

**User Story:** As a maintainer, I want backlog items to move through a validated state machine with parent hierarchy and agent briefs, so that every task's status and ownership is deterministic.

#### Acceptance Criteria

- **REQ-005** (ubiquitous): The backlog shall implement the state machine NEW → NEEDS-INFO ⇄ TRIAGED → READY → IN-PROGRESS → DONE | WONTFIX with transitions validated by script, and every writer that changes an item's state — including the idea-promotion script — shall go through that single validated primitive. <!-- D-15 -->
- **REQ-006** (optional): Where a backlog item declares `**Parent:** <I-NNN|none>`, the system shall treat an `I-NNN` parent as a subtask relationship and render the hierarchy in listings; an absent field or `none` denotes a root. <!-- D-15 -->
- **REQ-007** (event-driven): When a backlog item moves to READY, the system shall require an agent brief that is behavioral and free of file paths and line numbers. <!-- D-20 -->
- **REQ-008** (event-driven): When a backlog item is closed as WONTFIX with a rejection, the system shall record the precedent in the `## Out of scope` section and surface it when a similar idea arrives. <!-- D-15 -->
- **REQ-009** (event-driven): When a deferred spec is registered with the `[SPEC:<group>]` prefix, the system shall parse it into the decomposed-spec registry with its group attribution — both when the record is written and when a pre-existing record is migrated. <!-- D-31 -->

### Requirement 3: Детерминизм, миграция, совместимость

**User Story:** As a user of an existing bank, I want format validation and an idempotent migration, so that the upgrade never corrupts my data and legacy entries keep working.

#### Acceptance Criteria

- **REQ-004** (ubiquitous): The system shall validate `roadmap.md`, `backlog.md` and the frontmatter that feeds them — ICE components and their `1..10` range, the user-confirmation marker, `pin` and `group` — via `mb-bank-lint.sh`, reporting violations as key=value lines. <!-- S4-A-05, D-14 -->
- **REQ-010** (event-driven): When the backlog migration script runs on a legacy backlog, the system shall create a backup and upgrade the format idempotently. <!-- S4-A-03 -->
- **REQ-011** (ubiquitous): The system shall parse legacy backlog entries without the new fields unchanged, and shall report a legacy state token as a migration hint rather than an error. <!-- D-26 -->

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: ICE sorting with pin
**Covers:** REQ-001

- GIVEN три плана с `ice: {impact: 8, confidence: 9, ease: 7}` (504), `{8, 9, 6}` (432), `{10, 8, 5}` (400), и у третьего `pin: 1`
- WHEN mb-roadmap-sync запускается
- THEN Next: пин первым, затем 504, 432; вне fences файл byte-identical
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: Hand-edited percentage is corrected
**Covers:** REQ-002, REQ-012

- GIVEN в Group-секции кто-то вручную поменял 43% на 90%
- WHEN mb-bank-lint запускается
- THEN расхождение с чекбоксами зафлаговано (`progress_mismatch`), sync восстанавливает вычисленное значение
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: Invalid state transition rejected
**Covers:** REQ-005

- GIVEN I-042 в статусе DONE
- WHEN запрошен переход DONE → NEW
- THEN скрипт отказывает с exit 1 и подсказкой допустимых переходов
<!-- /mb-scenario:3 -->

<!-- mb-scenario:4 -->
### Scenario: READY without a brief refused
**Covers:** REQ-007

- GIVEN I-050 переводится TRIAGED → READY без agent-brief блока
- WHEN переход применяется
- THEN отказ: READY требует брифа (behavioral, без путей файлов)
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: Similar idea after WONTFIX
**Covers:** REQ-008

- GIVEN `## Out of scope` содержит прецедент «телеметрия по умолчанию»
- WHEN `/mb idea "включить телеметрию всем"` вызывается
- THEN прецедент показан пользователю до создания I-NNN
<!-- /mb-scenario:5 -->

<!-- mb-scenario:6 -->
### Scenario: Legacy backlog migration
**Covers:** REQ-010, REQ-011

- GIVEN backlog.md со статусами NEW/TRIAGED/PLANNED
- WHEN мигратор запускается дважды
- THEN первый прогон: backup + маппинг статусов; второй: `actions_pending=0`, файл не изменён
<!-- /mb-scenario:6 -->

<!-- mb-scenario:7 -->
### Scenario: Group render
**Covers:** REQ-003

- GIVEN три спеки с `group: sdd-vision-pipeline`, разными ICE-компонентами и одна с `blocked_by: [svp-sdd-core]`
- WHEN mb-roadmap-sync запускается
- THEN внутри fences появляется `## Group: sdd-vision-pipeline` с членами в ICE-порядке (score = I×C×E), статусом каждого, блокером у зависимого члена и агрегированным процентом группы
<!-- /mb-scenario:7 -->

<!-- mb-scenario:8 -->
### Scenario: Structural lint
**Covers:** REQ-004

- GIVEN в generated Group-секции roadmap.md процент вручную изменён, а `specs/foo/requirements.md` не содержит `ice:`
- WHEN mb-bank-lint запускается на `all`
- THEN вывод содержит `severity=error code=progress_mismatch ...` и `severity=warning code=no_ice ...`; exit 1 (есть error); файлы банка не изменены
<!-- /mb-scenario:8 -->

<!-- mb-scenario:9 -->
### Scenario: Parent hierarchy
**Covers:** REQ-006

- GIVEN I-060 (`**Parent:** none`) и I-061 (`**Parent:** I-060`)
- WHEN `mb-backlog-state.sh list --tree` запускается
- THEN I-060 печатается раньше I-061, строки несут `depth=0` и `depth=1` соответственно; несуществующий parent завершает команду exit 1 с пустым stdout
<!-- /mb-scenario:9 -->

<!-- mb-scenario:10 -->
### Scenario: SPEC registry migration
**Covers:** REQ-009

- GIVEN backlog.md содержит `### I-070 — [SPEC:sdd-vision-pipeline] svp-example [MED, NEW, 2026-07-10]`
- WHEN мигратор запускается с `--apply`
- THEN запись становится `### I-070 — svp-example [MED, NEW, 2026-07-10]` с добавленными `**Type:** SPEC`, `**Group:** sdd-vision-pipeline`, `**Parent:** none`, `**Spec:** svp-example`; ID и дата не изменились
<!-- /mb-scenario:10 -->

<!-- mb-scenario:11 -->
### Scenario: Legacy order preserved without ice or pin
**Covers:** REQ-001

- GIVEN три плана A, B, C в файловом порядке A/B/C, где `A.depends_on = [C]`, и ни один не несёт `ice`/`pin`
- WHEN mb-roadmap-sync запускается
- THEN Next содержит ровно сегодняшний DFS-порядок `C, A, B` (не `B, C, A`) и весь autosync-блок byte-identical снимку до правок
<!-- /mb-scenario:11 -->

<!-- mb-scenario:12 -->
### Scenario: ICE components scored and confirmation surfaced
**Covers:** REQ-001, REQ-004

- GIVEN спека с `ice: {impact: 8, confidence: 9, ease: 6}` без `ice_confirmed`, спека с `ice: 432` (легаси plain-int) и спека с `ice: {impact: 11, confidence: 9, ease: 6}`
- WHEN mb-roadmap-sync и mb-bank-lint запускаются
- THEN первая получает score 432 и метку `(unconfirmed)` + warning `ice_unconfirmed`; вторая и третья дают `severity=error code=invalid_ice` и уходят в no-ice tail; sync не падает ни на одной
<!-- /mb-scenario:12 -->

<!-- mb-scenario:13 -->
### Scenario: Next id is global across the bank
**Covers:** NFR-003

- GIVEN `backlog.md` с максимумом I-074, а `progress.md` содержит запись I-075
- WHEN `/mb idea "новая идея"` создаёт запись
- THEN выдан I-076 (не I-075) — максимум берётся по всем источникам аллокации; два параллельных вызова получают разные ID
<!-- /mb-scenario:13 -->

<!-- mb-scenario:14 -->
### Scenario: Promote requires READY and never writes PLANNED
**Covers:** REQ-005, REQ-011

- GIVEN I-080 в состоянии NEW и I-081 в состоянии READY с валидным `**Brief:**`
- WHEN `mb-idea-promote.sh` вызывается для обоих
- THEN I-080 — exit 2 с ремедиацией до READY, план не создан, файл не изменён; I-081 — план создан и состояние стало IN-PROGRESS; токен `PLANNED` не появляется ни в одном случае
<!-- /mb-scenario:14 -->

<!-- mb-scenario:15 -->
### Scenario: Typed SPEC record written at creation
**Covers:** REQ-009

- GIVEN беклог без записи о спеке
- WHEN `mb-idea.sh "[SPEC:sdd-vision-pipeline] svp-example"` вызывается (call-site S2)
- THEN создана запись `### I-NNN — svp-example [MED, NEW, <today>]` с `**Type:** SPEC`, `**Group:** sdd-vision-pipeline`, `**Parent:** none`, `**Spec:** svp-example` сразу, без прогона мигратора; stdout — ровно `I-NNN`; similarity-гейт к ней не применялся
<!-- /mb-scenario:15 -->

<!-- mb-scenario:16 -->
### Scenario: Unconfirmed ICE surfaced and order unchanged
**Covers:** REQ-013

- GIVEN спека с валидным `ice: {impact: 9, confidence: 8, ease: 7}` и `ice_confirmed: false`, и спека с тем же валидным ICE и `ice_confirmed: true`
- WHEN mb-roadmap-sync запускается, а затем оркестратор флипает `ice_confirmed` первой на `true` и запускает снова
- THEN первый прогон печатает в stderr `unconfirmed_ice=<slug первой спеки>` и порядок посчитан по score без изменения из-за неподтверждённости; второй прогон не печатает `unconfirmed_ice=` и снимает `(unconfirmed)`/`ice_unconfirmed` с этой спеки
<!-- /mb-scenario:16 -->
