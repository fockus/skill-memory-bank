# Requirements: sdd-openspec-parity

> Spec triple — see also: design.md, tasks.md.
>
> EARS acceptance criteria (uppercase keywords, REQ-ID bullets):
> - Ubiquitous:        `THE SYSTEM SHALL <response>`
> - Event-driven:      `WHEN <trigger> THE SYSTEM SHALL <response>`
> - State-driven:      `WHILE <state> THE SYSTEM SHALL <response>`
> - Optional feature:  `WHERE <feature> THE SYSTEM SHALL <response>`
> - Unwanted:          `IF <trigger> THEN THE SYSTEM SHALL <response>`

## Requirements (EARS)

<!-- Hybrid SDD format: each requirement = ONE Kiro User Story + its EARS acceptance -->
<!-- criteria. Group the REQ-NNN bullets below under user stories; split into multiple -->
<!-- ### Requirement N blocks as the topic needs. REQ-IDs stay unique and EARS-valid   -->
<!-- (mb-ears-validate.sh validates only REQ bullets; User-Story lines are ignored).   -->

### Requirement 1: <!-- short title -->

**User Story:** As a <role>, I want <feature>, so that <benefit>.

#### Acceptance Criteria

- **REQ-001** (ubiquitous): The system shall store canonical copies of external input artifacts (PRD, JTBD, diagrams, ADR excerpts) under `specs/<topic>/inputs/`.
- **REQ-002** (event-driven): When `/mb sdd` generates requirements.md and input artifacts exist, the system shall render a `## Sources` section assigning each input a stable S-NN identifier.
- **REQ-003** (optional): Where a `### Requirement N` block declares a `**Sources:** S-NN` line, the system shall validate that every referenced S-NN exists in the `## Sources` registry.
- **REQ-004** (event-driven): When `/mb discuss` runs Phase 0 and input artifacts exist for the topic, the system shall cite them as sources in the research digest.
- **REQ-005** (unwanted): If a `## Sources` entry references a path under `inputs/` that does not resolve, then the system shall report a validation error.
- **REQ-006** (event-driven): When `mb-sdd.sh` generates requirements.md from an existing context file, the system shall copy the Purpose summary into a `## Why` section linking to the context file.
- **REQ-007** (event-driven): When `mb-sdd.sh` creates a new spec, the system shall write a `scenarios: required` marker into the spec.
- **REQ-008** (state-driven): While a spec carries the `scenarios: required` marker, the system shall report a validation error for every SHALL or MUST requirement lacking a covering scenario.
- **REQ-009** (unwanted): If a spec lacks the `scenarios: required` marker, then the system shall validate it under the pre-existing opt-in rules without behavior change.
- **REQ-010** (state-driven): While validating a spec marked `scenarios: required`, the system shall report an error for any REQ bullet containing more than one SHALL or MUST keyword.
- **REQ-011** (ubiquitous): The system shall emit warnings for REQ bullets containing terms from the vague-wording stop-list.
- **REQ-012** (ubiquitous): The system shall emit warnings for scenario blocks whose titles are generic placeholders.
- **REQ-013** (optional): Where the `--strict` flag is passed to spec validation, the system shall treat wording-lint warnings as errors.
- **REQ-014** (ubiquitous): The system shall accept SHALL, MUST, SHOULD and MAY as requirement modal keywords in EARS validation.
- **REQ-015** (ubiquitous): The system shall apply task-coverage, scenario-coverage and test-coverage gates only to SHALL and MUST requirements.
- **REQ-016** (ubiquitous): The system shall mark SHOULD and MAY requirements as non-gated in the traceability matrix.
- **REQ-017** (unwanted): If a secret or credential pattern is detected in a file under `specs/<topic>/inputs/`, then the system shall fail spec validation with an error naming the file and line.
- **REQ-018** (optional): Where a flagged line carries the `<!-- mb-secret-ok -->` pragma on or directly above it, the system shall suppress that specific finding.
- **REQ-019** (unwanted): If a spec has unchecked tasks, then the system shall refuse archiving it to `specs/done/` unless the `--incomplete` flag with a reason is provided.
- **REQ-020** (event-driven): When a spec is archived with `--incomplete`, the system shall move its unchecked tasks to backlog.md and record the reason in the archive header and progress.md.
- **REQ-021** (ubiquitous): The system shall maintain living capability specs under `specs/system/` as the canonical description of current behavior.
- **REQ-022** (optional): Where a change spec contains ADDED, MODIFIED or REMOVED requirement sections, the system shall validate them as deltas against the referenced living spec.
- **REQ-023** (event-driven): When `/mb done` completes a change spec containing delta sections, the system shall merge the deltas into the living specs before archiving.
- **REQ-024** (ubiquitous): The system shall implement all parity features without invoking the OpenSpec runtime.


## Scenarios

<!-- OPTIONAL but recommended: GIVEN/WHEN/THEN acceptance scenarios.            -->
<!-- Each scenario links to its REQ(s) via **Covers:** and becomes a test-plan  -->
<!-- item (scripts/mb-scenario-extract.py) that /mb work turns into a real test -->
<!-- in the project's own stack. Enforce "every REQ has a scenario" with         -->
<!-- mb-spec-validate.sh --require-scenarios (off by default).                   -->

<!-- mb-scenario:1 -->
### Scenario: <name>
**Covers:** REQ-NNN

- GIVEN <initial state>
- WHEN <action taken>
- THEN <observable outcome>
- AND <additional outcome — optional>
<!-- /mb-scenario:1 -->
