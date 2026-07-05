---
type: spec-tasks
topic: work-loop-v2
status: ready
created: 2026-05-24
linked_design: design.md
linked_requirements: requirements.md
---

# Tasks: Work loop 2.0

Executable task list for traceability. Detailed implementation steps remain in the linked plan file when one exists.

<!-- mb-task:1 -->
### Task 1: Trend calculator and verdict cache

**Covers:** REQ-111, REQ-114
**Role:** developer

Testing: bats verifies improving, stagnant, and regressing verdict histories.

**DoD:**
- [x] Trend helper emits `improving`, `stagnant`, or `regressing`.
- [x] Previous verdict cache is keyed by plan and stage.

<!-- mb-task:2 -->
### Task 2: Contract phase script and reviewer contract mode

**Covers:** REQ-110
**Role:** architect

Testing: bats validates contract creation, idempotent reread, and scope-lock fields.

**DoD:**
- [x] Contract file contains in-scope, out-of-scope, test plan, and DoD checkpoints.
- [x] Reviewer contract mode returns structured JSON.

<!-- mb-task:3 -->
### Task 3: Pivot dispatch routes

**Covers:** REQ-112, REQ-114
**Role:** developer

Testing: bats stubs stagnant cycles and verifies `pivot_in_role` and `pivot_via_architect` dispatch decisions.

**DoD:**
- [x] Pipeline keys select the pivot route.
- [x] Pivot decisions are written to loop telemetry.

<!-- mb-task:4 -->
### Task 4: Max-cycle policy migration

**Covers:** REQ-113
**Role:** developer

Testing: pytest validates default resolution for new configs and backward-compatible handling for existing configs.

**DoD:**
- [x] v4 existing `pipeline.yaml` files are not rewritten.
- [x] v5 default policy is documented as `stop_for_human`.

<!-- mb-task:5 -->
### Task 5: Wire loop docs and changelog

**Covers:** REQ-110, REQ-111, REQ-112, REQ-113, REQ-114
**Role:** analyst

Testing: bats verifies command docs mention contract, trend, pivot, and max-cycle policy.

**DoD:**
- [ ] `commands/work.md`, docs, and `CHANGELOG.md` are updated.
- [ ] Existing work-loop tests remain green.
