---
type: feature
topic: goal-driven-autopilot-phase
status: active
created: 2026-05-23
level: phase
linked_spec: specs/goal-driven-autopilot
sprints:
  - 2026-05-23_feature_goal-driven-autopilot-sprint-1-prompt-overlay.md
  - 2026-05-23_feature_goal-driven-autopilot-sprint-2-mb-debugger.md
  - 2026-05-23_feature_goal-driven-autopilot-sprint-3-worktree.md
  - 2026-05-23_feature_goal-driven-autopilot-sprint-4-atomic-commit.md
  - 2026-05-23_feature_goal-driven-autopilot-sprint-5-parallel-waves.md
  - 2026-05-23_feature_goal-driven-autopilot-sprint-6-goal-layer.md
  - 2026-05-23_feature_goal-driven-autopilot-sprint-7-autopilot.md
---

# Plan: feature — goal-driven-autopilot (Phase roadmap)

## Context

**Problem:** Skill needs to be capable of executing a user-defined goal end-to-end with minimal supervision, while staying token-economical and preserving the inviolable memory subsystem.

**Expected result:** 8 new components delivered behind opt-in flags so that default behaviour is byte-identical to today; autopilot mode that runs to a goal with auto-recovery via mb-debugger.

**Related artefacts:**
- Spec: `.memory-bank/specs/goal-driven-autopilot/{design,requirements,tasks}.md`
- Design principles: `references/design-principles.md`
- Docs scaffolding: `docs/README.md`, `docs/concepts/overview.md`

---

## Sprint roadmap

7 sprints. Dependency-ordered. Each sprint = one plan file (this folder). Each plan file is a thin wrapper that delegates execution to `specs/goal-driven-autopilot/tasks.md` via `linked_spec` + `tasks` frontmatter.

| # | Sprint plan | Component | Tasks (from spec) | Depends on | Risk |
|---|-------------|-----------|-------------------|------------|------|
| 1 | `*sprint-1-prompt-overlay.md` | C7: Overlay system + addons | 1-5 | — | Low |
| 2 | `*sprint-2-mb-debugger.md` | C3: mb-debugger + `/mb debug` | 6-11 | Sprint 1 | Low |
| 3 | `*sprint-3-worktree.md` | C2: Worktree isolation | 12-15 | — | Med |
| 4 | `*sprint-4-atomic-commit.md` | C5: Atomic commit per stage | 16-20 | — | Low |
| 5 | `*sprint-5-parallel-waves.md` | C4: Parallel waves (DAG) | 21-27 | — | Med |
| 6 | `*sprint-6-goal-layer.md` | C1: Goal layer + `/goal` | 28-33 | — | Low |
| 7 | `*sprint-7-autopilot.md` | C6: Autopilot loop | 34-39 | All previous | High |

**Execution order rationale:**
- Sprint 1 first: low risk, improves every subsequent dispatch via overlay + addons.
- Sprint 2 next: builds on Sprint 1's addons (debugger uses them in its prompt).
- Sprints 3, 4, 5, 6: independent of each other — can be parallelised across sessions if multiple developers work the spec. For solo work, ordered by risk (low → med).
- Sprint 7 last: consumes everything else.

---

## Stages (one stage per sprint)

> Each stage = one sprint plan file. Detail lives in the sprint plan itself + `tasks.md` blocks. `/mb work` on this phase plan iterates sprint plans in order.

<!-- mb-stage:1 -->
### Stage 1: Sprint 1 — Prompt overlay + addons

**Plan:** `plans/2026-05-23_feature_goal-driven-autopilot-sprint-1-prompt-overlay.md`

**DoD:**
- [ ] Sprint 1 plan closed (all tasks PASS, plan moved to `plans/done/`).
- [ ] Overlay resolver + 4 addons shipped; addon catalogue indexed.
- [ ] `pipeline.yaml: agents.preamble_addons` validated; default empty.
- [ ] Golden-snapshot test confirms byte-identical dispatch when no addons + no overlay.
- [ ] `docs/concepts/overlay-system.md` published.

**Code rules:** SOLID, DRY, KISS, YAGNI, Testing Trophy.

<!-- mb-stage:2 -->
### Stage 2: Sprint 2 — mb-debugger + `/mb debug`

**Plan:** `plans/2026-05-23_feature_goal-driven-autopilot-sprint-2-mb-debugger.md`

**DoD:**
- [ ] Sprint 2 plan closed.
- [ ] `agents/mb-debugger.md` + `mb-debugger-parse.sh` + `commands/debug.md` shipped.
- [ ] `agents.debugger.*` config validated; auto-trigger on verify FAIL works behind flag.
- [ ] `docs/workflows/debugging.md` + `docs/commands/debug.md` published.

**Code rules:** SOLID, DRY, KISS, YAGNI.

<!-- mb-stage:3 -->
### Stage 3: Sprint 3 — Worktree isolation

**Plan:** `plans/2026-05-23_feature_goal-driven-autopilot-sprint-3-worktree.md`

**DoD:**
- [ ] Sprint 3 plan closed.
- [ ] `mb-work-worktree.sh` shipped with all subcommands.
- [ ] `execution.use_worktree` enum validated.
- [ ] `/mb work` honours worktree mode; cleanup options work.
- [ ] `docs/features/worktree-isolation.md` published.

**Code rules:** SOLID, DRY, KISS, YAGNI.

<!-- mb-stage:4 -->
### Stage 4: Sprint 4 — Atomic commit per stage

**Plan:** `plans/2026-05-23_feature_goal-driven-autopilot-sprint-4-atomic-commit.md`

**DoD:**
- [ ] Sprint 4 plan closed.
- [ ] Stage-SHA snapshot + template renderer + 4 safety gates reused.
- [ ] `execution.auto_commit_code: stage` produces exactly one commit per PASS stage.
- [ ] `docs/features/atomic-commit.md` published.

**Code rules:** SOLID, DRY, KISS, YAGNI.

<!-- mb-stage:5 -->
### Stage 5: Sprint 5 — Parallel waves (DAG)

**Plan:** `plans/2026-05-23_feature_goal-driven-autopilot-sprint-5-parallel-waves.md`

**DoD:**
- [ ] Sprint 5 plan closed.
- [ ] `depends_on` marker parsing + DAG construction + wave emission.
- [ ] `/mb work --parallel` dispatches waves; budget-aware fallback.
- [ ] File-conflict guard surfaces warnings.
- [ ] `docs/features/parallel-waves.md` published.

**Code rules:** SOLID, DRY, KISS, YAGNI.

<!-- mb-stage:6 -->
### Stage 6: Sprint 6 — Goal layer + `/goal`

**Plan:** `plans/2026-05-23_feature_goal-driven-autopilot-sprint-6-goal-layer.md`

**DoD:**
- [ ] Sprint 6 plan closed.
- [ ] `mb-goal.sh` + `commands/goal.md` shipped.
- [ ] `/goal init` runs 5-6 question flow with skip-safe markers.
- [ ] `goals.enabled` flag activates layer; file-presence also activates.
- [ ] `docs/workflows/goal-driven.md` + `docs/commands/goal.md` published.

**Code rules:** SOLID, DRY, KISS, YAGNI.

<!-- mb-stage:7 -->
### Stage 7: Sprint 7 — Autopilot loop

**Plan:** `plans/2026-05-23_feature_goal-driven-autopilot-sprint-7-autopilot.md`

**DoD:**
- [ ] Sprint 7 plan closed.
- [ ] Autopilot driver refuses to start without prerequisites.
- [ ] Goal-aware loop iterates pending items, auto-recovers via mb-debugger.
- [ ] All hard stops wired and surface with `[autopilot-halt]` lines.
- [ ] `docs/workflows/autopilot.md` published.
- [ ] End-to-end test: 3-stage plan runs autonomously to completion.

**Code rules:** SOLID, DRY, KISS, YAGNI.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Phase too large, drift between sprints | M | Spec is source of truth; sprint plans are thin wrappers; traceability matrix regenerated on save |
| Sprint 1 lands but no one consumes it | L | Sprint 2 directly depends on Sprint 1 — naturally exercises overlay |
| Sprint 7 reveals issues in earlier sprints | M | Each sprint ships with autopilot-relevant e2e test (skipped/xfail until Sprint 7) |
| Token economy regressions | M | NFR-001/NFR-002 golden snapshots in every sprint; CI gate on baseline |
| `pipeline.yaml` schema churn breaks user configs | L | All new fields opt-in with defaults preserving prior behaviour |
| Documentation falls behind code | M | Every sprint's DoD requires its docs page; `/mb verify` checks |

## Gate (phase success criterion)

Phase is considered complete when all 7 sprint plans are closed AND:

1. Every REQ-NNN / NFR-NNN in `requirements.md` mapped to ≥1 PASS test (verified by `mb-traceability-gen.sh`).
2. Default-off regression suite green on a representative plan + spec.
3. End-to-end autopilot test green: 3-stage plan runs autonomously from `/goal init` through `/goal done` with mb-debugger recovery exercised at least once.
4. `CHANGELOG.md` documents the goal-driven-autopilot release with opt-in instructions.
5. `docs/README.md` "Coming as part of the goal-driven-autopilot spec" section converted to live links (no `*(coming)*` markers left).
