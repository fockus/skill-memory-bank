---
type: spec-requirements
topic: Universal Orchestrator — portable Python DAG/gate/registry/runner/actualize for Memory Bank
status: draft
created: 2026-06-09
linked_design: design.md
linked_tasks: tasks.md
---

# Requirements: universal-orchestrator

> EARS patterns: **Ubiquitous** (`The <system> shall <response>`), **Event** (`When <trigger>, the <system> shall <response>`),
> **State** (`While <state>, the <system> shall <response>`), **Optional** (`Where <feature>, the <system> shall <response>`),
> **Unwanted** (`If <condition>, then the <system> shall <response>`). Validate with `mb-ears-validate.sh`.

## Context

The deep-search-v2 epic (FaberlicApp) was implemented with a harness-only, JavaScript `Workflow` tool: a MAP→SYNTHESIZE
file-collision DAG, worktree-isolated parallel tracks, a per-stage gate, and post-merge reconciliation. It worked, but
three weaknesses surfaced (see the session retrospective): the orchestration is **not portable** (JS, harness-bound),
**Memory Bank state drifted from git reality** (plans read `queued` after the epic shipped), and there was **no registry**
to prevent a duplicate concurrent run. This spec defines a **portable, Python** orchestrator that lives in the Memory Bank
skill, works **outside Claude Code** (cron/CI/other agent frontends), and is built **on top of** existing MB infrastructure
rather than duplicating it.

A deterministic precursor already shipped (`mb-drift.sh` check #14 `plan_vs_git`, wired into `/mb verify` Step 3.7) — it
makes MB-vs-git drift a fail-loud warning. This spec's `actualize` requirements build on that detector by adding the
*reconciler* (the write side).

## Functional Requirements (EARS)

### Collision-DAG (marry with the existing code graph)

- **REQ-UO-001** (Ubiquitous): The orchestrator shall build a **file-collision graph** over a set of planned phases, emitting
  `phase` nodes and `collides_with` / `depends_on` edges in the **existing `graph.json` JSON-Lines schema** so they load
  through `codegraph_loader.load_graph` with zero loader changes.
- **REQ-UO-002** (Ubiquitous): The orchestrator shall derive a `collides_with` edge (weight = number of shared files) between
  any two phases whose declared file sets intersect, reusing the file-set projection pattern of
  `codegraph_analytics.build_file_graph` **without** its `_MAX_DEFINING_FILES=8` hairball prune (a high-fan-out shared file
  is the contention hotspot to serialize, not to drop).
- **REQ-UO-003** (Ubiquitous): The orchestrator shall partition phases into mutually-exclusive parallel **tracks** by
  graph-coloring the collision graph and topologically ordering `depends_on` edges, producing a layered parallel schedule.
- **REQ-UO-004** (Unwanted): If `networkx` is unavailable, then the orchestrator shall produce a track assignment via a
  deterministic `networkx`-free fallback (connected-components / greedy coloring with a fixed sort), never failing to
  produce a layout.
- **REQ-UO-005** (Ubiquitous): The orchestrator shall expose track and collision queries through **new `mb-graph-query.py`
  subcommands** (`tracks`, `collisions --phase <id>`) reusing the existing `load_graph` → dispatch → `EXIT_OK/NO_MATCH/MISSING_GRAPH`
  JSON-and-exit-code contract.
- **REQ-UO-006** (Optional): Where git history is available, the orchestrator shall additionally treat `co_change` edges as a
  **soft collision** (serialize phases that historically co-change even without a literal file overlap), above a configurable
  weight threshold.
- **REQ-UO-007** (Ubiquitous): The base `graph.json` produced by `mb-codegraph.py` shall remain **byte-identical** when the
  collision-DAG capability is unused (the documented "capability is opt-in" invariant).

### Gate (extend the existing severity comparator, do not duplicate)

- **REQ-UO-010** (Ubiquitous): The gate shall map every check result into the **single fixed severity vocabulary**
  `{blocker, major, minor}` and decide pass/fail through the **existing** `mb-work-severity-gate.sh` comparator (the SSOT);
  it shall not introduce a second pass/fail engine or a new severity scale.
- **REQ-UO-011** (Ubiquitous): The gate configuration shall live in `pipeline.yaml` under a new top-level `gates:` block
  (bumping `pipeline.default.yaml` to `version: 2`), additively, preserving the existing `stage_pipeline:` / `severity_gate:`
  and the no-PyYAML fallback parser.
- **REQ-UO-012** (Ubiquitous): The gate shall run deterministic check runners — file-size (>400 lines → blocker), lint, type,
  test — reusing `mb-test-run.sh` and folding the duplicate file-size check currently inside `plan-verifier` step 3.6 into
  **one** runner.
- **REQ-UO-013** (Event): When a phase's feature flag is enabled, the gate shall run a **flag-ON smoke** check (set the flag,
  run the keyed test subset, assert green) and map any failure to a blocker — closing the "implemented but not wired" gap.
- **REQ-UO-014** (State): While `pipeline.yaml` declares no `gates:` block, the gate shall behave exactly as today
  (default-by-silence; `install.sh` never rewrites an existing project `pipeline.yaml`).

### Registry (anti-duplicate concurrent runs)

- **REQ-UO-020** (Ubiquitous): The orchestrator shall maintain a JSON registry `<bank>/.orchestrator/active.json` of active
  workflows — entries `{workflow_id, branch, worktree, track, status, pid, started, heartbeat}` — mutated under the portable
  `sc_lock` (mkdir-atomic + TTL) lock, reusing the `.work-budget.json` state-file pattern.
- **REQ-UO-021** (Unwanted): If a run attempts to claim a branch/worktree already present in `active.json` with a **live
  heartbeat**, then the orchestrator shall refuse the run (hard-stop) — preventing the duplicate-concurrent-run class that
  required an ad-hoc `TaskStop` in deep-search-v2.
- **REQ-UO-022** (Event): When a registry entry's heartbeat is older than its TTL or its PID is dead, the orchestrator shall
  treat the claim as stale and auto-release it.
- **REQ-UO-023** (Ubiquitous): The orchestrator shall extend `mb-drift.sh` with a checker that flags registry entries whose
  PID is dead or whose heartbeat is stale.

### Runner (portable Python spine)

- **REQ-UO-030** (Ubiquitous): The runner shall execute the proven `/mb work` loop shape
  (implement → protected-check → review → parse+gate → fix-cycle → verify → done) as a **standalone Python program**, reusing
  every existing `mb-work-*.sh` helper unchanged.
- **REQ-UO-031** (Ubiquitous): The runner shall drive subagents through a host adapter; the `claude -p` adapter shall reuse the
  **only proven non-interactive invocation** in the repo (`env -u CLAUDECODE MB_CAPTURE_SUBPROCESS=1 claude -p --strict-mcp-config
  --no-session-persistence --no-chrome`), preserving the `MB_CAPTURE_SUBPROCESS=1` anti-recursion guard.
- **REQ-UO-032** (Ubiquitous): The runner shall parse subagent structured output **tolerantly of a leading
  `[MEMORY BANK: ACTIVE]` preamble** (which `claude -p` emits because it obeys `CLAUDE.md`), never assuming clean JSON on stdout.
- **REQ-UO-033** (Ubiquitous): The runner shall schedule collision-DAG **tracks** concurrently, each in its own git worktree
  created at the plan `**Baseline commit:**`, with `.memory-bank` symlinked to the main bank.
- **REQ-UO-034** (Ubiquitous): The runner shall serialize all Memory Bank mutations across concurrent tracks under `sc_lock`
  so symlinked-bank writes never corrupt marker-fenced regions.
- **REQ-UO-035** (Unwanted): If a hard-stop condition fires — max review cycles without APPROVED, verifier FAIL, protected-path
  hit, budget exhausted, context-guard, **file-collision violation**, or **flag-ON-smoke FAIL** — then the runner shall halt
  that track and report, never silently continuing.
- **REQ-UO-036** (Ubiquitous): The runner shall enforce an explicit per-subagent **timeout, PID supervision, and cancellation**
  (Claude Code's external 180s budget is unavailable headless).
- **REQ-UO-037** (Optional): Where the runner executes outside Claude Code (cron/CI), it shall dispatch through a sequential
  CLI adapter (e.g. Codex/OpenCode) using file-based `dispatches.json` / `result.json` handoff, resolving the bank via
  `sc_resolve_mb` without any Claude Code environment.

### Actualize (deterministic git-fact reconciliation)

- **REQ-UO-040** (Ubiquitous): The orchestrator shall provide `mb-actualize.sh <bank>` — a frontend-agnostic entrypoint that
  factors out the proven `mb-plan-done.sh` actualize transaction (roadmap-sync → traceability-gen → checklist-prune →
  index-json) so any frontend can call it.
- **REQ-UO-041** (Ubiquitous): The actualizer shall reconcile `checklist.md` (`✅`/`⬜`) and the `<!-- mb-active-plans -->` /
  `<!-- mb-roadmap-auto -->` blocks **from git facts** — resolving `**Baseline commit:**` (with the plan-verifier fallback
  chain), reading `git diff baseline...HEAD` plus merged track branches plus committed DoD ticks.
- **REQ-UO-042** (Ubiquitous): The actualizer shall edit only inside HTML marker fences (`<!-- mb-active-plans -->`,
  `<!-- mb-roadmap-auto -->`, `<!-- mb-recent-done -->`, `<!-- mb-plan:<basename> -->`), leaving human-authored content
  byte-preserved.
- **REQ-UO-043** (Event): When a gate passes (severity-gate APPROVED or a green `/mb verify`), the orchestrator shall trigger
  actualize — in Claude Code via the existing `merge-hooks.py` PostToolUse marker mechanism, and headless via the runner
  calling `mb-actualize.sh` directly after a green gate.
- **REQ-UO-044** (Unwanted): If a plan claims a requirement done because its tests pass, then the actualizer shall require the
  tests to have actually **run** (via `mb-test-run.sh` / the gate), not merely be present (`traceability-gen` checks presence
  only).

### Universality & reuse constraints

- **REQ-UO-050** (Ubiquitous): The orchestrator shall expose every script with the Memory Bank path as a positional argument
  and shall run with **no dependency on the Claude Code environment** (cron/CI executable).
- **REQ-UO-051** (Ubiquitous): The orchestrator shall be implemented in **Python and POSIX shell only** (no JavaScript/TypeScript
  runtime dependency).
- **REQ-UO-052** (Ubiquitous): The orchestrator shall reuse the existing graph loader, severity comparator, lock primitives,
  budget tracker, test runner, and actualize writers; net-new code shall be limited to the collision layering, the gate
  fan-out glue, the registry CRUD, the Python runner spine, the adapters, and the git-fact reconciler.
- **REQ-UO-053** (Ubiquitous): The orchestrator shall resolve plan/phase status against **one canonical status vocabulary**
  (the SSOT chosen in design `## Decisions`), reconciling the three currently-divergent vocabularies so a plan authored in
  one vocabulary is never silently dropped from roadmap rendering.

## Constraints

- No new third-party runtime dependency is mandatory; `networkx` stays optional with a deterministic fallback (REQ-UO-004).
- Deterministic scripts must keep their no-PyYAML fallback parser path for headless environments.
- The base `graph.json` and every existing `pipeline.yaml`/spec file must remain backward-compatible (additive migration).
- Scope excludes designing new LLM-judge rubric dimensions (the review rubric stays 5 fixed keys).
