---
topic: svp-adapt-escalation
group: sdd-vision-pipeline
ice: {impact: 7, confidence: 7, ease: 6}
ice_confirmed: false
blocked_by: [svp-sdd-core, svp-parallel-engine, svp-roadmap-backlog-db]
covers_umbrella: [REQ-030, REQ-031, REQ-032]
status: ready
---

# Requirements: svp-adapt-escalation

> Spec triple — see also: design.md, tasks.md.
> Слайс S5 группы `sdd-vision-pipeline` (ICE 294). Зависимости **жёсткие**: `svp-sdd-core` (S2 —
> tasks.md v2: Eval/Budget/Scope-грамматика) и `svp-parallel-engine` (S3 — Scope-вердикт
> `mb-work-scope-check.sh`, S3-C3). Без S3 scope-гард REQ-002 нереализуем: слайс не стартует,
> частичного режима нет.
> Ревизия 3 (2026-07-17): закрыты PARTIAL-находки круга 2 — схема журнала эскалаций (SVP-AE-007),
> два исхода `replan` (SVP-AE-008), поведенческий verify-гейт стаба (SVP-AE-009A), беклог по
> фактическому контракту S4-C3 (SVP-AE-009B), граница с локальными hard stop'ами S8 (R2-001/X8-01).
> Добавлены сценарии 9–10; REQ-ID не перенумерованы.
> Контекст: `context/svp-adapt-escalation.md`; транскрипты: слайсовый + родительский.
>
> EARS: Ubiquitous `THE SYSTEM SHALL` · Event `WHEN …` · State `WHILE …` · Optional `WHERE …` · Unwanted `IF … THEN …`

## Requirements (EARS)

### Requirement 1: Триггеры ADaPT

**User Story:** As an operator, I want both a conscious agent signal and deterministic guards to detect oversized tasks, so that escalation fires early (signal) and reliably (guards).

#### Acceptance Criteria

- **REQ-001** (event-driven): When an implementer report contains a `complexity_escalation` block, the system shall trigger the ADaPT fork. <!-- S5-A-02 -->
- **REQ-002** (event-driven): When a deterministic guard fires — task token budget exceeded, declared-scope violation, eval not green after max cycles, or a verify/review/judge loop threshold exceeded — the system shall trigger the ADaPT fork. <!-- D-16 -->
- **REQ-003** (ubiquitous): The loop thresholds shall default to verify 3, review 3, judge 2 and shall be configurable via pipeline.yaml. <!-- S5-A-01 -->

### Requirement 2: Развилка по режиму

**User Story:** As a user (including a vibecoder), I want auto mode to stub-and-continue and interactive mode to give me four clear choices, so that work never stalls and never hides problems.

#### Acceptance Criteria

- **REQ-004** (state-driven): While in autonomous mode, on an ADaPT trigger the system shall implement a stub behind a feature flag with a docstring, register a backlog item for the deferred work and continue execution. <!-- S5-A-03 -->
- **REQ-005** (state-driven): While in HITL mode, on an ADaPT trigger the system shall offer the choices: continue anyway, simplify, replan via decomposition or requirement change, or skip the step. <!-- D-16 -->
- **REQ-006** (event-driven): When the replan choice is decomposition, the system shall route the deferred work into a new spec through the decomposed-spec registry with its own interview (or self-interview in autonomous mode). <!-- D-10 -->

### Requirement 3: Честность и телеметрия

**User Story:** As a project owner, I want every escalation logged and reported, so that nothing is silently swallowed and thresholds can be calibrated from data.

#### Acceptance Criteria

- **REQ-007** (ubiquitous): The system shall log every escalation as an `opened` JSONL record at trigger time and its resolution as a matching `resolved` JSONL record, correlated by `escalation_id`. <!-- S5-A-04, умбрелла §Interfaces 3 -->
- **REQ-008** (ubiquitous): The system shall report every escalation and stub to the user in the run summary — an escalation shall never be silently swallowed. <!-- D-33 -->
- **REQ-009** (unwanted): If a stub is created without a feature flag or without a backlog item, then verification shall fail for that task. <!-- no-placeholders, rules/RULES.md § Staged stubs -->

### Requirement 4: Каскад-стоп

**User Story:** As a project owner, I want a run to stop after repeated escalations, so that a mis-sized spec is revised instead of being ground through task by task.

#### Acceptance Criteria

- **REQ-010** (unwanted): If `cascade_stop` consecutive ADaPT escalations occur within one run, then the system shall stop before dispatching the next item and report a recommendation to revise the whole spec. <!-- D-35 -->

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: Agent escalation signal
**Covers:** REQ-001

- GIVEN имплементер понял, что задача требует новой подсистемы
- WHEN его отчёт содержит complexity_escalation с оценкой 300k
- THEN оркестратор открывает развилку до следующего цикла, событие opened в логе
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: Cycle guard fires
**Covers:** REQ-002, REQ-003

- GIVEN verify падает третий раз подряд на одной задаче (`verify_fail` = 3 в work-state)
- WHEN порог `escalation.thresholds.verify` = 3 достигнут (count >= threshold)
- THEN развилка открыта, в логе `triggers` содержит `verify_loops`
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: Autonomous mode stubs and continues
**Covers:** REQ-004, REQ-009

- GIVEN autonomous-режим и триггер на задаче 4
- WHEN развилка срабатывает
- THEN код за feature-флагом с docstring-маркером `MB-ADAPT-STUB backlog=I-NNN flag=<NAME> eval=<path>`, беклог-элемент доведён оркестратором до READY по цепочке S4-C3 (`mb-idea.sh` → `NEEDS-INFO` → `annotate --brief` → `TRIAGED` → `READY`) ДО правки кода, исполнение продолжено; verify падает, если флага, драйвера или беклог-ссылки нет
<!-- /mb-scenario:3 -->

<!-- mb-scenario:4 -->
### Scenario: HITL four options
**Covers:** REQ-005

- GIVEN HITL-режим и триггер
- WHEN пользователю показана развилка
- THEN варианты: continue_anyway / simplify / replan (декомпозиция или смена требований) / skip; выбор пишется событием resolved
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: Replan decomposition registers a child spec
**Covers:** REQ-006

- GIVEN на развилке выбран replan с декомпозицией
- WHEN решение подтверждено
- THEN новая child-спека зарегистрирована через реестр decomposed-spec и получает своё интервью (self-interview в autonomous), текущий item остаётся pending без переворота чекбокса
<!-- /mb-scenario:5 -->

<!-- mb-scenario:6 -->
### Scenario: Escalation telemetry is two phase
**Covers:** REQ-007

- GIVEN развилка открыта и затем разрешена
- WHEN resolution зафиксирован
- THEN в `tmp/escalations.jsonl` ровно две валидные строки схем C1.0 с одним `escalation_id`: `opened` с `ts`/`seq`/triggers и `resolved` с `ts`/`seq`/resolution; свёртка по id даёт последнее событие; строка с неизвестным ключом делает журнал невалидным (exit 1 без append)
<!-- /mb-scenario:6 -->

<!-- mb-scenario:7 -->
### Scenario: Nothing is silenced
**Covers:** REQ-008

- GIVEN autonomous-прогон завершился с двумя стабами
- WHEN печатается финальный отчёт
- THEN оба стаба и их беклог-элементы перечислены явно
<!-- /mb-scenario:7 -->

<!-- mb-scenario:8 -->
### Scenario: Escalation cascade stops the run
**Covers:** REQ-010

- GIVEN третья подряд эскалация в одном прогоне (`cascade_stop` = 3), ни один item между ними не закрылся
- WHEN открывается третья развилка
- THEN прогон останавливается до диспатча следующего item и печатает рекомендацию пересмотреть спеку целиком (D-35-путь)
<!-- /mb-scenario:8 -->

<!-- mb-scenario:9 -->
### Scenario: Replan requirement change blocks the rerun until requirements move
**Covers:** REQ-005

- GIVEN на развилке выбран replan с видом `requirement_change`, событие `resolved` записало `requirements_sha256` текущего `requirements.md`
- WHEN оркестратор пытается снова диспатчить тот же item, не изменив `requirements.md`
- THEN `replan-gate` отказывает с `code=requirements_unchanged` (exit 1), item остаётся pending, child-спека не создавалась, отказ попадает в summary; после фактической правки требований хэш расходится и тот же гейт допускает прогон
<!-- /mb-scenario:9 -->

<!-- mb-scenario:10 -->
### Scenario: Stub gate rejects a default-on flag
**Covers:** REQ-009

- GIVEN стаб с корректным маркером, существующим `I-NNN` и драйвером `eval=<path>`, но флаг включён по умолчанию
- WHEN verify-гейт запускает драйвер без переменной флага
- THEN драйвер печатает `MB-ADAPT-STUB-PATH: staged` вместо `baseline`, гейт даёт violation `flag_default_on` и exit 1 — задача FAIL (неограждённый продакшн-код за стаб не принимается)
<!-- /mb-scenario:10 -->
