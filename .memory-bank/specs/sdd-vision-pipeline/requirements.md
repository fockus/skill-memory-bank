# Requirements: sdd-vision-pipeline

> Spec triple — see also: design.md, tasks.md.
> Umbrella-спека группы `sdd-vision-pipeline` (D-31): child-слайсы создаются JIT со своими короткими интервью.
> Источники: `context/sdd-vision-pipeline.md` (D-01…D-35), транскрипт `context/sdd-vision-pipeline-interview.md`,
> гэп-анализ `reports/2026-07-17_research_mattpocock-skills-vs-mb-pipeline.md`.
>
> Ревизия 3 (2026-07-17): закрыты находки круга 2 (SVP-008, R2-001…R2-011) + смысловой аудит —
> REQ-009 (D-17: один seam предпочтителен), REQ-043 (D-32: group ИЛИ большой target),
> REQ-049 (AGR-018: ровно одна контрактная задача перед всеми implementation-задачами),
> сценарий REQ-038 (единственный неделегированный REQ).
>
> EARS acceptance criteria (uppercase keywords, REQ-ID bullets):
> - Ubiquitous:        `THE SYSTEM SHALL <response>`
> - Event-driven:      `WHEN <trigger> THE SYSTEM SHALL <response>`
> - State-driven:      `WHILE <state> THE SYSTEM SHALL <response>`
> - Optional feature:  `WHERE <feature> THE SYSTEM SHALL <response>`
> - Unwanted:          `IF <trigger> THEN THE SYSTEM SHALL <response>`

## Requirements (EARS)

### Requirement 1: Единый sdd-конвейер — от брифа до исполняемой спеки

**User Story:** As a developer, I want `/mb sdd <topic>` to take me from a brief to a fully generated, executable spec (requirements + design + tasks with the plan inside), so that a separate `/mb plan` step is needed only when no spec is wanted.

#### Acceptance Criteria

- **REQ-001** (event-driven): When `/mb sdd <topic>` runs without an existing `context/<topic>.md`, the system shall run the discuss interview (or self-interview in auto mode) before generating the spec triple. <!-- D-02 -->
- **REQ-002** (event-driven): When `/mb sdd` completes, the system shall generate `requirements.md`, `design.md` and `tasks.md` with full content — stages, tasks and per-task fields — rather than empty scaffolds. <!-- D-03 -->
- **REQ-003** (ubiquitous): The `tasks.md` format shall support stage grouping, `blocked_by` edges, `Scope`, `Eval` and size-budget fields per task, while remaining parseable by `mb_work_items.py`. <!-- D-03, D-26 -->
- **REQ-039** (ubiquitous): The system shall parse legacy `tasks.md` files without the new fields unchanged, requiring the new fields only for specs created by the new sdd pipeline. <!-- D-26 -->

### Requirement 2: Контракт-ферст и детерминированные эвалы

**User Story:** As a user, I want every gated requirement to be verified by code (red → green), not by an LLM's opinion, so that I can deterministically prove the implementation matches the spec while spending tokens on eval code only at work time.

#### Acceptance Criteria

- **REQ-005** (ubiquitous): The generated `design.md` shall contain a Contract section declaring interfaces and per-task Eval declarations (command name + expected red/green signal) without implementation code. <!-- D-05 -->
- **REQ-006** (event-driven): When `/mb work` starts a task with an Eval declaration, the system shall materialize the eval into executable code first, observe it fail (red) before implementation and pass (green) after implementation. <!-- D-05 -->
- **REQ-007** (state-driven): While a requirement carries a SHALL or MUST modal, the system shall require at least one GWT scenario and one Eval declaration covering it. <!-- D-06 -->
- **REQ-008** (unwanted): If a task covering a gated requirement declares `Eval: none`, then the system shall fail spec validation. <!-- D-25 -->
- **REQ-009** (event-driven): When `design.md` is generated, the system shall record the agreed test seams, preferring existing seams and the highest possible seam, and shall prefer a single seam — recording a brief rationale in `design.md` when more than one seam is agreed. <!-- D-17 -->

### Requirement 3: Качество интервью — план, финальный гейт, глоссарий, self-interview

**User Story:** As a user briefing the agent, I want the interview to follow a written plan, always ask me for final additions, keep terminology consistent, and optionally run itself from my brief, so that no white spot survives and I control the depth/speed trade-off.

#### Acceptance Criteria

- **REQ-004** (optional): Where the user requests self-interview mode with a brief, the system shall answer the interview questions itself and mark every self-answered decision as an assumption presented to the user for review. <!-- D-04 -->
- **REQ-010** (event-driven): When the interview plan has no remaining open topics, the system shall ask the user a final "anything to add?" question before generating artifacts. <!-- D-09 -->
- **REQ-011** (unwanted): If the user adds new material at the final gate, then the system shall reopen the discussion iteration and update the decision ledger before generation. <!-- D-09 -->
- **REQ-012** (event-driven): When an interview starts, the system shall write an interview plan file listing the topics and white spots to close. <!-- D-12 -->
- **REQ-013** (unwanted): If any interview plan item remains unclosed before artifact generation, then the system shall return to it and ask the missing questions before generating. <!-- D-12 -->
- **REQ-033** (event-driven): When a term is resolved during the interview, the system shall update `glossary.md` inline and challenge later uses that conflict with it. <!-- D-22 -->
- **REQ-040** (optional): Where the user requests batch interview mode, the system shall ask the whole current frontier of unblocked questions in one numbered round with a recommendation per question, grounding recommendations via parallel fact-finding subagents where the platform supports them and degrading to sequential fact-finding with an explicit `platform_limited` notice otherwise. <!-- D-18; деградация — S1 REQ-055/056 -->

### Requirement 4: Умная декомпозиция и группы спек

**User Story:** As a user with a large idea, I want oversized work split into budgeted specs grouped under one named program with its own registry and ICE ordering, so that the roadmap reads the whole effort as one unit while every piece stays session-sized.

#### Acceptance Criteria

- **REQ-014** (unwanted): If the estimated scope of a topic exceeds the spec budget (~1M tokens), then the system shall recommend decomposition into separate specs — each with its own interview — and let the user decline. <!-- D-10 -->
- **REQ-015** (event-driven): When the user accepts decomposition, the system shall register deferred specs in the decomposed-spec registry and continue the interview on the selected spec. <!-- D-10, D-15 -->
- **REQ-016** (ubiquitous): The system shall enforce size budgets — task ≤120k, stage ≤400k, spec ~1M tokens — via deterministic validation heuristics at spec-generation time. <!-- D-13 -->
- **REQ-041** (event-driven): When a topic is decomposed into multiple specs, the system shall assign every child spec to a named group, store the group in the spec frontmatter and the decomposed-spec registry, and render the group in the roadmap with intra-group ICE ordering and aggregated progress. <!-- D-31 -->
- **REQ-047** (unwanted): If the size estimate at sdd-generation time exceeds the spec budget, then the system shall stop before writing tasks and escalate to the user, recommending immediate decomposition into grouped specs with their own interviews and offering the alternatives: an MVP scope cut with the remainder registered in the backlog, a thin umbrella spec with JIT slices, or an explicit override recorded in the spec frontmatter. <!-- D-35 -->
- **REQ-048** (state-driven): While running in auto mode, on a budget excess at sdd-generation time the system shall decompose into self-interviewed slices by default and record that choice as an assumption. <!-- D-35 -->

### Requirement 5: Параллельное исполнение по DAG

**User Story:** As an operator of `/mb work`, I want to choose sequential or parallel execution at start, with the engine dispatching only safely-parallel frontier tasks to subagents, so that work speeds up without file conflicts or corrupted bank state.

#### Acceptance Criteria

- **REQ-017** (optional): Where `--parallel[=N]` is passed to `/mb work` or set as the pipeline.yaml default, the system shall dispatch frontier tasks to parallel subagents from a single orchestrator session. <!-- D-07 -->
- **REQ-018** (ubiquitous): The system shall treat as parallelizable only tasks that are both unblocked in the DAG and have pairwise-disjoint declared Scopes; conflicting tasks shall be serialized. <!-- D-07, D-08 -->
- **REQ-019** (unwanted): If the host platform lacks subagent dispatch, then the system shall fall back to sequential execution and report `platform_limited` honestly. <!-- D-07 -->
- **REQ-020** (event-driven): When a task completes in parallel mode, the system shall deterministically verify the actual diff against the declared Scope and escalate on out-of-scope changes. <!-- D-08 -->
- **REQ-021** (state-driven): While parallel execution is active, the system shall allow only the orchestrator to write to `.memory-bank/` files; task agents shall return structured reports. <!-- D-23 -->
- **REQ-022** (unwanted): If `tasks.md` contains a `blocked_by` cycle, then spec validation shall fail with the cycle path reported. <!-- D-24 -->
- **REQ-023** (event-driven): When a task is dispatched, the system shall record a claim (timestamp + session id) visible to concurrent sessions, and shall release stale claims by TTL. <!-- D-24 -->
- **REQ-042** (optional): Where a spec group is passed as the target to `/mb work`, the system shall execute the member specs of the group respecting the group DAG and the intra-group ICE order. <!-- D-32 -->
- **REQ-043** (event-driven): When `/mb work` starts on a group target, or on a single target whose size estimate exceeds the spec budget under the same deterministic size rubric as REQ-016, the system shall ask the user to choose the execution mode — sequential, or parallel via teammates, subagents, or additional sessions (worktree or coordination board) — and the intervention mode — HITL or autonomous. <!-- D-32 -->
- **REQ-044** (state-driven): While running in autonomous intervention mode, the system shall interrupt only on escalations and shall report every encountered problem instead of silently continuing. <!-- D-33 -->

### Requirement 6: Роадмеп и беклог как база данных

**User Story:** As a project owner, I want the roadmap ordered by ICE with script-computed progress and a backlog with a real state machine and subtask hierarchy, so that project state is deterministic, current and maintained by code — not only by an LLM.

#### Acceptance Criteria

- **REQ-024** (ubiquitous): The roadmap shall order the Next queue by ICE score (impact×confidence×ease from frontmatter) with an explicit pin override, computed and sorted by script. <!-- D-14 -->
- **REQ-025** (ubiquitous): The roadmap shall display per-spec and per-plan progress — percentages and counters of stages/tasks planned, in progress and done — computed deterministically from checkboxes by script. <!-- D-14 -->
- **REQ-026** (ubiquitous): The system shall validate the structure and format of `roadmap.md` and `backlog.md` by script, treating both files as machine-maintained databases. <!-- D-14 -->
- **REQ-027** (ubiquitous): The backlog shall implement the state machine NEW → NEEDS-INFO ⇄ TRIAGED → READY → IN-PROGRESS → DONE | WONTFIX with script-validated transitions and a parent field for subtask hierarchy. <!-- D-15 -->
- **REQ-028** (event-driven): When a backlog item moves to READY, the system shall require an agent brief that is behavioral and free of file paths and line numbers. <!-- D-15, D-20 -->
- **REQ-029** (event-driven): When a backlog item is closed as WONTFIX (rejected), the system shall record the rejection in the out-of-scope registry and check future ideas against it. <!-- D-15 -->

### Requirement 7: ADaPT — адаптивное репланирование

**User Story:** As a user (including a vibecoder shipping an MVP in 1–2 prompts), I want the engine to notice when a task is bigger than planned and offer clear choices — or stub-and-continue in auto mode — so that work never silently stalls or burns the budget.

#### Acceptance Criteria

- **REQ-030** (event-driven): When an implementer emits a `complexity_escalation` signal or a deterministic guard fires (task token budget exceeded, Scope violation, eval not green after max cycles, or verify/review/judge loop threshold exceeded), the system shall trigger the ADaPT fork. <!-- D-16 -->
- **REQ-031** (state-driven): While running in auto mode, on an ADaPT trigger the system shall implement a stub behind a feature flag, register a backlog item for the deferred work and continue execution. <!-- D-16 -->
- **REQ-032** (state-driven): While running interactively, on an ADaPT trigger the system shall offer the user the choices: continue anyway, simplify, replan via decomposition or requirement change, or skip the step. <!-- D-16 -->

### Requirement 8: Контекст спеки и spec-review

**User Story:** As a spec author, I want the full interview transcript preserved and the generated spec reviewed by a different model configured in the pipeline, so that planners and reviewers see the real context and the human stays the judge.

#### Acceptance Criteria

- **REQ-034** (event-driven): When the interview completes, the system shall save the full interview transcript to `context/<topic>-interview.md`, and the spec generator and spec reviewer shall read it as input context. <!-- D-29 -->
- **REQ-035** (optional): Where pipeline.yaml declares a `spec_review` model/agent, the system shall dispatch a review of the generated spec by that model before the spec is accepted, with the human (or the orchestrator in auto mode) as the judge. <!-- D-30 -->

### Requirement 9: /mb docs — LLM-вики по Карпатому

**User Story:** As a maintainer, I want `/mb docs` to incrementally document code written since the last documentation pass as a Karpathy-style LLM wiki in `docs/`, so that project documentation compounds instead of rotting.

#### Acceptance Criteria

- **REQ-036** (event-driven): When `/mb docs` runs, the system shall analyze the git diff since the last documented SHA and update the LLM wiki under the docs directory following the Karpathy rules — index.md catalog, append-only log.md, wikilinks and explicit contradiction flags. <!-- D-27 -->
- **REQ-037** (optional): Where pipeline.yaml sets a docs path, the system shall generate the wiki there instead of the default `docs/`. <!-- D-27 -->

### Requirement 10: /mb brief — формализация запроса до дискуссии

**User Story:** As a user with a raw idea and a pile of documents, I want `/mb brief` to turn them into a one-pager brief (essence, impact goal, references, JTBD solution, scenarios, constraints, UX, done-criteria) stored with its sources, so that `/mb discuss` starts from a formalized request instead of a fuzzy prompt.

#### Acceptance Criteria

- **REQ-045** (event-driven): When `/mb brief <topic>` runs with a free-form request and attached documents, the system shall analyze them, ask light clarifying questions only where the intent is unclear, and generate a one-pager brief stored together with the source documents. <!-- D-34 -->
- **REQ-046** (event-driven): When a brief is completed, the system shall offer to proceed to `/mb discuss` seeded by that brief as Phase 0 input. <!-- D-34 -->

### Requirement 11: Атрибуция референсов

**User Story:** As a project maintainer, I want the borrowed patterns credited, so that the MIT license of mattpocock/skills is honored.

#### Acceptance Criteria

- **REQ-038** (ubiquitous): The documentation shall credit mattpocock/skills (MIT) wherever its patterns are cited, including the grilling rules in `commands/discuss.md`. <!-- D-19 -->

### Requirement 12: Контрактный цикл и слои тестов

**User Story:** As a user, I want the contract and its deterministic checkers written before any business code and the integration/e2e layers written as their own steps, so that "done" is proven by code and business behaviour is actually tested.

#### Acceptance Criteria

- **REQ-049** (state-driven): While a spec enables the contract-first layer, the system shall generate exactly one contract task ordered before all implementation tasks, in which the checkers of the completion criteria are written and unit-tested against fixtures before any business code. <!-- S8-D-01, S8-D-02, AGR-018 -->
- **REQ-050** (unwanted): If a contract checker passes against the product before the covered implementation exists, then the system shall fail that contract task instead of accepting the checker. <!-- S8-D-04 -->
- **REQ-051** (state-driven): While a spec enables the integration or e2e layer, the system shall generate a dedicated task per enabled layer after the implementation tasks, covering the success scenario and the main edge scenarios. <!-- S8-D-05 -->
- **REQ-052** (event-driven): When the user declines a layer at spec-creation time, the system shall record the refusal with its reason in the spec frontmatter and omit the corresponding task. <!-- S8-D-06 -->
- **REQ-053** (ubiquitous): Every generated spec shall carry a Quality DoD referencing the resolved architecture and code-quality rule sources, delivered identically to implementer, reviewer and judge. <!-- S8-D-07, S8-D-09 -->

### Requirement 13: Fast-to-code bypass

**User Story:** As a user who wants speed over depth, I want an explicit fast-to-code mode that skips the rest of the interview and decomposition, so that velocity is a recorded decision instead of a silently degraded process.

#### Acceptance Criteria

- **REQ-054** (optional): Where the user explicitly selects fast-to-code mode, the system shall allow bypassing the remaining interview and decomposition steps after recording the choice and its quality trade-off in the context frontmatter, with quality mode remaining the default. <!-- D-11, ревью SVP-012 -->

## Scenarios

<!-- Делегирование сценариев (D-31, AGR-001): REQ-001…037 и REQ-039…054 исполняются child-слайсами -->
<!-- (`covers_umbrella` во frontmatter каждой child-спеки) — их GWT-сценарии живут ТАМ и здесь не -->
<!-- дублируются, иначе появляются два источника правды (анти-drift, D-01). Гейт -->
<!-- `mb-spec-validate.sh --require-scenarios` применяется к слайсам (8/8 green), а не к umbrella: -->
<!-- в `pipeline.yaml` он opt-in и выключен (`sdd.require_scenarios: false`), поэтому umbrella -->
<!-- проверяется базовым режимом. Единственное исключение — REQ-038 ниже: он не делегирован ни в -->
<!-- один слайс (прямая umbrella-задача T1), поэтому его сценарий обязан жить здесь. -->

<!-- mb-scenario:1 -->
### Scenario: Borrowed patterns credited with source and MIT license
**Covers:** REQ-038

- GIVEN `README.md` and `commands/discuss.md` cite patterns borrowed from mattpocock/skills (grilling rules, red-capable eval gate, DAG frontier, triage state machine, agent briefs)
- WHEN the attribution check runs over both files
- THEN each file carries a credits block naming the source repository link `https://github.com/mattpocock/skills` together with its MIT license in the same block
- AND a link or MIT mention that appears without the other (for example the pre-existing MIT license badge of this repository) does not satisfy the check
<!-- /mb-scenario:1 -->
