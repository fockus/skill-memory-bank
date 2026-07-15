# Requirements: agreements

> Spec triple — see also: design.md, tasks.md.
> Source: `context/agreements.md` (EARS-validated, grilling interview 2026-07-15).
>
> EARS acceptance criteria (uppercase keywords, REQ-ID bullets):
> - Ubiquitous:        `THE SYSTEM SHALL <response>`
> - Event-driven:      `WHEN <trigger> THE SYSTEM SHALL <response>`
> - State-driven:      `WHILE <state> THE SYSTEM SHALL <response>`
> - Optional feature:  `WHERE <feature> THE SYSTEM SHALL <response>`
> - Unwanted:          `IF <trigger> THEN THE SYSTEM SHALL <response>`

## Requirements (EARS)

### Requirement 1: Canonical registry file

**User Story:** As a memory-bank user, I want confirmed decisions stored in one canonical `agreements.md` with stable IDs and statuses, so that "what is in force right now" is answerable without rereading conversation history.

#### Acceptance Criteria

- **REQ-001** (ubiquitous): The agreements registry shall store confirmed decisions in `<bank>/agreements.md` with monotonic never-reused `AGR-NNN` identifiers, an ISO date, a source, and exactly one of four statuses: active, deferred, superseded, rejected.
- **REQ-012** (ubiquitous): The file `agreements.md` shall be the single source of truth; `mb-agree.sh sync` shall rebuild the managed block from the file so that manual file edits can be reconciled.

### Requirement 2: Script-mediated mutations

**User Story:** As a user running parallel sessions in one working tree, I want every registry mutation to go through an atomic locked CLI, so that IDs never collide and the format never drifts.

#### Acceptance Criteria

- **REQ-002** (event-driven): When a confirmed decision is captured, the system shall persist it exclusively through `mb-agree.sh` subcommands (`add`, `supersede`, `defer`, `reject`, `question`, `resolve`, `list`, `sync`) rather than direct file edits by the model.
- **REQ-004** (event-driven): When `mb-agree.sh add --supersedes N` is invoked, the system shall atomically create the new active entry, mark `AGR-N` as superseded with a link to the new ID, and move it to the Archive section in the same operation.
- **REQ-013** (unwanted): If `--supersedes N` references a non-existent or non-active agreement, then the system shall exit with a clear error and shall change nothing.
- **REQ-014** (event-driven): When two parallel sessions mutate the registry concurrently, the system shall serialize mutations via a lock so that issued IDs remain unique and no update is lost.
- **REQ-016** (event-driven): When `mb-agree.sh question` or `resolve` is invoked, the system shall add or close an entry in the Open Questions section without touching the managed block (Open Questions are not injected).

### Requirement 3: Injection into agent instruction files

**User Story:** As the model starting a fresh session (any agent — Claude Code, Cursor, Codex, …), I want all active agreements visible in CLAUDE.md/AGENTS.md with a pointer to the registry, so that I obey them without being reminded.

#### Acceptance Criteria

- **REQ-005** (event-driven): When any mutating subcommand completes, the system shall regenerate the managed block (`<!-- mb-agreements:start -->` … `<!-- mb-agreements:end -->`) in the project-root `CLAUDE.md` and `AGENTS.md` with every active agreement as a one-liner `AGR-NNN: statement` plus a single pointer line to `<bank>/agreements.md`.
- **REQ-006** (unwanted): If neither `CLAUDE.md` nor `AGENTS.md` exists in the project root, then the system shall create `AGENTS.md` containing only the managed block.
- **REQ-007** (unwanted): If the number of active agreements exceeds 25, then the system shall print a prune warning and shall still include all active agreements in the managed block without silent truncation.

### Requirement 4: Model conduct rules

**User Story:** As a user, I want the model to record only decisions I explicitly confirmed and to announce every write visibly, so that ideas and hypotheses never silently become obligations.

#### Acceptance Criteria

- **REQ-009** (ubiquitous): The skill rules shall instruct the model to record only explicitly confirmed user decisions, to announce every recorded entry visibly as `→ AGR-NNN записано: <statement>`, and to route unconfirmed hypotheses to Open Questions instead of Active.
- **REQ-015** (optional): Where a decision has a companion ADR, the registry entry shall carry a `→ ADR-NNN` reference and the detailed rationale shall live in the ADR, not in the registry.

### Requirement 5: Agreement compliance check

**User Story:** As a user closing a plan, I want `/mb verify` to check the result against every active agreement, so that violations surface before `/mb done` instead of after shipping.

#### Acceptance Criteria

- **REQ-010** (event-driven): When `/mb verify` runs in a bank where `agreements.md` exists, the verifier shall classify every active agreement as satisfied, violated, or not-applicable and shall include the classification in its report.
- **REQ-011** (unwanted): If any active agreement is classified as violated, then the verifier shall return a FAIL verdict and shall present the explicit choice: fix the implementation or supersede the agreement.

### Requirement 6: Lazy activation and kill-switch

**User Story:** As a user of banks that never use agreements, I want zero artifacts and zero token overhead until the first `/mb agree`, and a config switch to turn the feature off, so that the skill's defaults-never-change contract holds.

#### Acceptance Criteria

- **REQ-003** (event-driven): When `mb-agree.sh add` is invoked in a bank without `agreements.md`, the system shall create the file from the template (sections: Active / Deferred / Open Questions / Archive) — lazy activation, no artifacts before first use.
- **REQ-008** (state-driven): While `MB_AGREEMENTS=off` is set in `.mb-config`, the system shall reject every `mb-agree.sh` subcommand as an explained no-op and shall not modify `CLAUDE.md`, `AGENTS.md`, or `agreements.md`.

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: First add lazily activates the feature
**Covers:** REQ-001, REQ-003, REQ-005, REQ-006

- GIVEN a bank with no `agreements.md` and a project root with no `CLAUDE.md`/`AGENTS.md`
- WHEN `mb-agree.sh add "Memory Bank is the canonical project state store"` runs
- THEN `agreements.md` is created with sections Active / Deferred / Open Questions / Archive and entry `AGR-001 (…, user-confirmed): Memory Bank is the canonical project state store` under Active
- AND `AGENTS.md` is created containing only the managed block with the `AGR-001` one-liner and the pointer line
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: Supersede replaces atomically
**Covers:** REQ-004

- GIVEN `AGR-004: Kanban is part of the MVP` with status active
- WHEN `mb-agree.sh add "Kanban is postponed until phase 2" --supersedes 4` runs
- THEN a new active entry `AGR-NNN` is created, `AGR-004` is marked `superseded by AGR-NNN` and moved to Archive
- AND the managed block contains the new statement and no longer contains `AGR-004`
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: Supersede of a non-active target changes nothing
**Covers:** REQ-013

- GIVEN `AGR-004` already has status superseded
- WHEN `mb-agree.sh add "…" --supersedes 4` runs
- THEN the command exits non-zero with error `AGR-004 is not active`
- AND `agreements.md`, `CLAUDE.md`, and `AGENTS.md` are byte-identical to before
<!-- /mb-scenario:3 -->

<!-- mb-scenario:4 -->
### Scenario: Kill-switch makes every subcommand a no-op
**Covers:** REQ-008

- GIVEN `.mb-config` contains `MB_AGREEMENTS=off` and `agreements.md` exists
- WHEN any `mb-agree.sh` subcommand runs
- THEN it exits without writing, printing that agreements are disabled and how to re-enable
- AND `agreements.md`, `CLAUDE.md`, and `AGENTS.md` are unmodified
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: Sync is idempotent and preserves foreign content
**Covers:** REQ-005, REQ-012

- GIVEN a `CLAUDE.md` with user content above and below an existing managed block
- WHEN `mb-agree.sh sync` runs twice with no registry change
- THEN both runs produce byte-identical `CLAUDE.md`
- AND every byte outside the managed block equals the original user content
<!-- /mb-scenario:5 -->

<!-- mb-scenario:6 -->
### Scenario: Oversized active list warns but never truncates
**Covers:** REQ-007

- GIVEN 26 active agreements in the registry
- WHEN a mutating subcommand completes
- THEN a prune warning is printed to stderr
- AND the managed block still lists all 26 one-liners
<!-- /mb-scenario:6 -->

<!-- mb-scenario:7 -->
### Scenario: Parallel adds get unique IDs
**Covers:** REQ-014

- GIVEN two shells invoking `mb-agree.sh add` at the same moment in one bank
- WHEN both commands complete
- THEN the registry contains two entries with distinct consecutive `AGR-NNN` IDs
- AND no entry or block update is lost
<!-- /mb-scenario:7 -->

<!-- mb-scenario:8 -->
### Scenario: Verify fails on a violated agreement
**Covers:** REQ-010, REQ-011

- GIVEN an active agreement `AGR-002: Phase 1 must not depend on a vector database` and a diff that adds a vector-DB dependency
- WHEN `/mb verify` runs
- THEN the report classifies `AGR-002` as violated and the verdict is FAIL
- AND the report offers the explicit choice: fix the implementation or supersede `AGR-002`
<!-- /mb-scenario:8 -->

<!-- mb-scenario:9 -->
### Scenario: Damaged managed block fails loudly
**Covers:** REQ-005, REQ-012

- GIVEN a `CLAUDE.md` containing `<!-- mb-agreements:start -->` but no end marker
- WHEN `mb-agree.sh sync` runs
- THEN the command exits non-zero naming the damaged file and marker
- AND `CLAUDE.md` is not modified
<!-- /mb-scenario:9 -->
