---
type: spec-requirements
topic: work-loop-v2
status: ready
created: 2026-05-24
linked_design: design.md
linked_tasks: tasks.md
---

# Requirements: Work loop 2.0

EARS-validated functional requirements. Every REQ bullet is one line.

## Functional Requirements (EARS)

- **REQ-110** The skill shall create an explicit sprint contract before implementation when contract mode is enabled.
- **REQ-111** The reviewer shall emit a progress trend signal that the work loop can consume.
- **REQ-112** When progress is stagnant for the configured number of cycles, the skill shall pivot through the configured role or architect route.
- **REQ-113** If max review cycles are reached, the skill shall stop for a human by default in v5 and preserve existing v4 project settings unless explicitly changed.
- **REQ-114** The skill shall record loop telemetry sufficient to debug pivot and max-cycle decisions.

## Constraints

- All new behavior must preserve existing defaults unless the linked design explicitly states a v5 major-version gate.
- Tests must be written before implementation for deterministic scripts and validators.
