---
type: feature
topic: goal-driven-autopilot-sprint-6-goal-layer
status: queued
created: 2026-05-23
baseline_commit: a9093ac535d14657d5a808d5a1a67134937d4135
level: sprint
phase_plan: 2026-05-23_feature_goal-driven-autopilot-phase.md
linked_spec: specs/goal-driven-autopilot
tasks: 28-33
depends_on: ["2026-05-23_feature_goal-driven-autopilot-sprint-4-atomic-commit.md"]
parallel_safe: false
---

# Plan: feature — goal-driven-autopilot — Sprint 6: Goal layer + `/goal`

## Context

**Problem:** Skill has no high-level "what are we trying to achieve" artefact. Autopilot (Sprint 7) needs a defined goal to drive its loop.

**Expected result:** Single `goal.md` artefact (active goal) + `goals/done/` archive + slowly-changing `project.md` description. `/goal` command with 5 modes (status / init / set / done / list / refresh). `/goal init` asks 5-6 questions about mission, conventions, architecture constraints, stack notes, out-of-scope, active goal.

**Sprint scope:** spec tasks 28-33.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Spec Task 28 — `scripts/mb-goal.sh`
See `tasks.md` Task 28 — covers init/set/done/list/status/refresh subcommands.

<!-- mb-stage:2 -->
### Stage 2: Spec Task 29 — `commands/goal.md` dispatcher
See `tasks.md` Task 29.

<!-- mb-stage:3 -->
### Stage 3: Spec Task 30 — `/goal init` interactive flow (5-6 questions)
See `tasks.md` Task 30. Questions: mission, conventions, architecture constraints, stack notes, out-of-scope, active goal (last optional if goal.md exists).

<!-- mb-stage:4 -->
### Stage 4: Spec Task 31 — `pipeline.yaml: goals.*` schema
See `tasks.md` Task 31.

<!-- mb-stage:5 -->
### Stage 5: Spec Task 32 — `/mb start` integration
See `tasks.md` Task 32 — one-line goal summary at top of context.

<!-- mb-stage:6 -->
### Stage 6: Spec Task 33 — Documentation (workflows/goal-driven.md + commands/goal.md)
See `tasks.md` Task 33.

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| `/goal init` interactive flow blocks non-TTY runs | M | Each question accepts skip → `<TBD — fill manually>` marker |
| Multiple "active" goals if user edits manually | L | `mb-goal.sh status` surfaces conflict; user resolves |
| Progress % out of sync with checklist | L | Computed on read from `progress_source`, never stored |

## Gate

Sprint 6 complete when:
1. All 6 stages PASS verify.
2. `mb-goal.sh` subcommands all tested.
3. `/goal init` runs 6-question flow with skip-safe markers.
4. `goals.enabled` flag + file-presence activation both work.
5. `/mb start` surfaces active goal when enabled.
6. `docs/workflows/goal-driven.md` + `docs/commands/goal.md` published.
