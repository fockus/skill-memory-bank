# Requirements: quality-track

> Spec triple — see also: design.md, tasks.md.
> Source context: `context/quality-track.md` (discuss interview 2026-07-15, AGR-008/AGR-009).
> Release: donor program **v6.2.0**, queued after v6.1.0 (evidence core §7.5 is a dependency, not part of this spec).
>
> EARS acceptance criteria (uppercase keywords, REQ-ID bullets):
> - Ubiquitous:        `THE SYSTEM SHALL <response>`
> - Event-driven:      `WHEN <trigger> THE SYSTEM SHALL <response>`
> - State-driven:      `WHILE <state> THE SYSTEM SHALL <response>`
> - Optional feature:  `WHERE <feature> THE SYSTEM SHALL <response>`
> - Unwanted:          `IF <trigger> THEN THE SYSTEM SHALL <response>`

## Why

"124 tests passed" does not prove "all mandatory requirements are implemented and
verified". Quality Track turns requirements, tests and execution results into one
provable chain — Requirement → Scenario → QA Case → Verification Implementation →
Execution Evidence → Quality Gate — with `NOT_RUN ≠ PASS` enforced by a
deterministic core, while the LLM layer plans, generates and classifies.
Full rationale and decision ledger: `context/quality-track.md`.

## Requirements (EARS)

### Requirement 1: QA contract & planning

**User Story:** As a developer, I want a single QA contract derived from my spec, so that every requirement gets explicit, reviewable QA cases with oracles instead of ad-hoc test intuition.

#### Acceptance Criteria

- **REQ-001** (event-driven): When `/mb qa plan <target>` runs, the system shall create or update a single QA contract at `specs/<topic>/qa.md` whose cases carry `<!-- mb-case:ID -->` markers.
- **REQ-002** (ubiquitous): The system shall classify every QA case origin as exactly one of specified, derived, or regression.
- **REQ-003** (event-driven): When a derived case's expected behavior cannot be inferred from the requirements source, the system shall mark the case NEEDS_SPEC instead of inventing assertions.
- **REQ-004** (ubiquitous): The system shall require every QA case to declare an oracle listing observable facts that prove the requirement.

### Requirement 2: Requirement sources

**User Story:** As a skill user on a spec-driven or brownfield project, I want QA to read requirements from my native SDD spec, active plan, or a bare diff, so that the component works without forcing a second requirements catalog.

#### Acceptance Criteria

- **REQ-005** (ubiquitous): The system shall resolve requirements through a source adapter interface supporting kinds memory-bank, plan, and diff.
- **REQ-006** (state-driven): While the source kind is diff, the system shall report requirements completeness as UNKNOWN in every produced report.
- **REQ-007** (state-driven): While the source kind is plan, the system shall label report scope as implementation-plan verification.
- **REQ-008** (event-driven): When a QA contract is built or updated, the system shall record the source document digest without copying the source into a second requirements catalog.

### Requirement 3: Test-to-case linkage

**User Story:** As a reviewer, I want tests explicitly linked to QA cases via language-agnostic markers, so that coverage claims are grepable facts rather than name-matching guesses.

#### Acceptance Criteria

- **REQ-009** (ubiquitous): The system shall map tests to QA cases via language-agnostic `mb:case` and `mb:covers` comment markers.
- **REQ-010** (state-driven): While a test-to-case mapping is inferred rather than marker-based, the system shall exclude that mapping from strict PASS and flag it in the report.

### Requirement 4: Deterministic runner & evidence

**User Story:** As a release owner, I want real runner executions persisted as digest-bound evidence, so that a green result can never be stale, fabricated, or silently skipped.

#### Acceptance Criteria

- **REQ-011** (event-driven): When `/mb qa run` executes, the system shall run configured suites as argv arrays without shell string evaluation.
- **REQ-012** (ubiquitous): The system shall parse suite results through adapters for pytest JUnit XML, Bats TAP, generic JUnit XML, and generic exit-code.
- **REQ-013** (ubiquitous): The system shall compute case statuses PASS, FAIL, MISSING, NOT_RUN, STALE, FLAKY, WAIVED, and NEEDS_SPEC in the deterministic core from parsed runner output only.
- **REQ-014** (event-driven): When a suite run completes, the system shall persist an evidence manifest with run id, git commit, source digest, contract digest, test digest, suite config digest, profile, and timestamp under `.memory-bank/.qa/`.
- **REQ-015** (event-driven): When any digest recorded in an evidence manifest no longer matches the current inputs, the system shall mark that evidence STALE.
- **REQ-016** (unwanted): If a required suite was not executed, then the system shall report its cases as NOT_RUN and never as PASS.

### Requirement 5: Quality gate & waivers

**User Story:** As a team lead, I want a deterministic, configurable gate with explicit expiring waivers, so that "ready to ship" is a computed verdict, not an opinion.

#### Acceptance Criteria

- **REQ-017** (ubiquitous): The system shall apply a deterministic, configuration-driven quality gate that produces a machine-readable verdict and process exit code.
- **REQ-018** (unwanted): If a specified case has no verification implementation or its mapped test fails, then the quality gate shall block.
- **REQ-019** (unwanted): If a critical case receives semantic status mismatch, then the quality gate shall block.
- **REQ-020** (event-driven): When a waiver passes its expiry date, the system shall convert it into a blocking gate finding.

### Requirement 6: Semantic audit

**User Story:** As a reviewer, I want an LLM audit of whether each test's assertions actually cover its case oracle, so that green-but-empty tests are surfaced instead of counted as proof.

#### Acceptance Criteria

- **REQ-021** (event-driven): When semantic audit runs, the system shall evaluate each mapped test against its case oracle producing exactly one of strong, weak, mismatch, or uncertain.

### Requirement 7: Test generation

**User Story:** As a developer, I want the QA layer to generate missing tests at the right level with explicit case markers, so that coverage gaps close without hand-writing boilerplate or defaulting everything to E2E.

#### Acceptance Criteria

- **REQ-022** (optional): Where write mode is enabled, the system shall generate missing tests carrying `mb:case` markers and following existing project test conventions.
- **REQ-023** (event-driven): When a test is generated for not-yet-implemented behavior in TDD mode, the system shall confirm the expected RED result before the product fix proceeds.
- **REQ-024** (event-driven): When the generator selects a verification level for a case, the system shall choose the lowest suitable level instead of defaulting to end-to-end.

### Requirement 8: `/mb work` integration

**User Story:** As a skill user, I want QA to attach to the existing `/mb work` lifecycle behind an opt-in flag, so that governed runs gain a QA gate while every existing workflow stays untouched.

#### Acceptance Criteria

- **REQ-025** (event-driven): When `/mb work <target> --qa` runs, the system shall execute quality actions inside the existing canonical stages without introducing new mandatory stages.
- **REQ-026** (state-driven): While quality is not enabled by config or flag, the system shall keep `/mb work` behavior byte-identical to the current engine.

### Requirement 9: Reporting & memory updates

**User Story:** As a project owner, I want QA outcomes reflected in one report plus the Memory Bank core files, so that the bank stores current proof of quality, not just development history.

#### Acceptance Criteria

- **REQ-027** (event-driven): When a QA run completes, the system shall write a report to `.memory-bank/reports/qa-<topic>-latest.md` linking raw artifacts instead of inlining them.
- **REQ-028** (event-driven): When a gate verdict is produced, the system shall update status.md, checklist.md, progress.md, and traceability.md, adding only unresolved actions to the checklist.

### Requirement 10: LLM-free CI

**User Story:** As a CI pipeline, I want the whole deterministic path to run without an LLM or API key, so that the release gate works headless and cached audit results are consumed, not recomputed.

#### Acceptance Criteria

- **REQ-029** (ubiquitous): The system shall execute the pipeline parse, run, collect evidence, gate, report, and exit code without requiring an LLM.

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: QA plan builds the contract from a native spec
**Covers:** REQ-001, REQ-002, REQ-004, REQ-008

- GIVEN `specs/checkout/requirements.md` with EARS REQs and GWT scenarios
- WHEN `/mb qa plan checkout` runs
- THEN `specs/checkout/qa.md` is created with `<!-- mb-case:TC-CHECKOUT-NNN -->` blocks, each carrying origin, oracle, and the recorded source digest
- AND no requirement text is duplicated into a second catalog
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: Underivable derived case becomes NEEDS_SPEC
**Covers:** REQ-003

- GIVEN a derived edge case (concurrent double-submit) whose expected outcome the source spec does not define
- WHEN the QA planner processes it
- THEN the case is marked NEEDS_SPEC with the open question recorded
- AND no assertion is invented for it
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: Diff mode never claims full compliance
**Covers:** REQ-005, REQ-006

- GIVEN a brownfield repo without a spec and a working-tree diff
- WHEN `/mb qa --from diff` runs
- THEN the report header states scope diff-based regression audit and requirements completeness UNKNOWN
<!-- /mb-scenario:3 -->

<!-- mb-scenario:12 -->
### Scenario: Plan mode labels its narrower scope
**Covers:** REQ-007

- GIVEN an active plan with DoD items and no spec
- WHEN `/mb qa --from plan` produces its report
- THEN the report scope reads implementation-plan verification, not full product verification
<!-- /mb-scenario:12 -->

<!-- mb-scenario:13 -->
### Scenario: Marker-bound test counts, inferred mapping does not
**Covers:** REQ-009, REQ-010

- GIVEN test A carrying `mb:case TC-1` and legacy test B matched to TC-2 only by name similarity
- WHEN statuses are computed after a green run
- THEN TC-1 is PASS via the marker binding
- AND TC-2 is flagged mapping_status inferred and excluded from strict PASS
<!-- /mb-scenario:13 -->

<!-- mb-scenario:14 -->
### Scenario: Suites run as argv and parse through adapters
**Covers:** REQ-011, REQ-012

- GIVEN a suite configured as `[pytest, -q, --junitxml=.memory-bank/.qa/junit/unit.xml]` and a bats suite with TAP output
- WHEN `/mb qa run` executes
- THEN each command runs as an argv array with no shell evaluation and the exact argv is recorded in evidence
- AND results parse through the junit and bats-tap adapters into per-case outcomes
<!-- /mb-scenario:14 -->

<!-- mb-scenario:4 -->
### Scenario: Missing runner binary cannot become PASS
**Covers:** REQ-013, REQ-016

- GIVEN a required suite whose command binary is absent from PATH
- WHEN `/mb qa run` executes
- THEN that suite's cases are reported NOT_RUN
- AND the quality gate fails with required_suite_not_run
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: Spec edit invalidates old green evidence
**Covers:** REQ-014, REQ-015

- GIVEN a fresh PASS manifest for TC-X recorded at source digest D1
- WHEN the source spec changes to digest D2 and the gate is evaluated
- THEN TC-X evidence is marked STALE
- AND the gate blocks with stale_evidence
<!-- /mb-scenario:5 -->

<!-- mb-scenario:6 -->
### Scenario: Specified case without implementation blocks the gate
**Covers:** REQ-017, REQ-018

- GIVEN a specified case TC-Y with no mapped test
- WHEN the quality gate runs
- THEN the verdict is FAIL with TC-Y listed under blocking findings
- AND the process exit code is non-zero
<!-- /mb-scenario:6 -->

<!-- mb-scenario:7 -->
### Scenario: Expired waiver turns into a blocker
**Covers:** REQ-020

- GIVEN a waiver for TC-Z with expiry date in the past
- WHEN the gate is evaluated
- THEN the waiver is reported invalid and TC-Z blocks the gate
<!-- /mb-scenario:7 -->

<!-- mb-scenario:8 -->
### Scenario: Green-but-empty test is caught by semantic audit
**Covers:** REQ-019, REQ-021

- GIVEN a critical case whose oracle demands order paid, exactly one charge, confirmation event
- AND a mapped passing test asserting only HTTP 200
- WHEN semantic audit runs
- THEN the test receives mismatch
- AND the gate blocks
<!-- /mb-scenario:8 -->

<!-- mb-scenario:9 -->
### Scenario: Generated test proves RED before the fix
**Covers:** REQ-022, REQ-023, REQ-024

- GIVEN write mode enabled and a specified case for not-yet-implemented behavior
- WHEN `/mb qa generate` creates the missing test
- THEN the test carries `mb:case` markers, targets the lowest suitable level, and is executed to confirm expected RED before implementation proceeds
<!-- /mb-scenario:9 -->

<!-- mb-scenario:10 -->
### Scenario: QA off means byte-identical engine
**Covers:** REQ-025, REQ-026

- GIVEN a project with no `quality.enabled` and no `--qa` flag
- WHEN any `/mb work` workflow runs
- THEN emitted steps, JSON lines, and artifacts are byte-identical to the current engine
- AND with `--qa` the quality actions appear only inside existing canonical stages
<!-- /mb-scenario:10 -->

<!-- mb-scenario:11 -->
### Scenario: CI applies the gate with no LLM available
**Covers:** REQ-027, REQ-028, REQ-029

- GIVEN a CI runner with no claude binary and no API key
- WHEN the deterministic pipeline runs parse, run, collect, gate, report
- THEN the report is written with artifact links, memory files are updated, and the exit code reflects the gate verdict
- AND cached semantic-audit results are consumed if present, never recomputed
<!-- /mb-scenario:11 -->
