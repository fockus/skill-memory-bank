---
type: spec-design
topic: Dynamic Flow — agent-native adaptive orchestration over Memory Bank
status: draft
created: 2026-06-09
authors: [Anton Ivanov]
linked_requirements: requirements.md
linked_tasks: tasks.md
supersedes: [universal-orchestrator, goal-driven-autopilot]
---

# Design: dynamic-flow

## Architecture

**Load-bearing principle: the code-agent IS the runtime.** Dynamic Flow ships FUEL (skills), a MAP (the `mb-flow` fence),
GUARDRAILS (check scripts), and a DRIVING MANUAL (`AGENTS.md`). No standalone process owns the dispatch loop. Determinism lives
ONLY in scripts (exit codes); the LLM never self-certifies "done".

```
  L1  GOAL            goal.md (end-state + acceptance - [ ]) · project.md (constraints)   ← drive-to-done condition
        │
  L2  SKILLS          analyze-task · write-spec · plan · implement · review · critique ·  ← composable units
        │             risk-find · verify · update-MB · final-report
        │
  L3  ROUTER          analyze-task → names route → agent expands flow-templates/<route>.md ← goal-conditioned route
        │             (+ deterministic route-floor guard)
        │
  L4  FLOW-STATE      <!-- mb-flow --> fence in status.md (route, current_phase, checks)   ← working map (retry/resume)
        │
  L5  VERIFIER        mb-flow-verify.sh fan-out → severity-gate → exit 0/1/2               ← the firewall (fail-loud)
        │
  L6  ADAPTERS        AGENTS.md + skills/ + scripts/ + flow-templates/ (LCD)               ← cross-agent install
                      host-native parallel where present; sequential + WARN where absent
```

The agent reads `goal.md`, runs `analyze-task`, opens `flow-templates/<route>.md`, and walks its phases — **it is the
interpreter**. At every phase boundary it runs `mb-flow-verify.sh`; a non-zero exit forces a repair-loop. On Claude Code the
agent may delegate to the native Workflow tool / Task for parallel phases; on Codex/Pi it degrades to sequential.

## Interfaces

```text
# Goal (data, not a task list)
goal.md frontmatter: { id, status, mode: static|adaptive, progress_source, progress_target, replan_with, linked_plans[] }
goal.md body:        # Goal / ## Description / ## Acceptance criteria (- [ ] … the termination condition)

# Router skill
analyze-task: reads goal.md + `git diff --name-only` → writes `route:` into the mb-flow fence; applies the route-floor; stops.

# Flow-state fence (in status.md) — only genuinely-new fields; everything else is a POINTER to its SSOT
<!-- mb-flow -->
route: <r>          current_phase: k/n     phases: [...]
checks: { tests, rules, lint, build, mb_updated, no_todo, diff_scope, acceptance }   gate: PASS|FAIL
last_verify_sha: <sha>   stall_count: <n>
<!-- /mb-flow -->

# Verifier fan-out (the sole exit-code authority)
mb-flow-verify.sh <bank> [--phase <p>]  → JSON {blocker,major,minor} | severity-gate | exit 0 PASS / 1 FAIL / 2 broke
```

Field → SSOT map (read, not stored): goal→goal.md; DoD→goal.md acceptance + traceability.md; constraints→project.md +
pipeline.yaml protected_paths; tasks→checklist.md; decisions→backlog ADR; status→goal.md/plan frontmatter; risks→plan.md/research.

## Decisions

### ADR-1 — Agent-native, not a standalone runner
**Decision.** The host code-agent is the runtime. Dynamic Flow is skills + scripts + templates + memory-files; we never own a
dispatch loop. **Rationale.** The user's hard constraint (twice stated): usable INSIDE Codex/OpenCode/Pi/Claude Code, not as a
library that runs without an agent. **Consequence.** Kills the prior `mb-pipeline-run.py` runner and `HostAdapter.dispatch`.

### ADR-2 — Supersede universal-orchestrator + goal-driven-autopilot
**Decision.** Refocus `universal-orchestrator` into this `dynamic-flow` spec; recast `goal-driven-autopilot`'s single
`--autopilot` loop into the route-picking Router. Move both to `specs/superseded/` with a pointer. **Surviving primitives:** the
severity-gate comparator, the deterministic check runners, the git-fact actualizer (mutate-in-fence / loud-flag-outside), the
status-vocab SSOT, the `depends_on` topo-sort (`mb-roadmap-sync.sh`), and the greedy networkx-free DAG as an OPTIONAL CLI.
**Killed:** standalone Python runner, `HostAdapter.dispatch`, durable-execution journal. **Demoted to optional:** collision-DAG +
parallel tracks (a template/skill the host runs with its own subagent feature), heartbeat-TTL registry (cron/CI only).

### ADR-3 — Fail-loud lives in the fan-out + gate, never in the runners
**Decision.** Check runners (incl. the existing `mb-test-run.sh`, which is documented "exit code is always 0") stay exit-0 + JSON.
`mb-flow-verify.sh` parses their JSON, maps to severities, calls `mb-work-severity-gate.sh`, and propagates `0/1/2` as its own
exit; the Stop-hook gates on the fan-out, not on individual runners. **Rationale.** The prior critic found the "clone the
mb-test-run pattern" framing would make red checks return exit 0 — defeating the firewall. The single exit-code authority closes
that hole.

### ADR-4 — Deterministic route-floor (guard at the route boundary)
**Decision.** A wrong LLM route is mostly self-correcting at phase boundaries, BUT an arch change with a small surgical diff
(Protocol signature / DI wiring / cross-module contract) can pass diff-scope and a lazily-authored acceptance bar. So
`analyze-task` applies a pure path-glob + `depends_on` floor: touching `domain/` / `application/ports` / `*Protocol`/`ABC` /
`protected_paths` / `depends_on>0` → force route ≥ `arch`. **Rationale.** Puts a script — not the LLM — at the most dangerous
(under-escalation) boundary, making the fail-loud claim true for that case. **Consequence.** The floor must be conservative;
false-positives (forcing arch unnecessarily) are acceptable, false-negatives are not.

### ADR-5 — Flow-state is a marker-fence in status.md, not a new file
**Decision.** Reuse the proven fence pattern; put the ephemeral runtime fence in `status.md` (status-shaped), keep `goal.md`
durable-only. **Rationale.** A standalone `flow-state.json` would duplicate 7/9 fields against existing SSOTs and create a fourth
status vocabulary (three already drift; `mb-drift` checks #5/#12/#14 guard exactly this). Mixing live check-results into `goal.md`
would also break the `[x]/N` acceptance aggregator's grep and the staleness signal.

### ADR-6 — Phased scope; build-runner is YAGNI for v1
**Decision.** Phase 1 = goal + firewall (valuable on Claude Code immediately, and stronger than native `/goal`); Phase 2 =
mini-router (`code-change`=reuse work.md, `bugfix`) + route-floor; Phase 3 = adapters + remaining templates + parallel + the
extra skills. Drop the build-runner (this project builds via EAS/Kamal, not locally); `build` resolves to `skip`.
**Rationale.** The dominant case (code-change) is ~today's work.md, so the router earns its keep mainly for non-CC agents and
arch/migration — defer it behind the universally-valuable firewall.

### ADR-7 — Context contract; do not over-split
**Decision.** Each flow-template phase declares what it READS from files (diff via git, prior review JSON at a fixed path,
engineering-core via the existing prepend) so cross-phase context is reconstructed deterministically, not from conversational
memory. For `code-change`, keep implement→review→fix as ONE skill (the existing work.md loop) rather than separate hops.
**Rationale.** The user explicitly likes the current structured, context-preserving flow; splitting below the work.md granularity
costs context-marshalling on agents without subagent context inheritance (Pi).

### ADR-8 — Parallel via host-native only; registry optional
**Decision.** The Router EMITS a track list; the host fans out with its native feature (CC Task / OpenCode subagents) or runs
sequentially + WARN (Codex/Pi). The heartbeat-TTL registry is built ONLY for the cron/CI multi-runner path, off the v1 critical
path. **Rationale.** The host owns dispatch (ADR-1); a standalone scheduler/registry would re-introduce the killed runtime.

## Risks & mitigation

| Risk | Prob | Impact | Mitigation |
|------|------|--------|------------|
| LLM route-pick wrong for small surgical arch diff | M | H | ADR-4 deterministic route-floor (path-glob + depends_on) |
| Net-new runners accidentally fail-silent (exit 0 on red) | M | H | ADR-3: exit-code authority only in fan-out + gate; contract test |
| Concurrency race on the single `mb-flow` fence under parallel dispatch | M | M | serialize fence writes; or per-track fence sections; lock like plan-sync |
| Full verifier at every boundary of a long route is slow/expensive | M | M | changed-files-only check scoping; budget pre-check at wave entry |
| Pi hookless: no-commit false-done undetected | M | M | document honestly; git-hooks-fallback enforces at commit-time |
| Acceptance criteria are themselves an unchecked LLM act | M | M | route-floor + diff-scope backstop; acceptance is necessary not sufficient |
| Splitting skills breaks the context-preserving flow the user values | L | H | ADR-7 context contract; keep code-change as one work.md loop |
| Two superseded specs re-litigated (tasks all `[ ]`) | L | M | move to specs/superseded/ + status flip + banner BEFORE any code |

## Open questions

1. **replan-noop / re-route convergence** — what counts as "analyze-task produced nothing new" so adaptive re-routing can't loop?
   (Proposal: hash the normalized set of pending items × their touches-files; no-op = empty symmetric-difference vs last batch.)
2. **Fence concurrency** — single serialized `mb-flow` fence vs per-track sections once parallel dispatch lands (Phase 3).
3. **Check-cost scoping** — changed-files-only check execution to keep long routes practical; where does the budget gate sit?
4. **Route catalogue depth** — confirm v2 ships only `code-change`+`bugfix`; arch/migration/research deferred to Phase 3.
5. **Closure on hookful hosts** — how many `stall_count` iterations before a Stop-hook hands back to a human on a flaky check?

> `tasks.md` carries the phased MVP. Phases 2–3 stay deferred until Phase 1's firewall is proven and the user confirms scope.
