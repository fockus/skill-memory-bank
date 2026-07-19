# Requirements: openspec-adapter

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

- **REQ-001** (event-driven): When the user runs the OpenSpec import command for a change id, the system shall create a Memory Bank spec triple under `specs/<topic>/` from that change.
- **REQ-002** (ubiquitous): The system shall convert OpenSpec change artifacts into the Memory Bank format deterministically, producing a byte-stable skeleton for identical input.
- **REQ-003** (ubiquitous): The system shall not write to any file under the OpenSpec project directory.
- **REQ-004** (event-driven): When importing requirement deltas, the system shall map ADDED and MODIFIED requirements to REQ-NNN bullets and record REMOVED requirements as removed-scope notes with their reason.
- **REQ-005** (ubiquitous): The system shall anchor each generated REQ-NNN to its source OpenSpec requirement name via a hidden marker.
- **REQ-006** (ubiquitous): The system shall generate the target format skeleton from a fixed template without LLM involvement.
- **REQ-007** (optional): Where the normalize flag is passed, the system shall run an LLM pass that rewrites requirement text into EARS patterns and fills missing scenarios and Covers links.
- **REQ-008** (event-driven): When the normalize pass produces a slot output, the system shall cache it keyed by the source requirement hash and reuse it while that source is unchanged.
- **REQ-009** (state-driven): While the normalize flag is not passed, the system shall fill LLM slots with deterministic fallbacks.
- **REQ-010** (unwanted): If the normalize pass is requested but the language model is unavailable, then the system shall fall back to deterministic slots and record a warning without aborting the import.
- **REQ-011** (event-driven): When importing OpenSpec scenarios, the system shall map each `#### Scenario` WHEN/THEN block to the Memory Bank scenario format.
- **REQ-012** (event-driven): When importing OpenSpec tasks, the system shall map each numbered task group to one mb-task carrying its checkbox items as the task checklist.
- **REQ-013** (unwanted): If an OpenSpec task line is not in checkbox form, then the system shall import it as plain checklist text under its group and record a warning.
- **REQ-014** (ubiquitous): The system shall record the source change path and a content hash in the spec frontmatter.
- **REQ-015** (event-driven): When the user runs the OpenSpec sync command, the system shall re-import only specs whose stored source hash differs from the current source.
- **REQ-016** (event-driven): When re-importing a change, the system shall refresh requirements and design from source while preserving existing task check-state matched by task text.
- **REQ-017** (event-driven): When re-import finds tasks absent from source that were previously imported, the system shall move them to the backlog rather than deleting them silently.
- **REQ-018** (event-driven): When an OpenSpec RENAMED delta is imported, the system shall move the REQ anchor from the old name to the new name and preserve the existing REQ-NNN and its task progress.
- **REQ-019** (optional): Where an OpenSpec project is detected, the system shall list available changes and their import status.
- **REQ-020** (unwanted): If EARS validation of an imported requirement fails, then the system shall record a warning and continue rather than aborting the import.


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
