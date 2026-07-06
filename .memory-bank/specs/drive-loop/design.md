---
type: spec-design
topic: drive-loop — autonomous goal-driven session driver over the firewall
status: ready
created: 2026-07-05
authors: [Anton Ivanov]
linked_requirements: requirements.md
linked_tasks: tasks.md
depends_on_specs: [dynamic-flow, work-loop-v2, reviewer-2.0]
---

# Design: drive-loop

## Architecture

**The agent is the runtime; `mb-drive.sh` is the brain, the agent is the hands.** drive-loop is a stateless decision
function plus a loop contract. Each iteration the host agent asks `mb-drive.sh next` "what now?", gets ONE deterministic
action, executes it (dispatch a sonnet subagent, run the firewall, or stop), and asks again. No daemon owns the loop.

```
  ┌─────────────────────────── host code-agent (the runtime) ───────────────────────────┐
  │                                                                                       │
  │   loop:                                                                               │
  │     action = mb-drive.sh next --bank <b> [--route R]      ← deterministic decision    │
  │     case action:                                                                      │
  │       implement <route> <item>  → dispatch SONNET role-agent (route template)         │
  │       repair <item>             → dispatch SONNET role-agent (same item, cycle++)      │
  │       pivot <mode> <item>       → work-loop-v2 pivot (sonnet; architect on escalate)   │
  │       stop_success              → break: goal done (firewall green + acceptance 100%)  │
  │       stop_human <why>          → break: hand to human (check-broke | max-cycle | stall)│
  │       stop_budget               → break: budget ceiling hit                            │
  │     (after implement/repair/pivot) run review→judge per pipeline (codex→opus)          │
  │                                                                                       │
  └───────────────────────────────────────────────────────────────────────────────────────┘
                                        │ every step reads/writes
                                        ▼
   goal.md (acceptance [x]/N) · mb-flow fence (route,cycle,trend,stall,gate) · mb-work-state (cycle/max) ·
   mb-work-budget (ceiling) · last-verdict cache (trend)          ← all pre-existing SSOTs, none duplicated
```

## The decision function — `mb-drive.sh next`

Pure, side-effect-free except an optional fence/telemetry write on a stop. Reads five inputs, emits one action.

```text
inputs (all from existing scripts / files):
  acc      = mb-goal-acceptance.sh <bank>            → done_pct (0..100), unmet_items[]
  gate     = mb-flow-verify.sh <bank> [--phase P]    → exit 0|1|2   (THE firewall; sole done authority)
  trend    = normalized verdict progress_trend       → improving|stagnant|regressing|null  (work-loop-v2)
  cyc      = mb-work-state.sh cycle/status           → cycle, max_cycles, exhausted?(exit 3)
  bud      = mb-work-budget.sh precheck <next-cost>  → ok | exceeded

decision (first match wins — deterministic, order matters):
  1. gate == 2                                   → stop_human  (why=check-broke:<name>)
  2. bud == exceeded                             → stop_budget
  3. acc.done_pct == 100 AND gate == 0           → stop_success
  4. cyc.exhausted OR (stall AND last_pivot==architect) → stop_human (why=max-cycle|stall)
  5. gate == 1 AND trend==stagnant≥pivot_after   → pivot <in_role|via_architect> <current_item>
  6. gate == 1                                   → repair <current_item>            (cycle++)
  7. acc.done_pct < 100                          → implement <route> <next unmet item>
```

Rule ordering is the safety contract: **stops are checked before progress** (a broken check, an over-budget run, or a
completed goal short-circuit before any new work), and **pivot before repair** (escalate a stuck item instead of grinding).

## Interfaces

```text
mb-drive.sh next   --bank <b> [--route R] [--phase P] [--budget TOK]   → prints one action line; exit 0
                    action grammar:
                      implement <route> <item_id>
                      repair <item_id>
                      pivot <in_role|via_architect> <item_id>
                      stop_success
                      stop_human <check-broke:<name>|max-cycle|stall>
                      stop_budget
mb-drive.sh status --bank <b>                                          → current drive state (derived, read-only)
/mb drive <goal> [--route R] [--max-cycles N] [--budget TOK]           → command wrapper; refuses w/o goal.md (exit 1)
```

`mb-drive.sh` computes NOTHING new: `done_pct` from `mb-goal-acceptance.sh`, `gate` from `mb-flow-verify.sh`, `trend` from
the normalized verdict (`mb-work-review-parse.sh` output / last-verdict cache), `cycle` from `mb-work-state.sh`, `budget`
from `mb-work-budget.sh`. It is a router over exit codes and JSON fields.

## Decisions

### ADR-1 — Rebuild autopilot over the firewall, not as an LLM loop
**Decision.** drive-loop revives `goal-driven-autopilot` Sprint 7's intent (self-driving to a goal) but replaces its two
LLM-only mechanisms — the autopilot loop and the "done" check — with a deterministic decision function + the firewall gate.
**Rationale.** The superseded spec was rejected precisely because a model must not certify its own completion (memory
`judge-terminates-review-loop`, `governed-review-independent-refix`). **Consequence.** Success requires firewall exit 0 AND
acceptance 100%; the model's opinion is never a stop condition.

### ADR-2 — Stateless decision helper; the agent owns dispatch (inherits dynamic-flow ADR-1′)
**Decision.** `mb-drive.sh` returns an action and exits; the host agent dispatches subagents and re-invokes it. **Rationale.**
Portability across Codex/Pi/OpenCode/Claude Code — the same helper works everywhere because it never owns a process.
**Consequence.** No daemon, no journal; a killed session simply resumes by re-reading the durable SSOTs (mb-flow fence +
mb-work-state) and calling `next` again — resume is free because state lives in files, not in a process.

### ADR-3 — Stops before progress; pivot before repair
**Decision.** The decision table checks stop conditions (broken check, budget, success, exhaustion) before emitting new work,
and prefers pivot over repeated repair on a stagnant trend. **Rationale.** Three independent safeties (acceptance-gate,
max-cycle/stall, budget) must each be able to halt the loop regardless of what the model wants next. **Consequence.** The
loop provably terminates: either acceptance reaches 100% behind a green firewall, or one of the three brakes fires.

### ADR-4 — Reuse the roles from pipeline.yaml verbatim
**Decision.** `implement`/`repair`/`pivot` dispatch the pipeline-resolved role-agent (sonnet); review is codex (gpt-5.5);
judge is opus. drive-loop passes exact `model`/`thinking`. **Rationale.** One SSOT for role→model (the active governed
pipeline), no fuzzy names (project rule). **Consequence.** Changing the model tier is a `pipeline.yaml` edit, not a drive-loop
change; cost-multi-model (Phase 5) composes cleanly.

### ADR-5 — Closure on hookful hosts strengthens, doesn't replace, the contract
**Decision.** On hosts with a Stop-hook, a thin resume-gate blocks a premature stop when "goal not done AND no stop
condition"; on hookless hosts the `AGENTS.md` loop contract is the mechanism and the git-hooks fallback catches a
no-commit false-done at commit time (dynamic-flow REQ-DF-062). **Rationale.** Belt-and-suspenders without a daemon.

## Reuse map (nothing here is net-new logic)

| Capability | Existing asset | drive-loop's use |
|---|---|---|
| Done gate | `mb-flow-verify.sh` (exit 0/1/2) | success/repair/stop_human decision |
| Goal % | `mb-goal-acceptance.sh` | `[x]/N` → done_pct, next item |
| Route | `analyze-task` / `mb-flow-route.sh` | pick/override route per iteration |
| Trend/pivot/stall | work-loop-v2 (Phase 2) | pivot vs repair; stall stop |
| Cycle / max_cycles | `mb-work-state.sh` (I-093) | cycle++, exhaustion stop |
| Budget | `mb-work-budget.sh` | pre-dispatch budget stop |
| Verdict normalize | `mb-work-review-parse.sh --external` | trend source (codex verdict) |
| Fence / telemetry | `mb-flow-sync.sh` mb-flow fence | route, cycle, trend, stall, stop reason |
| Closure | CC Stop-hook + `git-hooks-fallback.sh` | resume-gate / commit-time backstop |

## Risks & mitigation

| Risk | Prob | Impact | Mitigation |
|---|---|---|---|
| Decision table order bug lets the loop skip a stop | L | H | table is the load-bearing bats test: one case per rule, plus "stop beats progress" ordering cases |
| Trend/`stall` counter drift vs work-loop-v2 | M | M | single SSOT = mb-flow fence `stall_count` (work-loop-v2 design §Alignment); drive READS, never writes a second counter |
| Budget precheck under/over-estimates next-iteration cost | M | M | reuse `mb-work-budget.sh` estimate; conservative (stop on `>=`); fail-loud not fail-open |
| Hookless host false-done (Pi) | M | M | git-hooks-fallback at commit; documented honestly in AGENTS.md (dynamic-flow REQ-DF-062) |
| Autonomous loop spawns unbounded sonnet subagents | M | H | budget stop (rule 2) fires BEFORE dispatch; max_cycles (rule 4) bounds per-item iteration |
| Agent ignores the contract and stops early | L | M | Stop-hook resume-gate on hookful hosts (ADR-5); the loop is idempotent-resumable so a re-run continues |

## Open questions

1. **stall-after-pivot definition** — exactly how many post-`pivot_via_architect` stagnant cycles before `stop_human`?
   (Proposal: 1 — architect pivot is already the heavy escalation; if it doesn't move the trend, hand back.)
2. **next-item selection when acceptance items map to multiple plans/specs** — order by plan `depends_on` topo-sort
   (reuse `mb-roadmap-sync.sh` ordering) vs goal.md declaration order. Resolve in Task 1.
3. **budget estimate granularity** — per-iteration flat estimate vs per-route (arch costs more than bugfix). Start flat;
   refine when cost-multi-model (Phase 5) lands real per-role costs.
