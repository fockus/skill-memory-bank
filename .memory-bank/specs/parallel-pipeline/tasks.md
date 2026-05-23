---
type: spec-tasks
topic: parallel-pipeline
status: ready
created: 2026-05-24
linked_design: design.md
linked_requirements: requirements.md
---

# Tasks: Parallel pipeline

Executable task list for traceability. Detailed implementation steps remain in the linked plan file when one exists.

<!-- mb-task:1 -->
### Task 1: Pipeline schema and planner

**Covers:** REQ-140, REQ-141, REQ-144
**Role:** developer

Testing: pytest validates DAG order, cycle rejection, missing phase rejection, and preset expansion.

**DoD:**
- [ ] Planner emits an execution graph for valid configs.
- [ ] Invalid configs fail before dispatch.

<!-- mb-task:2 -->
### Task 2: Executor, worktree lifecycle, and state cache

**Covers:** REQ-142, REQ-143, REQ-144
**Role:** devops

Testing: bats verifies worktree create/reuse/remove and state cache resume behavior.

**DoD:**
- [ ] `/mb run` creates one worktree per plan.
- [ ] State files record wave, phase, item, and gate outcomes.

<!-- mb-task:3 -->
### Task 3: Wave control flow and gates

**Covers:** REQ-141, REQ-142, REQ-144
**Role:** developer

Testing: bats covers successful waves, gate failures, max loops, budget stop, and pivot-on-stagnant.

**DoD:**
- [ ] Subsequent waves do not start after unrecovered failure.
- [ ] Budget and loop hard stops are enforced.

<!-- mb-task:4 -->
### Task 4: Adapter layer and safe model contract

**Covers:** REQ-142, REQ-145, REQ-146
**Role:** architect

Testing: bats verifies Claude/Pi native dispatch, Codex/OpenCode sequential fallback, and rejection of unsafe arbitrary provider commands.

**DoD:**
- [ ] Adapter contract is documented.
- [ ] Unsupported model/provider requests follow `on_model_unsupported` without shelling out unsafely.

<!-- mb-task:5 -->
### Task 5: Multi-plan orchestration and doctor checks

**Covers:** REQ-142, REQ-143, REQ-144
**Role:** developer

Testing: bats verifies multiple plans run in separate worktrees and orphaned state is reported by doctor.

**DoD:**
- [ ] `/mb run plan-a plan-b` emits separate execution states.
- [ ] Orphan worktrees and state files are discoverable.

<!-- mb-task:6 -->
### Task 6: Install, docs, changelog, and smoke tests

**Covers:** REQ-140, REQ-145, REQ-146
**Role:** qa

Testing: e2e smoke validates `/mb run --dry-run` and docs link checks validate examples.

**DoD:**
- [ ] Install ships new command/scripts idempotently.
- [ ] Docs emphasize opt-in behavior and model-provider follow-up boundaries.
