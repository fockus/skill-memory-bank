---
type: sequence-plan
title: "SEQUENCE — Long-running autonomous sessions (goal-driven drive-loop + parallel worktree tracks)"
status: active
priority: HIGH
created: 2026-07-05
owner: Anton Ivanov
depends_on: []
linked_specs: [reviewer-2.0, work-loop-v2, drive-loop, cost-multi-model, parallel-pipeline, parallel-team-execution, dynamic-flow]
parallel_safe: false
---

# SEQUENCE — Long-running autonomous sessions

## Goal (end-state)

A user can hand Memory Bank a **goal** and let it run a **long, autonomous, goal-driven session** that:
drives `analyze-task → route → implement → verify` until `goal-acceptance = 100%` behind the deterministic
firewall; pivots when stagnant and stops for a human on max-cycle; survives context compaction via handoff
capsules; reviews reliably (no dropped blockers); fans big projects out across **parallel git-worktree tracks**
and **parallel in-phase implement**; and controls cost by routing roles to cheaper/pricier models — with three
independent budget/stall/acceptance safeties so it never loops forever or burns an unbounded budget.

**Reconciliation with ADR-1 (dynamic-flow):** all parallelism is built on the existing stateless, agent-invoked
`mb-fanout.sh` — NO standalone daemon/runner. `/mb run` = the host agent starts a wave; fanout spreads tracks
across worktrees, waits, collects. This is the "fold worktree isolation into dynamic-flow templates" path the
roadmap already recommended, so `parallel-pipeline` re-enters scope without reviving the killed Python runner.

## Grounding (verified on disk 2026-07-05)

- dynamic-flow **Phase 1 + Phase 2 are DONE on disk** (`mb-fanout.sh` 549 ln, `mb-flow-verify.sh`,
  `mb-flow-route.sh`, `mb-flow-branch-sink.sh`, 5 route + 6 pattern templates, full bats suites) — but
  `status.md`/`roadmap.md`/`checklist.md` still say "Phase 2 paused/deferred". **Doc drift, not code gap.**
- **handoff-v2 = DONE on disk** (`mb-handoff.sh` + `hooks/mb-pre-compact.sh` + `hooks/mb-session-start-context.sh`,
  Wave 2 2026-06-15). Dropped from scope — it is a *dependency already satisfied*, not work to do.
- **reviewer-2.0 = NOT done** (no `mb-review.sh`, no calibration examples on disk). **work-loop-v2 design depends on it**
  (design L18: pivot needs the calibrated, tests-aware reviewer for a reliable trend signal; L108: work-loop-v2 *extends*
  `mb-review.sh` from S1 to emit `progress_trend`). ⇒ **reviewer-2.0 MUST precede work-loop-v2.**
- work-loop-v2: **G3 (fail-fast default) already shipped** — `on_max_cycles: stop_for_human` is already in
  `references/pipeline.default.yaml`. Remaining: **G1 sprint-contract** + **G2 trend/pivot**. 0 trend/contract/pivot scripts.
- cost-multi-model / parallel-pipeline / parallel-team-execution: **0 code on disk** (no `/mb run`, no model-alias resolver).
- dynamic-flow **Phase 3** open: Task 13 (`adapters/{pi,opencode}.sh` sub-invoke + `flow-templates/` in install
  payload — `mb-subinvoke-resolve.sh` already has the `pi`/`opencode` extension point) and Task 14
  (`critique`/`risk-find`/`final-report` skills).
- Parallel infra groundwork exists: I-094 (`mb-work-slots.sh`, per-run state/budget in `mb-work-state.sh`,
  `mb-work-progress-append.sh`) is Draft — Phase 4 builds on it, not from scratch.

## Global gate (every phase)

TDD (failing test first) → implementation → `mb-flow-verify.sh` green → governed review (mb-reviewer + codex-reviewer)
→ mb-judge GO/GO_WITH_BACKLOG → commit. Byte-identical additive migration: no `goal.md` / no `mode: adaptive` ⇒
today's behaviour unchanged. All net-new check runners stay exit-0 + JSON; fail-loud only in the fan-out + severity-gate.

---

## Phase 0 — Fix doc drift (no code)  ·  ~30 min

**Why first:** the roadmap/status lie about dynamic-flow Phase 2; every later phase reads these as SSOT.

**DoD:**
- [ ] `status.md`, `roadmap.md` reflect dynamic-flow Phase 2 = DONE (fanout + patterns + routes shipped).
- [ ] `checklist.md` drops/marks the superseded `goal-driven-autopilot` sprint rows (W5–W11) as superseded.
- [ ] `progress.md` gets one append-only entry recording the Phase-2-done reconciliation + this SEQUENCE start (new I-NNN).
- [ ] `mb-drift.sh <repo>` is clean (or only pre-existing unrelated warnings).

## Phase 1 — reviewer-2.0 (S1, the foundation)  ·  spec: `specs/reviewer-2.0`  ·  ✅ DONE 2026-07-05

**Status: COMPLETE (6/6 tasks, commits 45737fb·9d0a2e1·113b9b5·7e3604a·1ac1c49·7fb3db4).** Governed cycle throughout
(implement=sonnet · review=codex gpt-5.5 · judge=opus). Cross-model review caught 2 real security issues (rubric
path-traversal + symlink exfil to external LLM, Task 2) and a strict-mode severity-gate count-lie bypass (Task 5)
that internal review + `--external` repro missed. Deliverables: `mb-review.sh` + `mb-review-cache.sh` +
`mb-review-examples.sh` (path/symlink-safe layered loader) + 7 `references/rubric-examples/*.md` +
`--require-tests-blocker` REQ-103 safety net (wired into `commands/work.md` 5d + `agents/mb-reviewer.md`) +
`tests/calibration/` golden suite. Backlog: I-095/I-096/I-097/I-098.


**Why first:** work-loop-v2's trend/pivot signal is only reliable on a calibrated, tests-aware reviewer, and work-loop-v2
*extends* the `mb-review.sh` this phase creates (work-loop-v2 design L18/L108). Autonomous drive (Phase 3) must not trust a
lying review, so the reliable reviewer is the base of the whole stack.

Deterministic payload assembly (REQ-100) · layered calibration examples, project > bundled (REQ-101) · touched-file test
status in the payload (REQ-102) · **pre-injected blocker finding the reviewer output cannot drop** (REQ-103) · calibration
suite that detects reviewer verdict drift (REQ-104) · default severity-gate behaviour unchanged unless opted in (REQ-105).

**DoD:** `mb-review.sh` exists (payload assembly + `progress_trend` hook point for Phase 2); calibration examples layered;
failing touched-file tests force an undroppable blocker; calibration suite runs; existing review tests stay green. TDD-first.

## Phase 2 — work-loop-v2 (S2, the smart cycle)  ·  spec: `specs/work-loop-v2` (Tasks 1–5)

Builds on Phase 1's reviewer. **G3 (fail-fast default) already shipped** (`on_max_cycles: stop_for_human` in
`pipeline.default.yaml`) — this phase delivers **G1 + G2**:
- **G1 sprint-contract** (REQ-110): `mb-work-contract.sh` + `templates/contract.md`; `mb-reviewer` gains `review_mode: contract`;
  opt-in `--contract` / `require_contract`.
- **G2 trend + pivot** (REQ-111/112/114): `mb-work-trend.sh` (weighted-score `improving/stagnant/regressing`);
  `pivot_in_role` → `pivot_via_architect` on `pivot_after_cycles`; loop telemetry `pivot-log.jsonl`.
- **Reuse, don't duplicate:** the cycle counter is `mb-work-state.sh` (I-093), NOT a second counter; `progress_trend` is the
  same SSOT as dynamic-flow `stall_count` in the `mb-flow` fence (design §Alignment). max-cycle policy already lands via G3.

**DoD:** Tasks 1–5 DoD met; bats for trend (improving/stagnant/regressing) + contract + pivot; existing work-loop tests green.

## Phase 3 — drive-loop (`/mb drive`)  ·  NEW mini-spec (I author it, Opus)

The thin self-driving wrapper over the firewall + Phase 2. Loop: analyze-task → route → implement → `mb-flow-verify.sh`
→ {green+goal100%→STOP done · green+goal<100%→next item · red→repair · exit2→STOP human} → trend/stall→pivot →
max-cycle/stall-after-pivot→STOP human → budget pre-check before every wave.

**DoD:**
- [ ] `/mb drive <goal>` command + `mb-drive.sh` orchestration (agent-invoked, stateless; no daemon).
- [ ] Three deterministic stops proven by bats: goal-acceptance=100%+green; max_cycles/stall; budget-exceeded / exit2.
- [ ] Reuses `mb-flow-verify.sh` (done-gate), work-loop-v2 (pivot/trend/stall), `mb-work-budget.sh` (budget) — no new done authority.
- [x] Mini-spec authored (Opus, 2026-07-05): `specs/drive-loop/` (requirements+design+tasks, EARS+spec-validate green, 5 mb-tasks).

## Phase 4 — Parallel execution (the "big projects in parallel" ask)

**4a — parallel-pipeline** (`specs/parallel-pipeline`): `/mb run` opt-in, `/mb work` untouched (REQ-140) · DAG validate,
reject cycles (REQ-141) · waves via adapter (REQ-142) · **one git worktree per plan** (REQ-143) · gates+loop+budget
per wave (REQ-144) · cross-agent dispatch + sequential fallback (REQ-145). **Built on `mb-fanout.sh`, not a new runner.**

**4b — parallel-team-execution** (`specs/parallel-team-execution`): parallel *implement inside a phase* — N role-agents
concurrently (mode A ephemeral subagents / mode B native Team) · orchestrator selects pattern by scope · deterministic
verifier gates completion (not agent self-assessment).

**DoD:** worktree isolation proven (two tracks, no cross-write); DAG rejects a cycle; a wave halts on red gate / over-budget;
parallel implement writes disjoint files and re-converges through the firewall.

## Phase 5 — cost-multi-model + dynamic-flow Phase 3

**cost-multi-model** (`specs/cost-multi-model`): central role→alias resolver (REQ-130) · bundled aliases updatable
without editing role prompts (REQ-131) · project override without clobber-on-upgrade (REQ-132) · host-without-model-param
fallback + log (REQ-133).

**dynamic-flow Phase 3** (`specs/dynamic-flow` Tasks 13–14): `adapters/{pi,opencode}.sh` sub-invoke arms +
`flow-templates/` into install payload + native-feature preference + sequential+WARN fallback; `critique`/`risk-find`/
`final-report` skills.

**DoD:** each role resolves its model via one script; pi/opencode fan out via mb-fanout; install payload ships flow-templates;
the 3 composable skills exist without duplicating role-agents/mb-reviewer.

## Phase 6 — Documentation (explicit user ask)  ·  the "how to use all of this" guide

- [ ] One end-to-end guide (`references/long-running-sessions.md` or `docs/`): goal → `/mb goal` → `/mb flow`/auto-route →
      `/mb drive` (autonomous) → `/mb run` (parallel worktree tracks) → monitoring → where it stops → budget knobs.
- [ ] `SKILL.md` + `README.md` + affected `commands/*.md` updated; `CHANGELOG.md` entry per shipped phase.
- [ ] A worked example: drive a real multi-item goal to green, then a 2-track parallel `/mb run`.

---

## Risks

| Risk | Mitigation |
|---|---|
| `parallel-pipeline` misread as reviving the killed runner | Build strictly on `mb-fanout.sh` (stateless, agent-invoked); contract test: no cross-invocation state |
| drive-loop burns budget on a flaky check | `mb-work-budget.sh` pre-check before every wave + max_cycles + stall→pivot→stop-for-human |
| Autonomous loop trusts a lying review | Phase 3 (reviewer-2.0) is a dependency of trusting drive-loop on real code — sequenced before Phase 4 scale-out |
| Long session outlives context window | handoff-v2 capsule (Phase 3) before Phase 4 parallelism multiplies session length |
| Worktree track collision on shared files | per-track worktree (REQ-143) + DAG `depends_on` ordering; disjoint-file assertion in parallel implement |
| Scope creep across 7 specs | strict phase gates; each phase commits independently and is self-valuable; docs (Phase 6) last |
