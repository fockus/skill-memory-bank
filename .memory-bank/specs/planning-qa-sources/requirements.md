---
type: spec-requirements
topic: planning-qa-sources
status: ready
created: 2026-10-15
group: "[SPEC:autopilot]"
parent_context: context/drive-autopilot.md
interview_transcript: context/drive-autopilot-interview.md
linked_design: design.md
backlog: [I-281]
covers_umbrella: [REQ-001, REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010, REQ-011, REQ-034, REQ-035, REQ-036, REQ-037, REQ-038]
layers:
  contract_first: false
  contract_first_reason: prompt and script changes over existing contracts
  integration_tests: true
  e2e_tests: false
  e2e_tests_reason: covered by the drive-autopilot e2e
---

# Requirements: planning-qa-sources

> Spec triple — see also: design.md, tasks.md.
> Slice S1 of group `[SPEC:autopilot]` (backlog I-281). Source: `context/drive-autopilot.md` decisions
> D-04 (plan-as-wrapper after a spec), D-05, D-06, D-12, D-14 and NFR-001..NFR-003, i.e. context
> REQ-001..REQ-011 and REQ-034..REQ-038; agreements AGR-101, AGR-102, AGR-075, AGR-078.
> REQ ids here are spec-local; every requirement names its context source.
> Runs in parallel with S2 `team-completion`; S3 `drive-autopilot` depends on both. Drive and team
> changes are out of scope here.
>
> EARS acceptance criteria (uppercase keywords, REQ-ID bullets):
> - Ubiquitous:        `THE SYSTEM SHALL <response>`
> - Event-driven:      `WHEN <trigger> THE SYSTEM SHALL <response>`
> - State-driven:      `WHILE <state> THE SYSTEM SHALL <response>`
> - Optional feature:  `WHERE <feature> THE SYSTEM SHALL <response>`
> - Unwanted:          `IF <trigger> THEN THE SYSTEM SHALL <response>`

## Requirements (EARS)

### Requirement 1: QA is declared by tier when a plan is created

**User Story:** As a user planning standard or larger work, I want QA switched on by default with an
explicit, recorded way out, so that a live check of the user path is part of "done" without me asking
for it, and small work stays cheap.

Source: context REQ-001, REQ-002, REQ-003, REQ-006 · D-12 · AGR-101 · user decision 2026-10-15 (`qa.enabled: auto`).

#### Acceptance Criteria

- **REQ-001** (event-driven): WHEN `/mb plan` or `/mb sdd` creates a plan or a plan wrapper of tier standard, large or extra and QA is not disabled, THE SYSTEM SHALL declare `qa: on` in the plan frontmatter, add a QA item to the plan DoD and run the test-case authoring step. Source: context REQ-001.
- **REQ-002** (event-driven): WHEN a plan of tier small is created without `--qa` while `qa.enabled` is `auto`, THE SYSTEM SHALL declare `qa: off — small tier` and add no QA item. Source: context REQ-002.
- **REQ-003** (event-driven): WHEN `--no-qa`, a user request to skip QA, or `qa.enabled: false` in the effective `pipeline.yaml` is present, THE SYSTEM SHALL declare `qa: off — disabled` and add neither the QA item nor the test-case authoring step. Source: context REQ-003.
- **REQ-004** (unwanted): IF `<bank>/qa/README.md` is absent when QA would be on, THEN THE SYSTEM SHALL declare `qa: off — no QA target` and finish the plan without failing. Source: context REQ-006.
- **REQ-020** (optional feature): WHERE the effective `pipeline.yaml` sets `qa.enabled: true`, THE SYSTEM SHALL declare `qa: on` for a plan of every tier, small included, unless `--no-qa` is given or the QA target is absent. Source: D-12 · user decision 2026-10-15.
- **REQ-021** (ubiquitous): THE SYSTEM SHALL ship `qa.enabled: auto` as the bundled default, accept `auto`, `true` and `false` for `qa.enabled` and `hosts.<host>.qa.enabled` with and without PyYAML, and treat `auto` as the tier rule of REQ-001 and REQ-002. Source: D-12 · AGR-101 · user decision 2026-10-15.

### Requirement 2: Test cases are written from requirements right after planning

**User Story:** As the owner of a plan, I want an independent QA agent to write the test cases from the
requirements and DoD before any code exists, so that the cases describe what was asked, not what was
built.

Source: context REQ-004, REQ-005, REQ-034, REQ-035, REQ-036 · NFR-002 · D-05, D-14 · AGR-102.

#### Acceptance Criteria

- **REQ-005** (event-driven): WHEN the test-case authoring step runs, THE SYSTEM SHALL dispatch `mb-qa` once with the plan, its requirements or DoD and its tier, to write cases into `<bank>/qa/test_cases/<topic>/`, each tagged `<topic>` and carrying `covers:`. Source: context REQ-004.
- **REQ-006** (state-driven): WHILE the tier is standard, THE SYSTEM SHALL require one case per key user path, and WHILE the tier is large or extra, one case per externally testable REQ. Source: context REQ-005.
- **REQ-007** (ubiquitous): THE SYSTEM SHALL give every QA case frontmatter fields `id`, `covers`, `origin` (specified, derived or regression) and `proof` (live, test or both). Source: context REQ-034.
- **REQ-008** (unwanted): IF the expected result of a case cannot be derived from the requirements or the DoD, THEN THE SYSTEM SHALL mark the case `status: needs_spec` and keep it out of live runs instead of inventing assertions. Source: context REQ-035.
- **REQ-009** (event-driven): WHEN a critical or major QA bug is set to fixed, THE SYSTEM SHALL write a case with `origin: regression` beside the scenario that found it and SHALL require the regression test of the fix to carry an `mb:case <id>` comment. Source: context REQ-036.
- **REQ-010** (state-driven): WHILE QA is on for a standard plan, THE SYSTEM SHALL add at most two dispatches to a clean run: one test-case authoring dispatch and one QA run. Source: NFR-002.

### Requirement 3: A spec gets a plan wrapper that says how to run it

**User Story:** As a user who just finished a spec, I want a plan wrapper next to it, so that the
execution mode, the QA declaration and the plan-level DoD live in one place `/mb work` and drive can
pick up.

Source: context REQ-007 · D-04.

#### Acceptance Criteria

- **REQ-011** (event-driven): WHEN `/mb sdd` publishes a spec, THE SYSTEM SHALL offer a plan wrapper with `linked_spec: specs/<topic>` that states how to execute the spec, and SHALL create it without asking under `--auto` or when QA is on. Source: context REQ-007.

### Requirement 4: Verifier, reviewer and judge see the same sources

**User Story:** As the user relying on the gates, I want the verifier, reviewer and judge to read the
spec, the plan wrapper and the last QA report together, so that a plan that drifted from its spec or a
requirement with no proof is caught instead of passing on the DoD alone.

Source: context REQ-008, REQ-009, REQ-010, REQ-011, REQ-037, REQ-038 · D-06, D-14.

#### Acceptance Criteria

- **REQ-012** (event-driven): WHEN `mb-work-plan.sh` emits a work item that comes from a spec, THE SYSTEM SHALL include `spec_path`, and `plan_path` when a plan wrapper links that spec. Source: context REQ-008.
- **REQ-013** (event-driven): WHEN the verifier, reviewer or judge is dispatched, THE SYSTEM SHALL pass the spec, the plan wrapper and the last QA report of the item. Source: context REQ-009.
- **REQ-014** (event-driven): WHEN the verifier checks an item that has both a plan wrapper and a spec, THE SYSTEM SHALL report plan DoD coverage and spec REQ coverage in separate sections. Source: context REQ-010.
- **REQ-015** (unwanted): IF the plan wrapper and the spec diverge, by a REQ in the wrapper's scope that no task covers or by plan work outside the spec, THEN THE SYSTEM SHALL report a critical finding. Source: context REQ-011.
- **REQ-016** (event-driven): WHEN the verifier checks an item with QA cases, THE SYSTEM SHALL report per REQ its cases and their proof: live PASS in the last QA report, a test carrying `mb:case <id>`, or none. Source: context REQ-037.
- **REQ-017** (unwanted): IF an item has no requirement, DoD item or case to verify, THEN THE SYSTEM SHALL report `NOTHING TO VERIFY` instead of PASS and `/mb work` SHALL halt that item. Source: context REQ-038.

### Requirement 5: A plan's QA declaration reaches /mb work, and nothing else changes

**User Story:** As a user running `/mb work`, I want a plan that declares QA to run it without an extra
flag, and every other run to behave exactly as before, so that the default changes only where it was
decided.

Source: D-05, D-12 · NFR-003 · AGR-098 discipline.

#### Acceptance Criteria

- **REQ-018** (event-driven): WHEN `/mb work` runs a plan, or a spec through its plan wrapper, that declares `qa: on`, THE SYSTEM SHALL run QA as with `--qa` and select the cases with `@<topic>` at cadence stage or plan. Source: D-05, D-12.
- **REQ-019** (ubiquitous): THE SYSTEM SHALL keep the `mb-workflow.sh` JSON and the `mb-work-plan.sh` JSON Lines of a plain plan byte-identical to their pre-change output when QA is not on for the run, and `qa.enabled: auto` alone SHALL NOT turn the run-level QA step on. Source: NFR-003 · user decision 2026-10-15.

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: QA declaration follows tier opt-outs and target
**Covers:** REQ-001, REQ-002, REQ-003, REQ-004, REQ-020

- GIVEN a bank with `qa/README.md` and the bundled `qa.enabled: auto`
- WHEN `mb-plan.sh feature checkout --tier standard` creates a plan
- THEN the plan frontmatter says `qa: on` and its last DoD list ends with the QA item naming `/mb qa run @checkout`
- AND `--tier small` gives `qa: off — small tier`, `--tier small --qa` gives `qa: on`, `--no-qa` or `qa.enabled: false` gives `qa: off — disabled`, all without the QA item
- AND `qa.enabled: true` gives `qa: on` for `--tier small` while `--no-qa` still gives `qa: off — disabled`
- AND with `qa/README.md` removed, `--tier large` gives `qa: off — no QA target` and exit 0
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: Test case authoring contract
**Covers:** REQ-005, REQ-006, REQ-007, REQ-008, REQ-010

- GIVEN a plan with `qa: on` of tier standard
- WHEN `/mb plan` reaches its QA step
- THEN it dispatches `mb-qa` exactly once with the plan path, the topic and the tier, and `mb-qa` in authoring mode writes only under `qa/test_cases/<topic>/`
- AND each case carries `id`, `tags: [<topic>]`, `covers`, `origin`, `proof`, with one case per key user path for standard and one per externally testable REQ for large or extra
- AND a case whose expected result is not in the requirements or DoD carries `status: needs_spec`
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: Fixed major bug yields a regression case
**Covers:** REQ-008, REQ-009

- GIVEN an open major `BUG-003` whose body names `- Scenario: qa/test_cases/checkout/pay.md, step 2` and a case file with `covers: [REQ-002]`
- WHEN `mb-qa-bug.sh set BUG-003 fixed` runs
- THEN `qa/test_cases/checkout/reg-bug-003.md` exists with `id: reg-bug-003`, `origin: regression`, `proof: both` and `covers: [REQ-002]`, and stdout names it
- AND a medium bug set to fixed writes no case, and an existing regression case is never overwritten
- AND a live QA selection skips cases with `status: needs_spec` or `proof: test` and lists them under `## Not verified`
<!-- /mb-scenario:3 -->

<!-- mb-scenario:4 -->
### Scenario: Spec gets a plan wrapper
**Covers:** REQ-011

- GIVEN a published spec `specs/demo` with three tasks
- WHEN `mb-plan.sh feature demo --spec demo --tier large` creates the wrapper
- THEN the wrapper frontmatter carries `linked_spec: specs/demo` and a `qa:` declaration
- AND `mb-work-plan.sh --target <wrapper>` resolves the three spec tasks
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: Work items carry spec and plan paths
**Covers:** REQ-012, REQ-019

- GIVEN a spec `specs/demo` and a wrapper plan linking it
- WHEN `mb-work-plan.sh` runs on the wrapper and on the topic `demo`
- THEN every emitted item carries `spec_path` ending in `specs/demo` and `plan_path` naming the wrapper
- AND a plain plan without a spec emits neither key, and its JSON Lines and the workflow JSON equal the QA-off goldens
<!-- /mb-scenario:5 -->

<!-- mb-scenario:6 -->
### Scenario: Agents receive the source bundle
**Covers:** REQ-013, REQ-014, REQ-015

- GIVEN an item with a spec, a plan wrapper and a QA report
- WHEN `mb-review.sh --emit-payload` runs with `--source` for each of them
- THEN the payload ends with a `## Sources` section holding each file, and without `--source` the payload is unchanged
- AND the verifier contract names separate plan DoD and spec REQ sections and a critical plan-spec divergence finding
<!-- /mb-scenario:6 -->

<!-- mb-scenario:7 -->
### Scenario: Verifier coverage table and nothing to verify
**Covers:** REQ-016, REQ-017

- GIVEN cases with `covers:` and a test carrying `mb:case reg-bug-003`
- WHEN the verifier builds its QA coverage section
- THEN each REQ row lists its cases with proof live PASS, test or none
- AND a source with no REQ, DoD item or case gets `NOTHING TO VERIFY`, which `/mb work` treats as a halt, never as PASS
<!-- /mb-scenario:7 -->

<!-- mb-scenario:8 -->
### Scenario: Plan QA declaration turns QA on in work
**Covers:** REQ-018

- GIVEN a plan whose frontmatter says `qa: on` and topic `checkout`
- WHEN `/mb work` resolves the workflow and the items for it
- THEN `--qa` is passed to both resolvers and the QA selection is `@checkout`
- AND a plan without `qa: on` gets no QA key from either resolver
<!-- /mb-scenario:8 -->

<!-- mb-scenario:9 -->
### Scenario: Pipeline qa enabled auto is accepted and inert
**Covers:** REQ-021, REQ-019

- GIVEN the bundled `pipeline.yaml` with `qa.enabled: auto`
- WHEN `mb-pipeline-validate.sh` runs with PyYAML and with PyYAML hidden
- THEN both exit 0, `auto`, `true` and `false` are accepted in `qa` and in `hosts.<host>.qa`, and `maybe` is rejected
- AND `mb-workflow.sh --json` emits no `qa` key, the same bytes as the QA-off golden
<!-- /mb-scenario:9 -->
