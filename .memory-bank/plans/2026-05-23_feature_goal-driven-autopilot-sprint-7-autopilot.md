---
type: feature
topic: goal-driven-autopilot-sprint-7-autopilot
status: pending
created: 2026-05-23
level: sprint
phase_plan: 2026-05-23_feature_goal-driven-autopilot-phase.md
linked_spec: specs/goal-driven-autopilot
tasks: 34-39
depends_on: sprint-1, sprint-2, sprint-3, sprint-4, sprint-5, sprint-6
---

# Plan: feature — goal-driven-autopilot — Sprint 7: Autopilot loop

## Context

**Problem:** Even with all isolation/recovery infrastructure in place, the user still has to drive `/mb work` manually stage by stage. Long goals require unattended execution.

**Expected result:** `/mb work --autopilot` runs the active goal's linked plan/spec to completion. On verify FAIL → auto-recovery via mb-debugger. Hard stops: max_iterations, max_stall_iterations, budget, protected paths, context guard. Refuses to start without prerequisites (debugger enabled, goal active).

**Depends on:** Sprints 1-6 (autopilot consumes overlay system, mb-debugger, optionally worktree + atomic-commit, parallel waves, goal layer).

**Sprint scope:** spec tasks 34-39.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Spec Task 34 — Autopilot driver with startup checks
See `tasks.md` Task 34.

<!-- mb-stage:2 -->
### Stage 2: Spec Task 35 — Goal-aware loop + iteration counters
See `tasks.md` Task 35.

<!-- mb-stage:3 -->
### Stage 3: Spec Task 36 — Hard-stop integration
See `tasks.md` Task 36.

<!-- mb-stage:4 -->
### Stage 4: Spec Task 37 — Auto-recovery via mb-debugger inside loop
See `tasks.md` Task 37.

<!-- mb-stage:5 -->
### Stage 5: Spec Task 38 — `pipeline.yaml: execution.autopilot.*` schema
See `tasks.md` Task 38.

<!-- mb-stage:6 -->
### Stage 6: Spec Task 39 — Documentation (workflows/autopilot.md)
See `tasks.md` Task 39.

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Autopilot drifts off goal | M | `max_stall_iterations` halt; acceptance re-check every iteration |
| Hard stops conflict / race | M | Each hard stop surfaces unique `[autopilot-halt] reason=` line; first stop wins |
| User cancels mid-run, leaves dirty state | M | Worktree mode (Sprint 3) recommended; atomic commit (Sprint 4) checkpoints recovery |
| Budget exhaustion mid-stage | L | `sprint_context_guard` hard-stops; existing `--budget` machinery applies |
| Goal completion check loop | L | Acceptance reads are idempotent; goal marked done only once |

## Gate

Sprint 7 complete when:
1. All 6 stages PASS verify.
2. Autopilot driver refuses to start without `agents.debugger.enabled` + active goal.
3. e2e test: 3-stage plan runs to completion with one mb-debugger recovery exercised.
4. All 5 hard stops verified independently.
5. `docs/workflows/autopilot.md` published.
6. **Phase gate:** all 7 sprints closed; `docs/README.md` "Coming as part of the goal-driven-autopilot spec" section converted to live links; CHANGELOG entry for the full goal-driven-autopilot release.
