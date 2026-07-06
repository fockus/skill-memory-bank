---
type: spec-requirements
topic: drive-loop — autonomous goal-driven session driver over the firewall
status: ready
created: 2026-07-05
linked_design: design.md
linked_tasks: tasks.md
depends_on_specs: [dynamic-flow, work-loop-v2, reviewer-2.0]
authors: [Anton Ivanov]
---

# Requirements: drive-loop

> EARS patterns: **Ubiquitous** (`The <system> shall <response>`), **Event** (`When <trigger>, the <system> shall <response>`),
> **State** (`While <state>, the <system> shall <response>`), **Optional** (`Where <feature>, the <system> shall <response>`),
> **Unwanted** (`If <condition>, then the <system> shall <response>`). Validate with `mb-ears-validate.sh`.

## Context

Memory Bank has all the parts of a long, autonomous, goal-driven session but no driver that ties them into one loop:
the **firewall** (`mb-flow-verify.sh`, deterministic done-gate), the **router** (`analyze-task` / `mb-flow-route.sh`),
the **goal** primitive (`goal.md` + `mb-goal-acceptance.sh` = `[x]/N`), the **budget** guard (`mb-work-budget.sh`), the
**durable cycle counter + max_cycles** (`mb-work-state.sh`), and — after Phase 2 — **trend/pivot/stall** (work-loop-v2).

The user wants a "ralph-loop": hand it a GOAL and let it run itself to completion. The superseded `goal-driven-autopilot`
Sprint 7 proposed exactly this as an **LLM-only** `--autopilot` loop with an **LLM-only** "done" check — both were
deliberately rejected (they let the model lie about completion). drive-loop is that autopilot **rebuilt over the
deterministic firewall**: the loop keeps iterating, but success is gated by the firewall exit + goal-acceptance, never by
the model's self-assessment.

**Hard constraint — AGENT-NATIVE (inherits dynamic-flow ADR-1/ADR-1′).** drive-loop ships as a stateless decision helper
(`mb-drive.sh`) + a command + an `AGENTS.md` loop contract. The host code-agent IS the runtime: it calls `mb-drive.sh next`,
gets a deterministic action, executes it (dispatch a sonnet role-agent, run the firewall, or stop), and repeats. There is
**no daemon**, no durable-execution journal, no JS/TS runtime, and no process the agent does not itself initiate.

**Reuse, do not reimplement.** Every capability already exists; drive-loop only sequences them and computes the next action.

## Functional Requirements (EARS)

### The driver (L1)

- **REQ-DR-001** (Ubiquitous): The system shall provide a `/mb drive <goal>` entry point that drives the dynamic-flow loop
  over a resolved `goal.md` until a deterministic stop condition is reached.
- **REQ-DR-002** (Ubiquitous): The system shall provide `mb-drive.sh` as a **stateless decision function** that, given the
  current `{goal-acceptance, firewall exit, progress_trend, budget, cycle/max_cycles}`, prints exactly one next action from
  `{implement, repair, pivot, stop_success, stop_human, stop_budget}` and exits — holding no cross-invocation state and
  starting no daemon (ADR-1′).
- **REQ-DR-003** (Ubiquitous): The system shall keep the host code-agent as the runtime: the agent calls `mb-drive.sh next`,
  executes the returned action, then calls it again — the helper never dispatches subagents itself.

### Deterministic stop conditions (L2) — the three safeties

- **REQ-DR-010** (Event): When `mb-goal-acceptance.sh` reports `[x]/N == 100%` AND `mb-flow-verify.sh` exits `0`, the system
  shall return `stop_success` and declare the goal done.
- **REQ-DR-011** (Unwanted): If `mb-flow-verify.sh` exits `2` (a check script itself broke), then the system shall return
  `stop_human` naming the broken check, and shall NOT continue.
- **REQ-DR-012** (Unwanted): If `mb-work-state.sh` reports max_cycles reached (exit 3) OR the trend stays stagnant after a
  `pivot_via_architect` pivot, then the system shall return `stop_human`, so the loop can never run forever.
- **REQ-DR-013** (Unwanted): If `mb-work-budget.sh` pre-check shows the next iteration would exceed the run budget, then the
  system shall return `stop_budget` loudly BEFORE any subagent is dispatched.
- **REQ-DR-014** (Ubiquitous): The system shall never return `stop_success` on the model's self-assessment; only the firewall
  exit `0` AND goal-acceptance `100%` may gate success (dynamic-flow REQ-DF-060).

### Loop body (L3)

- **REQ-DR-020** (State): While goal-acceptance `< 100%` and no stop condition holds, the system shall return `implement` for
  the next unmet acceptance item, routed by `analyze-task` / an explicit `--route`.
- **REQ-DR-021** (State): While the firewall exits `1` (red) on the current item, the system shall return `repair` for the
  SAME item and increment the durable cycle via `mb-work-state.sh`, not advance to the next item.
- **REQ-DR-022** (Event): When `progress_trend` (work-loop-v2) is `stagnant` for `pivot_after_cycles`, the system shall return
  `pivot` (work-loop-v2 `pivot_in_role`, escalating to `pivot_via_architect`) rather than another `repair`.
- **REQ-DR-023** (Event): When a `regressing`/`stagnant` trend is observed, the system shall re-run `analyze-task` to allow a
  route correction before the next `implement` (dynamic-flow REQ-DF-023/024).

### Roles, guard, telemetry (L4)

- **REQ-DR-030** (Ubiquitous): The system shall dispatch `implement`/`repair`/`pivot` work through SONNET role-agents,
  external review through codex (gpt-5.5), and the judge through opus — reading the roles from `pipeline.yaml`, passing exact
  `model`/`thinking` (no fuzzy names).
- **REQ-DR-031** (State): While no resolvable `goal.md` exists, `/mb drive` shall refuse with exit `1` and a concrete fix-hint
  (reuse the `mb-goal-validate.sh` failure path), never silently start.
- **REQ-DR-032** (Optional): Where the host provides a Stop-hook (Claude Code / Cursor / Cline / Windsurf / OpenCode), the
  system shall gate a premature stop on "goal not done AND no stop condition", so the loop resumes instead of ending early.
- **REQ-DR-033** (Ubiquitous): The system shall record each stop as a one-line reason
  (`success | human:check-broke | human:max-cycle | human:stall | budget`) into the `mb-flow` fence and append it to
  `progress.md`, so a run's outcome is auditable.
- **REQ-DR-034** (State): While `MB_WORK_PARALLEL=1`, the driver's per-item state shall be per-run-keyed (reuse I-094's
  per-run dirs), so parallel drives don't cross-contaminate.

## Constraints

- No new third-party runtime dependency on the critical path; the decision function is POSIX shell.
- Additive: with no `goal.md`, `/mb drive` refuses; it never changes today's `/mb work` behaviour.
- drive-loop owns NO new done-authority, NO second cycle counter, NO second trend calculator, NO second budget gate — it
  sequences the existing ones and computes the next action.
- Scope EXCLUDES: a standalone daemon/runner, a durable-execution journal, a JS/TS runtime, and any new LLM-judge rubric.
