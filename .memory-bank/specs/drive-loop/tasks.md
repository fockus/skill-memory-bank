---
type: spec-tasks
topic: drive-loop — autonomous goal-driven session driver over the firewall
status: ready
created: 2026-07-05
linked_design: design.md
linked_requirements: requirements.md
depends_on_specs: [dynamic-flow, work-loop-v2, reviewer-2.0]
---

# Tasks: drive-loop

Executable list. TDD-first; determinism lives in `mb-drive.sh`; success is gated by the firewall, never self-assessment.
Reuse existing assets — no second done-authority, cycle counter, trend calculator, or budget gate. Prereqs on disk:
`mb-flow-verify.sh`, `mb-goal-acceptance.sh`, `mb-flow-route.sh`, `mb-work-state.sh`, `mb-work-budget.sh`,
`mb-work-review-parse.sh` (all present); work-loop-v2 trend/pivot (Phase 2) must land before Task 3's pivot branch is live.

<!-- mb-task:1 -->
### Task 1: `mb-drive.sh next` — stateless decision function

**Covers:** REQ-DR-002, REQ-DR-010, REQ-DR-011, REQ-DR-012, REQ-DR-013, REQ-DR-014, REQ-DR-020, REQ-DR-021
**Role:** backend

Testing: bats — one case per decision-table rule (broken-check→stop_human; over-budget→stop_budget; acceptance100%+green→
stop_success; exhausted/stall→stop_human; red+stagnant→pivot; red→repair; <100%→implement) PLUS ordering cases proving a
stop beats progress (e.g. gate==2 while acceptance<100% still yields stop_human, not implement) and pivot beats repair.
Helper holds no cross-invocation state; bash-3.2 clean; shellcheck clean.

**DoD:**
- [x] `scripts/mb-drive.sh next --bank <b>` prints exactly one action from the §"decision function" grammar and exits 0.
- [x] Inputs are read ONLY from existing scripts (`mb-goal-acceptance.sh`, `mb-flow-verify.sh`, `mb-work-state.sh`,
      `mb-work-budget.sh`, normalized verdict) — no recomputation, no new SSOT.
- [x] Decision-table order enforced: stops before progress, pivot before repair (proven by ordering bats).
- [x] `stop_success` is impossible unless firewall exit 0 AND acceptance 100% (REQ-DR-014) — negative bats asserts a
      model-"done" with red firewall never yields stop_success.

<!-- mb-task:2 -->
### Task 2: `/mb drive` command + AGENTS.md loop contract

**Covers:** REQ-DR-001, REQ-DR-003, REQ-DR-030, REQ-DR-031
**Role:** developer

Testing: bats/manual — `/mb drive` with no `goal.md` refuses (exit 1 + fix-hint via `mb-goal-validate.sh`); the rendered
AGENTS.md loop block references only shipped scripts; the contract instructs the agent to dispatch the pipeline-resolved
role-agent (sonnet) for implement/repair/pivot, codex for review, opus for judge, passing exact model/thinking.

**DoD:**
- [ ] `commands/drive.md` wraps `mb-drive.sh`: reads/scaffolds `goal.md`, then documents the "call `next` → execute → repeat"
      loop until a `stop_*` action.
- [ ] `/mb drive` refuses without a resolvable `goal.md` (reuse `mb-goal-validate.sh` failure path), never silently starts.
- [ ] `_lib_agents_md.sh` fenced block carries the drive loop-contract: agent is the runtime, dispatch is sonnet/codex/opus
      from `pipeline.yaml`, never self-certify done.

<!-- mb-task:3 -->
### Task 3: Trend/pivot + route-reeval wiring into the loop

**Covers:** REQ-DR-022, REQ-DR-023
**Role:** developer

Testing: bats — a stagnant trend for `pivot_after_cycles` makes `next` emit `pivot in_role`, escalating to `pivot via_architect`
at the configured cycle; a regressing/stagnant trend triggers an `analyze-task` re-run before the next `implement`; the
`stall_count` read comes from the `mb-flow` fence (work-loop-v2 SSOT), not a new counter.

**DoD:**
- [ ] `next` consumes work-loop-v2's `progress_trend` + `stall_count` from the `mb-flow` fence (no second counter).
- [ ] Stagnant≥`pivot_after_cycles` → `pivot`; escalation to `via_architect` at `pivot_escalate_to_architect_on`.
- [ ] A regressing/stagnant trend re-runs `analyze-task` before emitting the next `implement` (route self-correction).

<!-- mb-task:4 -->
### Task 4: Stop telemetry + Stop-hook resume-gate + parallel keying

**Covers:** REQ-DR-032, REQ-DR-033, REQ-DR-034
**Role:** devops

Testing: bats/manual — each stop writes a one-line reason to the `mb-flow` fence + appends to `progress.md`; on a hookful
host a premature stop with "goal not done AND no stop condition" is blocked and the loop resumes; under `MB_WORK_PARALLEL=1`
the drive per-item state is per-run-keyed (reuse I-094 dirs); on a hookless host the git-hooks fallback catches a no-commit
false-done at commit time.

**DoD:**
- [ ] Stop reason (`success|human:check-broke|human:max-cycle|human:stall|budget`) written to the `mb-flow` fence + appended
      to `progress.md` via `mb-work-progress-append.sh`.
- [ ] CC Stop-hook resume-gate: blocks stop when goal not done AND no stop condition (REQ-DR-032); documented for hookless hosts.
- [ ] `MB_WORK_PARALLEL=1` per-run keys the drive state (reuse I-094); no cross-run contamination (bats).

<!-- mb-task:5 -->
### Task 5: drive-loop docs + wiring

**Covers:** REQ-DR-001, REQ-DR-003
**Role:** analyst

Testing: doc-test — `references/drive-loop.md` links resolve; `commands/goal.md`/`commands/work.md` cross-reference `/mb drive`;
CHANGELOG entry present.

**DoD:**
- [ ] `references/drive-loop.md` covers: the loop, the three deterministic stops, budget/max-cycle knobs, resume-after-kill.
- [ ] `SKILL.md` Tools table + `commands/goal.md` cross-reference `/mb drive`.
- [ ] `CHANGELOG.md` entry under `[Unreleased]`: `/mb drive` autonomous goal-driven driver over the firewall.

## Gate (whole spec)

Ships when: `mb-drive.sh next` emits the correct action for every decision-table rule (bats, incl. ordering + the negative
"no self-done" case), `/mb drive` refuses without a goal, trend/pivot reads the work-loop-v2 SSOT, stops are auditable in the
fence + progress, and a killed drive resumes by re-reading files. Each task: TDD → `mb-flow-verify.sh` green → governed review
(codex) → judge (opus) → done. Depends on Phase 1 (reviewer-2.0) + Phase 2 (work-loop-v2) being green first.
