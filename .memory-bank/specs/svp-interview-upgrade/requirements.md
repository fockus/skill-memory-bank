---
topic: svp-interview-upgrade
group: sdd-vision-pipeline
ice: {impact: 8, confidence: 9, ease: 7}
ice_confirmed: true
blocked_by: []
covers_umbrella: [REQ-004, REQ-010, REQ-011, REQ-012, REQ-013, REQ-014, REQ-015, REQ-033, REQ-034, REQ-040, REQ-054]
status: ready
---

# Requirements: svp-interview-upgrade

> Spec triple — see also: design.md, tasks.md.
> Слайс S1 группы `sdd-vision-pipeline` (ICE 504). Контекст: `context/svp-interview-upgrade.md`;
> транскрипты: `context/svp-interview-upgrade-interview.md` (слайс) + `context/sdd-vision-pipeline-interview.md` (родитель).
> REQ-неймспейс слайс-локальный; мапинг на umbrella — в комментариях бюллетов.
> Ревизия 2 (2026-07-17): closed spec-review SVP-IU-001…010 — все REQ покрыты сценарием, добавлены
> REQ-020 (fast-to-code bypass), REQ-021 (defer-or-MVP alternative), REQ-022 (partial batch round).
> Ревизия 3 (2026-07-17): closed круг 2 (SVP-IU-002/003/005, R2-001…003) + смысловая находка
> D-18-FACT-FINDING — добавлены REQ-055 (параллельный fact-finding во frontier-раунде) и REQ-056
> (честная деградация в последовательный fact-finding), сценарии §19/§20. Прочие правки — в
> design.md (C4 грамматика транскрипта, C5 диспетчер policy, C9 prompt-harness, C10 glossary в
> mb-context.sh, red-условия) и tasks.md (парные mb-task маркеры, Scope T5, бюджеты).
> Ревизия 4 (2026-07-18, круг 3): **critical R3-001** — REQ-006/007 переписаны: secret-scan
> транскрипта сканирует СЫРОЙ текст включая `<private>`, находка блокирует публикацию в git до
> удаления/необратимой редакции; `<private>` = только index/search-редакция, не разрешение писать
> секрет в git (rules/RULES.md caveat). Прочее — в design.md (C1 near-формула + error-контракты
> R3-002/003, C4 строгая грамматика answer/rejected + `--legacy-live-fixture` SVP-IU-005, C11/C12
> детерминированные writer-helper'ы SVP-IU-002) и tasks.md; `ice_confirmed: true` (R3-004 —
> транскрипт+roadmap подтверждают 504). Текст REQ-001…056 (кроме 006/007) не менялся.
>
> EARS acceptance criteria (uppercase keywords, REQ-ID bullets):
> - Ubiquitous:        `THE SYSTEM SHALL <response>`
> - Event-driven:      `WHEN <trigger> THE SYSTEM SHALL <response>`
> - State-driven:      `WHILE <state> THE SYSTEM SHALL <response>`
> - Optional feature:  `WHERE <feature> THE SYSTEM SHALL <response>`
> - Unwanted:          `IF <trigger> THEN THE SYSTEM SHALL <response>`

## Requirements (EARS)

### Requirement 1: План интервью и возврат к белым пятнам

**User Story:** As a user briefing the agent, I want the interview to start from a written plan and refuse to generate artifacts while planned topics stay open, so that no white spot is silently lost when discussion drifts.

#### Acceptance Criteria

- **REQ-001** (event-driven): When an interview starts, the system shall write an interview plan file to `<bank>/tmp/interview-plan-<topic>.md` listing the topics to close and the inherited decisions not to re-ask. <!-- umbrella REQ-012, S1-D-03 -->
- **REQ-002** (unwanted): If any interview plan item remains unclosed before artifact generation, then the system shall return to it and ask the missing questions before generating. <!-- umbrella REQ-013 -->
- **REQ-019** (event-driven): When an interview is cancelled mid-way, the system shall keep the context file at status draft and preserve the interview plan file for resume. <!-- S1-D-03 -->

### Requirement 2: Финальный гейт и batch-режим

**User Story:** As a user, I want a guaranteed final "anything to add?" moment and an optional batch mode that researches and asks the whole question frontier per round, so that I can always contribute late additions and get evidence-backed recommendations without a slow one-by-one interview.

#### Acceptance Criteria

- **REQ-003** (event-driven): When the interview plan has no remaining open topics, the system shall ask the user a final "anything to add?" question before generating artifacts. <!-- umbrella REQ-010, D-09 -->
- **REQ-004** (unwanted): If the user adds new material at the final gate, then the system shall reopen the discussion iteration and update the decision ledger before generation. <!-- umbrella REQ-011 -->
- **REQ-015** (optional): Where batch mode is requested, the system shall ask the whole current frontier of unblocked questions in one numbered round with a recommendation per question. <!-- umbrella REQ-040, S1-D-05 -->
- **REQ-016** (unwanted): If the host lacks an interactive question tool, then the system shall degrade the batch round to numbered plain text. <!-- S1-D-05 -->
- **REQ-022** (unwanted): If a batch round is only partially answered, then every unanswered question shall remain unchecked in the interview plan and return in the next frontier. <!-- S1-D-05 -->
- **REQ-055** (optional): Where batch mode is requested on a host providing subagent dispatch, the system shall fact-find the frontier questions in parallel subagents before asking the round and shall ground each per-question recommendation in a cited finding. <!-- umbrella REQ-040, D-18, S1-D-07 -->
- **REQ-056** (unwanted): If the host lacks subagent dispatch, then the system shall run the same frontier fact-finding sequentially in the main agent and shall report the degradation to the user. <!-- D-18, S1-D-07, AGR-013 -->

### Requirement 3: Размерный триаж и декомпозиция в группы

**User Story:** As a user with a large idea, I want the interview to estimate topic size by a fixed rubric and offer grouped decomposition when it exceeds the budget, so that every resulting spec stays inside the ~1M token budget.

#### Acceptance Criteria

- **REQ-008** (event-driven): When Phase 1 of the interview completes, the system shall estimate the topic size in tokens using the fixed rubric and record the estimate with its breakdown in the context frontmatter. <!-- S1-D-01 -->
- **REQ-009** (unwanted): If the estimated size exceeds the spec budget (~1M tokens), then the system shall recommend decomposition into named grouped specs — stating that each accepted child receives its own follow-up interview — and let the user decline the recommendation. <!-- umbrella REQ-014, D-10 -->
- **REQ-010** (event-driven): When the user accepts decomposition, the system shall register the deferred specs in the decomposed-spec registry with the group name and continue the interview on the selected spec. <!-- umbrella REQ-015/041, D-31 -->
- **REQ-021** (unwanted): If an interview branch is estimated at spec size, then the system shall offer either deferring it as a child spec or simplifying it to an MVP inside the current topic before continuing. <!-- umbrella D-12 -->
- **REQ-011** (ubiquitous): The system shall validate the presence and format of the size estimate by script and compare it against the configured budgets. <!-- S1-D-01, D-13 -->

### Requirement 4: Транскрипт и приватность

**User Story:** As a spec planner or reviewer, I want the full curated interview transcript preserved in git with secrets protected, so that downstream stages see the real discussion context safely.

#### Acceptance Criteria

- **REQ-005** (event-driven): When the interview completes, the system shall save a curated transcript to `context/<topic>-interview.md` preserving the user's answers near-verbatim, including rejected alternatives. <!-- umbrella REQ-034, D-29 -->
- **REQ-006** (ubiquitous): The transcript shall honor `<private>` markers — private fragments excluded from the index and redacted in search output; this index/search redaction is orthogonal to the secret-scan gate (REQ-007) and does not relax it. <!-- S1-D-02, R3-001 -->
- **REQ-007** (unwanted): If the secret-scan flags a credential in a transcript candidate — scanning the raw text including content inside `<private>…</private>` — then the system shall block publication to the git-tracked transcript until the flagged credential is removed or irreversibly redacted; a `<private>` marker shall never suppress a scanner finding nor authorize writing a credential into git. <!-- S1-D-02, R3-001: rules/RULES.md caveat — <private> не защищает git diff -->

### Requirement 5: Глоссарий

**User Story:** As a project owner, I want interview-resolved terms recorded in a single glossary and later conflicts challenged, so that terminology stays consistent across specs.

#### Acceptance Criteria

- **REQ-017** (event-driven): When a term is resolved during the interview, the system shall update `glossary.md` inline. <!-- umbrella REQ-033, S1-D-06 -->
- **REQ-018** (unwanted): If a later statement conflicts with an existing glossary term, then the system shall challenge the conflict before recording the requirement. <!-- S1-D-06 -->

### Requirement 6: Self-interview и assumptions

**User Story:** As a user who wants full automation, I want the agent to run the interview against itself from my brief with every self-answered decision tracked as an assumption, so that speed never hides what was assumed on my behalf.

#### Acceptance Criteria

- **REQ-012** (optional): Where self-interview mode is requested with a brief, the system shall answer the interview questions itself and record every self-answered decision in an Assumptions block. <!-- umbrella REQ-004, D-04 -->
- **REQ-013** (state-driven): While in interactive self-interview, the system shall present the assumptions batch for user confirmation before generation. <!-- S1-D-04 -->
- **REQ-014** (state-driven): While in auto mode, the system shall record assumptions without blocking and shall offer their review after completion. <!-- S1-D-04 -->

### Requirement 7: Fast-to-code bypass

**User Story:** As a user in a hurry, I want an explicit escape hatch that skips the remaining interview and decomposition steps while quality mode stays the default, so that I can trade rigor for speed only when I say so.

#### Acceptance Criteria

- **REQ-020** (optional): Where the user explicitly selects fast-to-code mode, the system shall allow bypassing the remaining interview and decomposition steps after recording the choice and its quality trade-off in the context frontmatter, with quality mode remaining the default. <!-- umbrella REQ-054, D-11 -->

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: Interview plan returns to an unclosed theme
**Covers:** REQ-002

- GIVEN интервью с планом из 5 тем, где тема «edge cases» осталась ⬜
- WHEN агент готов генерировать context-файл
- THEN генерация не начинается, агент возвращается к теме «edge cases» и задаёт недостающие вопросы
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: Final gate catches a late addition
**Covers:** REQ-003, REQ-004

- GIVEN все темы плана закрыты и задан вопрос «есть ли что добавить?»
- WHEN пользователь описывает новую фичу
- THEN открывается новая итерация обсуждения, леджер пополняется, гейт повторяется до явного «нет»
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: Estimate exceeds the budget
**Covers:** REQ-008, REQ-009, REQ-010

- GIVEN Phase 1 завершена и рубрика дала оценку 2.4M токенов с разбивкой
- WHEN агент сообщает оценку
- THEN пользователю рекомендовано разбиение на именованные child-спеки с оговоркой, что каждая принятая ветка получит своё интервью, и правом отказа; при согласии отложенные спеки регистрируются в реестре с именем группы
<!-- /mb-scenario:3 -->

<!-- mb-scenario:4 -->
### Scenario: Secret in the transcript
**Covers:** REQ-007

- GIVEN в ответе пользователя есть строка, похожая на API-ключ (в т.ч. внутри `<private>…</private>`)
- WHEN агент пишет транскрипт-кандидат
- THEN secret-scan сканирует сырой текст включая содержимое `<private>`; находка блокирует публикацию в git-tracked файл до удаления или необратимой редакции credential; одна лишь пометка `<private>` блокировку НЕ снимает, credential в git не попадает
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: Glossary conflict
**Covers:** REQ-018

- GIVEN glossary.md определяет «слайс — child-спека группы»
- WHEN пользователь называет слайсом этап плана
- THEN агент указывает на конфликт и просит уточнить термин до записи требования
<!-- /mb-scenario:5 -->

<!-- mb-scenario:6 -->
### Scenario: Self-interview marks assumptions
**Covers:** REQ-012, REQ-013

- GIVEN пользователь дал бриф и попросил заполнить спеку самостоятельно (интерактивный режим)
- WHEN агент сам ответил на 7 вопросов интервью
- THEN перед генерацией пользователю предъявлен пакет из 7 assumptions на подтверждение
<!-- /mb-scenario:6 -->

<!-- mb-scenario:7 -->
### Scenario: Interview start writes an interview plan file
**Covers:** REQ-001

- GIVEN интервью запускается по теме «foo» с 5 обсуждаемыми темами и 2 унаследованными родительскими решениями
- WHEN агент начинает интервью
- THEN `<bank>/tmp/interview-plan-foo.md` создаётся с секцией «Inherited decisions» (2 записи) и секцией «Topics» (5 строк `- [ ]`)
<!-- /mb-scenario:7 -->

<!-- mb-scenario:8 -->
### Scenario: Interview completion saves curated transcript
**Covers:** REQ-005

- GIVEN интервью завершено: все темы плана закрыты и финальный гейт пройден явным «нет»
- WHEN агент финализирует артефакты
- THEN `context/<topic>-interview.md` создаётся с ответами близко к дословным и явно перечисленными отклонёнными альтернативами
<!-- /mb-scenario:8 -->

<!-- mb-scenario:9 -->
### Scenario: Private markers stay redacted in transcript
**Covers:** REQ-006

- GIVEN сохранённый транскрипт содержит фрагмент внутри `<private>...</private>`
- WHEN индекс/search обрабатывают файл транскрипта
- THEN приватный фрагмент исключён из `index.json` и редактирован в выдаче `/mb search`
<!-- /mb-scenario:9 -->

<!-- mb-scenario:10 -->
### Scenario: Estimate check validates presence and format against budgets
**Covers:** REQ-011

- GIVEN context-файл, у которого frontmatter `estimated_tokens` то заполнен корректно, то отсутствует, то содержит несогласованный `subtotal`
- WHEN запускается `scripts/mb-estimate-check.sh <context-file>`
- THEN скрипт детерминированно возвращает `estimate=ok|near|over|missing|malformed` с соответствующим exit-кодом, сверяясь с настроенными бюджетами
<!-- /mb-scenario:10 -->

<!-- mb-scenario:11 -->
### Scenario: Auto mode records assumptions without blocking
**Covers:** REQ-014

- GIVEN `--self "<brief>" --auto` запущен и интервью содержит 5 self-answered решений
- WHEN агент завершает генерацию в auto-режиме
- THEN все 5 assumptions записаны в блок без промежуточного подтверждения, а обзор assumptions предложен пользователю только после завершения
<!-- /mb-scenario:11 -->

<!-- mb-scenario:12 -->
### Scenario: Batch mode asks the full frontier in one round
**Covers:** REQ-015

- GIVEN запрошен `--batch`, текущий фронтир содержит 6 разблокированных вопросов
- WHEN агент формирует раунд
- THEN все 6 вопросов заданы одним нумерованным раундом с рекомендацией на каждый (несколько AskUserQuestion-вызовов при >4 вопросах на хостах с этим тулом)
<!-- /mb-scenario:12 -->

<!-- mb-scenario:13 -->
### Scenario: Batch round degrades to plain text without interactive tool
**Covers:** REQ-016

- GIVEN запрошен `--batch` на хосте без интерактивного question-тула
- WHEN агент формирует раунд
- THEN раунд деградирует в нумерованный plain-text список вопросов вместо интерактивного UI
<!-- /mb-scenario:13 -->

<!-- mb-scenario:14 -->
### Scenario: Resolved term updates the glossary inline
**Covers:** REQ-017

- GIVEN пользователь и агент согласовали значение термина «слайс» во время интервью
- WHEN термин разрешён
- THEN `.memory-bank/glossary.md` обновляется немедленно строкой «слайс — определение»
<!-- /mb-scenario:14 -->

<!-- mb-scenario:15 -->
### Scenario: Cancelled interview keeps draft status and plan for resume
**Covers:** REQ-019

- GIVEN интервью прервано после записи interview-plan файла и частичного context-файла
- WHEN пользователь отменяет сессию
- THEN context-файл остаётся `status: draft`, файл плана сохраняется в `<bank>/tmp/` для последующего resume
<!-- /mb-scenario:15 -->

<!-- mb-scenario:16 -->
### Scenario: Fast-to-code bypass skips remaining interview steps
**Covers:** REQ-020

- GIVEN пользователь явно выбирает fast-to-code режим, когда quality-режим уже предложен по умолчанию
- WHEN выбор зафиксирован
- THEN агент пропускает оставшиеся шаги интервью и декомпозиции, записав выбор и quality trade-off в context frontmatter, а quality-режим остаётся дефолтом для последующих интервью
<!-- /mb-scenario:16 -->

<!-- mb-scenario:17 -->
### Scenario: Spec-sized branch offers defer-or-simplify choice
**Covers:** REQ-021

- GIVEN ветка обсуждения внутри текущей темы сама разрослась до размера отдельной спеки
- WHEN агент обнаруживает это до завершения текущей секции интервью
- THEN пользователю предложены два варианта — отложить ветку как отдельную child-спеку или упростить её до MVP в текущей теме — и интервью продолжается по выбору
<!-- /mb-scenario:17 -->

<!-- mb-scenario:18 -->
### Scenario: Partially answered batch round returns unanswered questions to frontier
**Covers:** REQ-022

- GIVEN раунд batch-режима из 5 вопросов, пользователь ответил только на первые 2
- WHEN раунд сохраняется
- THEN первые 2 темы закрываются `- [x]`, оставшиеся 3 остаются `- [ ]` в interview-plan и формируют следующий фронтир
<!-- /mb-scenario:18 -->

<!-- mb-scenario:19 -->
### Scenario: Parallel fact-finding grounds the frontier round
**Covers:** REQ-055

- GIVEN запрошен `--batch` на хосте с диспатчем сабагентов, фронтир содержит 4 разблокированных вопроса
- WHEN агент готовит раунд
- THEN на каждый вопрос отработал свой параллельный fact-finding сабагент, и рекомендация к каждому вопросу раунда несёт ссылку на найденный факт (`file:line` или URL), а не догадку
<!-- /mb-scenario:19 -->

<!-- mb-scenario:20 -->
### Scenario: Fact-finding degrades honestly without subagent dispatch
**Covers:** REQ-056

- GIVEN запрошен `--batch` на хосте, чей манифест объявляет `platform_limited: ["subagents"]`
- WHEN агент готовит раунд
- THEN тот же fact-finding выполняется последовательно основным агентом, пользователю сообщается о деградации одной строкой, и ни один вопрос фронтира не остаётся без собранного факта
<!-- /mb-scenario:20 -->
