---
type: feature
topic: goal-driven-autopilot-sprint-5-parallel-waves
status: pending
created: 2026-05-23
level: sprint
phase_plan: 2026-05-23_feature_goal-driven-autopilot-phase.md
linked_spec: specs/goal-driven-autopilot
tasks: 21-27
---

# Plan: feature — goal-driven-autopilot — Sprint 5: Parallel waves (DAG)

## Context

**Problem:** `/mb work` is strictly sequential. Independent stages run one-by-one even when they have no shared state.

**Expected result:** Opt-in DAG-based parallel dispatch via `<!-- mb-stage:N depends_on:[1,2] -->` markers. `/mb work --parallel` groups items into waves; same-wave items dispatch in one Task batch. File-conflict guard surfaces collisions. Budget-aware fallback to sequential.

**Sprint scope:** spec tasks 21-27.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Spec Task 21 — Extend marker parser with `depends_on`
See `tasks.md` Task 21.

<!-- mb-stage:2 -->
### Stage 2: Spec Task 22 — `scripts/mb-work-dag.sh`
See `tasks.md` Task 22.

<!-- mb-stage:3 -->
### Stage 3: Spec Task 23 — `mb-work-plan.sh` wave assignment
See `tasks.md` Task 23.

<!-- mb-stage:4 -->
### Stage 4: Spec Task 24 — `--parallel` dispatch + file-conflict guard
See `tasks.md` Task 24.

<!-- mb-stage:5 -->
### Stage 5: Spec Task 25 — Budget-aware sequential fallback
See `tasks.md` Task 25.

<!-- mb-stage:6 -->
### Stage 6: Spec Task 26 — `pipeline.yaml: execution.parallel_waves` schema
See `tasks.md` Task 26.

<!-- mb-stage:7 -->
### Stage 7: Spec Task 27 — Documentation (parallel-waves.md)
See `tasks.md` Task 27.

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Parallel items write to same file | M | Pre-wave overlap warning; per-item snapshot; user owns `depends_on` |
| Main context bloat from parallel Task replies | M | Documented limitation; users can split into more waves |
| DAG cycle detection misses subtle cases | L | Topological sort raises on remaining nodes; tested with adversarial graphs |

## Gate

Sprint 5 complete when:
1. All 7 stages PASS verify.
2. Parser handles old + new markers; cycle/forward-ref detection works.
3. `mb-work-plan.sh` emits `wave` field; `mb-work-dag.sh` produces ASCII + JSON.
4. e2e test: 3-item wave dispatches in one message; budget fallback to sequential verified.
5. File-conflict guard surfaces collisions without halting wave.
6. `docs/features/parallel-waves.md` published.
