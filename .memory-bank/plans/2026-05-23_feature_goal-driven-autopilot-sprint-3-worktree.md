---
type: feature
topic: goal-driven-autopilot-sprint-3-worktree
status: pending
created: 2026-05-23
level: sprint
phase_plan: 2026-05-23_feature_goal-driven-autopilot-phase.md
linked_spec: specs/goal-driven-autopilot
tasks: 12-15
---

# Plan: feature — goal-driven-autopilot — Sprint 3: Worktree isolation

## Context

**Problem:** `/mb work` currently shurudits in the current tree. For autopilot / long-running sessions this risks dirty baseline, blocks parallel `/mb work` invocations, makes abort messy.

**Expected result:** Opt-in worktree-isolated execution via `git worktree add` into `~/.cache/memory-bank/worktrees/<project-hash>/<plan-slug>/`. Auto mode reserves worktrees for `--autopilot`; always mode for every `/mb work`.

**Sprint scope:** spec tasks 12-15.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Spec Task 12 — `scripts/mb-work-worktree.sh`
See `tasks.md` Task 12 — covers ensure/status/path/remove/clean subcommands + safety refusals.

<!-- mb-stage:2 -->
### Stage 2: Spec Task 13 — `pipeline.yaml: execution.use_worktree` schema
See `tasks.md` Task 13.

<!-- mb-stage:3 -->
### Stage 3: Spec Task 14 — `/mb work` CWD wiring + cleanup
See `tasks.md` Task 14.

<!-- mb-stage:4 -->
### Stage 4: Spec Task 15 — Documentation (worktree-isolation.md)
See `tasks.md` Task 15.

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Worktrees leak disk space | L | `mb-work-worktree.sh clean` available; documented in workflow doc |
| Windows path semantics break | M | v1 documents Unix-only support; Windows best-effort |
| `worktree_cleanup: merge` conflicts | M | Cleanup is fast-forward only; conflict → keep worktree, surface to user |

## Gate

Sprint 3 complete when:
1. All 4 stages PASS verify.
2. `mb-work-worktree.sh` covers all subcommands; safety refusals work.
3. `execution.use_worktree` accepts off/auto/always.
4. e2e test: `auto` mode creates worktree only for `--autopilot`.
5. `docs/features/worktree-isolation.md` published.
