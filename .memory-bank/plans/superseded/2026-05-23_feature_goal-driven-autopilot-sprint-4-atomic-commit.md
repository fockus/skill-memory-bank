---
type: feature
topic: goal-driven-autopilot-sprint-4-atomic-commit
status: queued
created: 2026-05-23
baseline_commit: a9093ac535d14657d5a808d5a1a67134937d4135
level: sprint
phase_plan: 2026-05-23_feature_goal-driven-autopilot-phase.md
linked_spec: specs/goal-driven-autopilot
tasks: 16-20
depends_on: ["2026-05-23_feature_goal-driven-autopilot-sprint-2-mb-debugger.md"]
parallel_safe: false
---

# Plan: feature — goal-driven-autopilot — Sprint 4: Atomic commit per stage

## Context

**Problem:** `mb-auto-commit.sh` only commits `.memory-bank/` after `/mb done`. Source code isn't auto-committed per stage, so long autopilot sessions accumulate monolithic dirty diffs with no rollback granularity.

**Expected result:** One git commit per PASS stage, gated by 4 safety gates (clean start, no protected paths, no private content, tests pass via verify PASS). Commit message + trailers configurable through `pipeline.yaml` template.

**Sprint scope:** spec tasks 16-20.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Spec Task 16 — Template renderer + stage SHA snapshot
See `tasks.md` Task 16.

<!-- mb-stage:2 -->
### Stage 2: Spec Task 17 — Safety gates shared library
See `tasks.md` Task 17.

<!-- mb-stage:3 -->
### Stage 3: Spec Task 18 — `/mb work` step 3g integration
See `tasks.md` Task 18.

<!-- mb-stage:4 -->
### Stage 4: Spec Task 19 — `pipeline.yaml: execution.auto_commit_code` schema
See `tasks.md` Task 19.

<!-- mb-stage:5 -->
### Stage 5: Spec Task 20 — Documentation (atomic-commit.md)
See `tasks.md` Task 20.

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Stage commit picks up unrelated files | L | `-A` limited to files changed since `STAGE_START_SHA` only |
| Private content leaks via commit | L | Gate 3 scans staged diff for `<private>` markers |
| Re-run of same stage creates duplicate commit | L | Idempotency check; surface "already committed at sha XYZ" |

## Gate

Sprint 4 complete when:
1. All 5 stages PASS verify.
2. Template renderer covers all standard placeholders.
3. 4 safety gates extracted to shared library; both callers reuse.
4. e2e test: PASS stage → one commit with expected trailers; empty diff → skipped; FAIL → no commit.
5. `docs/features/atomic-commit.md` published.
