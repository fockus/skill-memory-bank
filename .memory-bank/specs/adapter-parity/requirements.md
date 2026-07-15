# Requirements: adapter-parity

> Spec triple — see also: design.md, tasks.md.
> Source: `context/adapter-parity.md` (discuss of 2026-07-15, AGR-012/AGR-013).
>
> EARS acceptance criteria (uppercase keywords, REQ-ID bullets):
> - Ubiquitous:        `THE SYSTEM SHALL <response>`
> - Event-driven:      `WHEN <trigger> THE SYSTEM SHALL <response>`
> - State-driven:      `WHILE <state> THE SYSTEM SHALL <response>`
> - Optional feature:  `WHERE <feature> THE SYSTEM SHALL <response>`
> - Unwanted:          `IF <trigger> THEN THE SYSTEM SHALL <response>`

## Requirements (EARS)

### Requirement 1: Opt-in extension offer

**User Story:** As a Pi/OpenCode user installing the skill, I want to be offered the host parity extensions explicitly, so that I get full capabilities by choice and my defaults never change silently.

#### Acceptance Criteria

- **REQ-001** (event-driven): When installation targets the pi or opencode client, the system shall offer opt-in installation of the host parity extensions.
- **REQ-002** (unwanted): If the user declines the extension offer, then the system shall complete the installation without extensions and without behavior change.
- **REQ-003** (event-driven): When `/mb doctor` runs on a pi or opencode host without installed parity extensions, the system shall suggest the exact extension install command.
- **REQ-004** (ubiquitous): The system shall install host extensions only after explicit user consent.
- **REQ-005** (optional): Where a non-interactive installation passes the extensions flag, the system shall install the offered extensions without prompting.

### Requirement 2: Pi hook & subagent parity

**User Story:** As a Pi user, I want session memory, role-agent dispatch and graph tools working like in Claude Code, so that `/mb recall`, `/mb work` and GraphRAG are fully usable on Pi.

#### Acceptance Criteria

- **REQ-006** (event-driven): When the user accepts the Pi extension offer, the system shall install the session-memory extension into the resolved Pi extensions directory.
- **REQ-007** (optional): Where the Pi session-memory extension is installed, the system shall capture session start, per-turn, pre-compact and shutdown events into `session/*.md` using the same schema as Claude Code.
- **REQ-008** (event-driven): When installation targets the pi client, the system shall install the skill subagent definitions for Pi role dispatch.
- **REQ-009** (optional): Where the Pi parity extensions are installed, the system shall dispatch `/mb work` role agents through the mechanism selected by the host-API research task.
- **REQ-010** (event-driven): When the user accepts the Pi extension offer during global installation, the system shall install the graph-rag extension without requiring a separate project-local run.

### Requirement 3: OpenCode hook & subagent parity

**User Story:** As an OpenCode user, I want session-start context, per-turn capture and globally available role agents, so that the skill behaves the same whichever project I open.

#### Acceptance Criteria

- **REQ-011** (event-driven): When the user accepts the OpenCode extension offer, the system shall install the parity plugin providing session-start context injection and per-turn session capture.
- **REQ-012** (ubiquitous): The system shall install skill subagent definitions for opencode at global scope in addition to project scope.

### Requirement 4: update-notify on every capable host

**User Story:** As a skill user on any host, I want to learn about new releases, so that I do not run stale versions just because my host is not Claude Code.

#### Acceptance Criteria

- **REQ-013** (state-driven): While a host has a session-start capable transport, the system shall render the update notice on session start on that host.
- **REQ-014** (optional): Where codex experimental hooks are enabled, the system shall render the update notice through the prompt-submit hook at most once per cache TTL window.

### Requirement 5: Honest degradation, lifecycle & tests

**User Story:** As a maintainer, I want platform limits declared and parity regressions testable, so that "works everywhere" is a verified claim, not an assumption.

#### Acceptance Criteria

- **REQ-015** (ubiquitous): The system shall record capabilities a host cannot support in the adapter manifest `platform_limited` array.
- **REQ-016** (ubiquitous): The system shall cover every extension install path with tests for installation, idempotent re-run and uninstallation.
- **REQ-017** (ubiquitous): The system shall assert through negative tests that unsupported host capabilities are reported as absent with a reason.
- **REQ-018** (event-driven): When `/mb upgrade` updates the skill, the system shall refresh installed host extensions to the bundled version.
- **REQ-019** (unwanted): If a host extension fails at runtime, then the system shall degrade to the pre-extension fallback behavior without blocking the session.

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: Declined offer keeps install byte-identical
**Covers:** REQ-001, REQ-002, REQ-004

- GIVEN a project install targeting `--clients pi,opencode`
- WHEN the user declines the parity-extension offer
- THEN the installed file set is byte-identical to today's adapter output
- AND no file appears under the host extensions/plugins directories
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: Accepted Pi offer revives session memory
**Covers:** REQ-006, REQ-007

- GIVEN a Pi install where the user accepted the extension offer
- WHEN a Pi session runs one turn and shuts down
- THEN `.memory-bank/session/*.md` contains the turn with the same v2 schema fields as a Claude Code capture
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: Doctor nudges a bare host
**Covers:** REQ-003

- GIVEN a pi host with the skill installed but no parity extensions
- WHEN `/mb doctor` runs
- THEN the report names the missing extensions and prints the exact install command
<!-- /mb-scenario:3 -->

<!-- mb-scenario:4 -->
### Scenario: update-notify reaches a Pi user
**Covers:** REQ-013

- GIVEN an out-of-date skill and an installed Pi session-memory extension
- WHEN a new Pi session starts
- THEN the ≤3-line update notice with `current -> latest` and the flavor-matched upgrade command is rendered
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: Manifest declares platform limits
**Covers:** REQ-015, REQ-017

- GIVEN a codex adapter install
- WHEN the manifest is written
- THEN `platform_limited` lists statusline and native subagents
- AND a negative test asserts each listed capability is absent with that reason
<!-- /mb-scenario:5 -->
