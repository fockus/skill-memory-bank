---
type: spec-requirements
topic: handoff-v2
status: ready
created: 2026-05-24
linked_design: design.md
linked_tasks: tasks.md
---

# Requirements: Handoff 2.0

EARS-validated functional requirements. Every REQ bullet is one line.

## Functional Requirements (EARS)

- **REQ-120** The skill shall create a fresh handoff capsule before context compaction.
- **REQ-121** When a fresh handoff capsule exists, session start shall include it before older broad context.
- **REQ-122** The skill shall run deterministic done gates before session close.
- **REQ-123** If a done gate fails, the skill shall require an explicit force reason before continuing.
- **REQ-124** The skill shall maintain a progress hash chain that detects append-only tampering.

## Constraints

- All new behavior must preserve existing defaults unless the linked design explicitly states a v5 major-version gate.
- Tests must be written before implementation for deterministic scripts and validators.
