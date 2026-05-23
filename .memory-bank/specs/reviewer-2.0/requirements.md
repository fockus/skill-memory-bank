---
type: spec-requirements
topic: reviewer-2.0
status: ready
created: 2026-05-24
linked_design: design.md
linked_tasks: tasks.md
---

# Requirements: Reviewer 2.0

EARS-validated functional requirements. Every REQ bullet is one line.

## Functional Requirements (EARS)

- **REQ-100** The skill shall assemble reviewer payloads deterministically before invoking the reviewer agent.
- **REQ-101** The skill shall load layered calibration examples with project examples taking precedence over bundled examples.
- **REQ-102** The skill shall include current touched-file test status in reviewer payloads.
- **REQ-103** When touched-file tests fail, the skill shall pre-inject a blocker test finding that the reviewer output cannot drop.
- **REQ-104** The skill shall provide a runnable calibration suite that detects reviewer verdict drift.
- **REQ-105** The skill shall keep default review severity-gate behavior compatible unless the user opts in to new settings.

## Constraints

- All new behavior must preserve existing defaults unless the linked design explicitly states a v5 major-version gate.
- Tests must be written before implementation for deterministic scripts and validators.
