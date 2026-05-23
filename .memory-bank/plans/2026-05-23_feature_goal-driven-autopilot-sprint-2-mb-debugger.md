---
type: feature
topic: goal-driven-autopilot-sprint-2-mb-debugger
status: pending
created: 2026-05-23
level: sprint
phase_plan: 2026-05-23_feature_goal-driven-autopilot-phase.md
linked_spec: specs/goal-driven-autopilot
tasks: 6-11
depends_on: sprint-1-prompt-overlay
---

# Plan: feature — goal-driven-autopilot — Sprint 2: mb-debugger + `/mb debug`

## Context

**Problem:** When `plan-verifier` returns FAIL, `/mb work` halts and waits for a human. In autopilot (Sprint 7) the first red stage would end the session.

**Expected result:** New `mb-debugger` agent that consumes verifier output + failing test stdout and emits a structured fix-plan; new `/mb debug` command for manual diagnostic; opt-in auto-trigger on verify FAIL.

**Depends on:** Sprint 1 — debugger prompt uses defensive/scope-lock/fail-loudly addons via the new overlay system.

**Sprint scope:** spec tasks 6-11. Detailed DoD lives in `tasks.md`. `/mb work` on this plan reads tasks via `linked_spec` + `tasks: 6-11`.

---

## Stages

This plan delegates execution to `specs/goal-driven-autopilot/tasks.md` tasks 6-11. Stage markers below mirror the task numbers for `/mb work` ranging.

<!-- mb-stage:1 -->
### Stage 1: Spec Task 6 — `agents/mb-debugger.md` prompt
See `tasks.md` Task 6 for DoD and tests.

<!-- mb-stage:2 -->
### Stage 2: Spec Task 7 — `mb-debugger-parse.sh` validator
See `tasks.md` Task 7.

<!-- mb-stage:3 -->
### Stage 3: Spec Task 8 — `commands/debug.md`
See `tasks.md` Task 8.

<!-- mb-stage:4 -->
### Stage 4: Spec Task 9 — `pipeline.yaml: agents.debugger.*` schema
See `tasks.md` Task 9.

<!-- mb-stage:5 -->
### Stage 5: Spec Task 10 — `/mb work` auto-trigger on FAIL
See `tasks.md` Task 10.

<!-- mb-stage:6 -->
### Stage 6: Spec Task 11 — Documentation (debugging.md + commands/debug.md)
See `tasks.md` Task 11.

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Debugger fabricates fix-plans | M | Strict JSON schema; parser non-zero on malformed; `require_confidence: medium` default |
| Auto-trigger loops infinitely | L | `max_cycles` cap (default 3); per-stage counter persisted |
| Manual `/mb debug` confused with `/mb test` | L | Clear docs separation; `/mb test` runs tests, `/mb debug` diagnoses failures |

## Gate

Sprint 2 complete when:
1. All 6 stages PASS verify.
2. `agents/mb-debugger.md` + `scripts/mb-debugger-parse.sh` + `commands/debug.md` shipped.
3. `pipeline.yaml: agents.debugger.*` validated and documented.
4. e2e test: mocked verify FAIL → debugger called → high-confidence fixable → implementer re-dispatched.
5. `docs/workflows/debugging.md` + `docs/commands/debug.md` published.
