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
  L3  ROUTER          analyze-task → names route → agent expands flow-templates/<route>.md ← goal-conditioned route (default)
        │             (+ deterministic route-floor guard)  ·  /mb flow <route> = override   (ADR-10)
        │
  L3a PATTERN ENGINE  flow-templates/patterns/<6>.md + mb-fanout.sh (stateless, agent-      ← explicit portable orchestration
        │             invoked) + per-agent shell sub-invoke   (ADR-1′/ADR-9)                   (Codex/Pi/OpenCode, not native-only)
        │
  L4  FLOW-STATE      <!-- mb-flow --> fence in status.md (route, current_phase, checks)   ← working map (retry/resume)
        │
  L5  VERIFIER        mb-flow-verify.sh fan-out → severity-gate → exit 0/1/2               ← the firewall (fail-loud)
        │
  L6  ADAPTERS        AGENTS.md + skills/ + scripts/ + flow-templates/ + per-agent sub-    ← cross-agent install
                      invoke (LCD); explicit mb-fanout default, host-native optional        (ADR-1′/ADR-8′)
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

> **ADR-1′ — Sharpened 2026-06-16 (explicit fan-out is in; daemon stays out).** The user chose (Q2) to ship the six workflow
> patterns as EXPLICIT orchestration that runs on every code-agent (Codex/Pi/OpenCode), not delegated to a host-only native
> feature — because portability across agents is the whole point of Dynamic Flow; delegating to a native-only tool would forfeit
> it on exactly the agents that need it most. This sharpens ADR-1's blanket "no orchestration code" into a precise line:
> **DF now OWNS** an explicit, *stateless*, *agent-invoked* fan-out (the six `flow-templates/patterns/*.md` + a POSIX
> `mb-fanout.sh` + a per-agent shell sub-invocation command). **DF still OWNS NO**: standalone daemon that owns the loop without
> an agent, durable-execution / resumable-state journal, JS/TS runtime on the critical path, or any process the agent does not
> itself initiate. The good things ADR-1 protected are preserved by the *statelessness* + *agent-initiation* invariants
> (REQ-DF-085); only the over-broad reading ("therefore zero fan-out code") is lifted. The empirical proof it works without a
> runtime: this very session fanned out Codex reviews via `codex exec … </dev/null &` background jobs — agent-invoked, stateless,
> portable. See ADR-9.

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

> **ADR-8′ — Revised by ADR-1′/ADR-9.** "Host-native OR sequential+WARN" is replaced by "explicit `mb-fanout.sh` is the portable
> default everywhere; host-native is an optional optimization; sequential+WARN is the last resort only when no shell
> sub-invocation is resolvable" (REQ-DF-051/052). Codex/Pi no longer lose parallelism by default — they fan out via the helper.

### ADR-9 — Explicit, stateless pattern engine (the six patterns)
**Decision.** Ship the six Anthropic workflow patterns (Classify-And-Act, Fanout-And-Synthesize, Adversarial-Verification,
Generate-And-Filter, Tournament, Loop-Until-Done) as declarative `flow-templates/patterns/<pattern>.md` plus a single POSIX
`mb-fanout.sh`. **Mechanism.** The agent calls `mb-fanout.sh` with N branch prompts + the adapter's per-agent sub-invocation
command; the helper runs the branches as background jobs, `wait`s, and collects each branch's JSON (fail-loud: a failed/non-JSON
branch → exit 2 + per-branch error marker, never a silent drop). Patterns compose: e.g. Tournament = Fanout-And-Synthesize whose
aggregation step is pairwise judges; Loop-Until-Done wraps a body until a stop predicate. **Aggregation / judge** steps reuse
existing assets (`mb-reviewer*`, `judge`, reflexion/sadd) — no new rubric dimensions (ADR-3 scope). **Firewall still gates the
result** (REQ-DF-086): a pattern's aggregated output passes `mb-flow-verify.sh` before "done". **On Claude Code** a template may
prefer native Task/Workflow (REQ-DF-083), but the helper path is identical-in-contract and is the portable default.
**Rationale.** Realizes Dynamic Flow's value-(B) — the patterns work explicitly on agents with no native orchestration — which is
the user's stated reason for owning the engine. **Consequence.** The per-agent shell sub-invocation command becomes a first-class
adapter field; `mb-fanout.sh` must stay stateless (ADR-1′) and bash-3.2-portable; fence concurrency (open-Q2) is now load-bearing
because branches may write results in parallel.

### ADR-10 — Router auto-picks by default; explicit override is an escape-hatch
**Decision.** `analyze-task` auto-classifies and names one route by default (Classify-And-Act, system-driven — faithful to the
pattern: the SYSTEM routes, not the human). An explicit `/mb flow <route>` / `--route <route>` override skips classification but
STILL applies the deterministic route-floor (ADR-4) and the firewall (REQ-DF-025). **Rationale.** Gives the user the explicit
per-type command they asked for (Q1) without contradicting the article's own principle and without bloating the surface into six
pattern-named commands; mirrors the proven `/mb work --workflow` override precedent. **Consequence.** The override is a thin
selector, not a parallel code path — it feeds the same template interpreter the router would have chosen.

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
| Explicit `mb-fanout` spawns unbounded / expensive sub-invocations | M | H | per-run branch-count cap + `mb-work-budget.sh` pre-check at fan-out entry; fail-loud if N×cost > budget (open-Q3) |
| Parallel branches race on the `mb-flow` fence / shared sink | M | M | ADR-9: per-branch `.mb-flow/branch-<i>.json`; fence written once, serially, by the initiating agent — never by a branch (open-Q2) |
| ADR-1′ misread as license to rebuild the killed standalone runner | M | H | REQ-DF-085 invariants (stateless + agent-initiated); contract test that `mb-fanout.sh` holds no cross-invocation state + no daemon |
| Per-agent sub-invoke missing for an agent → fan-out silently serial | L | M | REQ-DF-052 stderr WARN on missing sub-invoke; document per-agent coverage matrix |

## Open questions

1. **replan-noop / re-route convergence** — what counts as "analyze-task produced nothing new" so adaptive re-routing can't loop?
   (Proposal: hash the normalized set of pending items × their touches-files; no-op = empty symmetric-difference vs last batch.)
2. **Fence concurrency** — NOW LOAD-BEARING (ADR-9): `mb-fanout.sh` runs branches in parallel, so the single `mb-flow` fence and
   any shared result sink need a write discipline from Phase 2, not Phase 3. (Proposal: each branch writes its JSON to its own
   `.mb-flow/branch-<i>.json`; the agent aggregates; the fence is written once, serially, by the initiating agent — never by a
   branch.) Resolve in the `mb-fanout` sub-wave.
3. **Check-cost scoping** — changed-files-only check execution to keep long routes practical; where does the budget gate sit?
   With explicit fan-out, also: a per-run branch-count cap + `mb-work-budget.sh` pre-check at fan-out entry (fail-loud if N×cost
   exceeds budget) so a pattern can't spawn unbounded sub-invocations.
4. **Route catalogue depth** — RESOLVED 2026-06-16 (Q3): Phase 2 ships the FULL five-route catalogue
   (`code-change | bugfix | arch | migration | research`), delivered in sub-waves; `arch` is mandatory in Phase 2 because the
   route-floor (ADR-4) can force a route to `arch`, so its template must exist or the floor points at nothing.
5. **Closure on hookful hosts** — how many `stall_count` iterations before a Stop-hook hands back to a human on a flaky check?
6. **Per-agent sub-invoke contract** — exact shape of the adapter field (`codex exec …` / Pi / OpenCode / CC) and how
   `mb-fanout.sh` discovers it (adapter-baked env var vs a resolver); how a branch's model/thinking is passed. Resolve in the
   per-agent-sub-invoke sub-wave.

> `tasks.md` carries the phased MVP. Phase 2 scope is CONFIRMED (2026-06-16): router (auto + `/mb flow` override) + route-floor +
> explicit pattern engine (`mb-fanout.sh` + six pattern templates) + full five-route catalogue, in dependency-ordered sub-waves.
> Phase 3 broadens per-agent sub-invocation + ships the `critique`/`risk-find`/`final-report` skills.
