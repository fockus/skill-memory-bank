---
type: spec-requirements
topic: parallel-pipeline
status: ready
created: 2026-05-24
linked_design: design.md
linked_tasks: tasks.md
---

# Requirements: Parallel pipeline

EARS-validated functional requirements. Every REQ bullet is one line.

## Functional Requirements (EARS)

- **REQ-140** The skill shall keep existing `/mb work` behavior unchanged while adding `/mb run` as an opt-in command.
- **REQ-141** The skill shall validate a pipeline DAG before execution and reject cycles or missing phase references.
- **REQ-142** The skill shall execute independent items in waves using an adapter abstraction.
- **REQ-143** The skill shall isolate each plan in its own worktree during `/mb run`.
- **REQ-144** The skill shall enforce gates, loop limits, and budget limits before advancing waves.
- **REQ-145** The skill shall support cross-agent dispatch with sequential fallback where native parallelism is unavailable.
- **REQ-146** The skill shall defer arbitrary external provider execution to a separate model-dispatch follow-up unless the provider is represented by a safe adapter contract.

## Constraints

- All new behavior must preserve existing defaults unless the linked design explicitly states a v5 major-version gate.
- Tests must be written before implementation for deterministic scripts and validators.
