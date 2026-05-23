---
type: spec-requirements
topic: cost-multi-model
status: ready
created: 2026-05-24
linked_design: design.md
linked_tasks: tasks.md
---

# Requirements: Cost multi-model role assignment

EARS-validated functional requirements. Every REQ bullet is one line.

## Functional Requirements (EARS)

- **REQ-130** The skill shall resolve a model alias for each role through a central script.
- **REQ-131** The skill shall provide bundled model aliases that can be updated without editing role prompts.
- **REQ-132** The skill shall allow project-level model overrides without overwriting user-owned configuration on upgrade.
- **REQ-133** Where a host does not support an explicit model parameter, the skill shall fall back to the host default and log the decision.

## Constraints

- All new behavior must preserve existing defaults unless the linked design explicitly states a v5 major-version gate.
- Tests must be written before implementation for deterministic scripts and validators.
