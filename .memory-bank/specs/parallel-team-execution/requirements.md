---
type: spec-requirements
topic: Parallel & Team Execution — multi-agent parallel /mb work (subagents + native Team) with an orchestrator-selected pattern library
status: draft
created: 2026-06-14
linked_design: design.md
linked_tasks: tasks.md
extends: [parallel-pipeline, dynamic-flow, composable-work-pipeline]
references:
  - fockus/claude-skill-build   # GSD: subagent dispatch + /build:team-phase team-mode + model tiering
---

# Requirements: parallel-team-execution

> EARS patterns (validate with `scripts/mb-ears-validate.sh`):
> - **Ubiquitous**: `The <system> shall <response>`
> - **Event-driven**: `When <trigger>, the <system> shall <response>`
> - **State-driven**: `While <state>, the <system> shall <response>`
> - **Optional feature**: `Where <feature>, the <system> shall <response>`
> - **Unwanted**: `If <trigger>, then the <system> shall <response>`

## Context

Memory Bank's `/mb work` runs the **implement** step as **one role-agent per work-item, sequentially**
(`commands/work.md` §5a: "pick a work item → route to the right role-agent → let the agent implement → verify").
The **only** out-of-the-box parallelism is the **review ensemble** (`work.md`:326, 3–5 aspect reviewers in parallel).
There is **no parallel implement** and **no team-mode**. A project may declare a `pipeline.yaml` `implement:` block with
`parallelism: dynamic`, but the stock engine + `mb-pipeline-validate.sh` **ignore** it (unknown top-level keys pass
validation without being enforced) — so today such a block is **inert documentation**, not a feature.

This spec adds first-class **parallel, multi-agent execution** to `/mb work` in two modes — **(A) ephemeral subagents**
(host-native Task/Workflow) and **(B) native Team** (persistent, addressable teammates via the host's Team feature) —
driven by an **orchestrator that selects an execution pattern by task scope**, **monitors** in-flight progress, and gates
completion on a **deterministic, coded verifier** rather than any agent's self-assessment.

**Reference (sourced):** `fockus/claude-skill-build` (GSD) already ships exactly this shape — two mechanisms
(subagent dispatch + `/build:team-phase` team-mode with model-tiering on Opus) and **scope-based pattern selection**
(1 file → `fast`; 2–5 → `quick`; phase 1–3 tasks → sequential+judge; **phase ≥4 tasks → parallel team**; all → autonomous).
We want the same capability **inside the Memory Bank skill**, composed from MB's own assets.

**Agent-native (hard constraint).** This ships as skills + instructions + templates + check-scripts the **host code-agent**
reads and executes with its OWN native subagent/Task/Team/workflow features. We never own the dispatch loop; the host is the
runtime. "Portable" means **cross-agent**, not no-agent.

**Relationship to existing specs (extends, does not duplicate).**
- `parallel-pipeline` (REQ-140..146, ready) already gives wave-based, **plan-level** parallelism: `/mb run`, `pipeline.yaml`
  DAG, **worktree-per-plan**, cross-agent adapter, Mode A (sequential) vs Mode B (parallel waves). This spec **reuses** that
  wave/worktree/adapter/budget engine and adds **within-plan parallel-implement**, **native Team mode**, and **pattern
  selection** on top.
- `dynamic-flow` (REQ-DF-*, draft) gives a **Router** that picks a route per task + a **deterministic completion firewall**
  (`mb-flow-verify.sh` + `mb-work-severity-gate.sh`) + a marker-fenced runtime contract. This spec **generalizes** that Router
  into an execution-**pattern library** and **reuses** its firewall + fence verbatim.
- `composable-work-pipeline` (REQ-001..016) gives flag/preset/`pipeline.yaml` stage resolution. Parallel and Team are new
  **execution modes** resolvable through that same resolution layer.

## Functional Requirements (EARS)

### A. Parallel implement via subagents (closes the current gap)

- **REQ-PTE-001** (Ubiquitous): The system shall decompose the active plan/spec into dependency-disjoint work units (by file / module / task with no shared mutable surface) before dispatching the implement step.
- **REQ-PTE-002** (Event-driven): When a work item resolves to two or more dependency-disjoint units, the system shall dispatch one implementer subagent per unit in parallel through the host-native subagent feature.
- **REQ-PTE-003** (Ubiquitous): The orchestrator shall choose the parallel degree dynamically from the count of independent units, bounded by a configurable `max_parallel`.
- **REQ-PTE-004** (Ubiquitous): The system shall run each parallel implementer in its own git worktree so that no two implementers mutate the same file concurrently.
- **REQ-PTE-005** (State-driven): While two units share a dependency edge, the system shall serialize them and parallelize only the dependency-disjoint units.
- **REQ-PTE-006** (Event-driven): When a unit's own tests pass, the system shall integrate that unit back into the base branch before marking the unit done (sequential-after-unit-green merge).
- **REQ-PTE-007** (Unwanted): If the host provides no native parallel-subagent feature, then the system shall execute the units sequentially and emit a stderr WARN, preserving correctness.

### B. Native Team mode (тиммод)

- **REQ-PTE-010** (Optional feature): Where the host exposes a native Team feature (e.g. TeamCreate), the system shall offer a team-mode execution path that spawns persistent, addressable teammates for a phase, distinct from ephemeral subagents.
- **REQ-PTE-011** (Event-driven): When team-mode is selected, the system shall assign each teammate a role and a work-slice and shall coordinate them through host-native messaging (e.g. SendMessage) under a single lead orchestrator.
- **REQ-PTE-012** (Ubiquitous): The orchestrator shall select the execution mode — sequential, parallel-subagent, or team — from task scope using a documented decision matrix mirroring the GSD reference.
- **REQ-PTE-013** (Unwanted): If team-mode is requested on a host without a native Team feature, then the system shall degrade to parallel-subagent or sequential mode and emit a WARN rather than fail.
- **REQ-PTE-014** (Ubiquitous): The system shall persist team membership, each teammate's work-slice, and live status in a marker-fenced runtime block, deriving any JSON view read-only without introducing a new status SSOT.

### C. Workflow-pattern library + orchestrator selection

- **REQ-PTE-020** (Ubiquitous): The system shall expose a catalogue of named execution patterns — at minimum sequential, parallel-fanout, pipeline, wave-DAG, loop-until-dry, adversarial-verify, and judge-panel — as declarative templates.
- **REQ-PTE-021** (Ubiquitous): The orchestrator shall select exactly one pattern per task from the catalogue and shall record the chosen pattern with its justification in the runtime fence.
- **REQ-PTE-022** (Unwanted): If the task scope crosses a deterministic floor (touches `domain/`, an `application/ports` path, a `*Protocol`/`ABC`/interface file, a declared `protected_path`, or a multi-plan phase), then the orchestrator shall raise the pattern to at least the wave-DAG / team tier regardless of its heuristic choice.
- **REQ-PTE-023** (Optional feature): Where a pattern must be reproducible, the system shall allow that pattern to be expressed as deterministic workflow-as-code whose structured output the orchestrator consumes for verification.
- **REQ-PTE-024** (Ubiquitous): The pattern library shall reuse the existing review-ensemble parallel dispatch and the `parallel-pipeline` wave engine rather than reimplementing parallel primitives.

### D. Progress monitoring

- **REQ-PTE-030** (State-driven): While a parallel or team execution is in flight, the orchestrator shall monitor each agent/teammate's status and surface live per-unit progress.
- **REQ-PTE-031** (Unwanted): If a unit fails, times out, or stalls beyond the configured threshold, then the orchestrator shall halt that unit, surface the breach, and apply the pattern's retry-or-fallback rule without silently dropping the unit.
- **REQ-PTE-032** (Ubiquitous): The system shall record per-unit runtime status (pending / running / green / failed) in the marker-fenced block, regenerated idempotently with content outside the fence byte-preserved.

### E. Code-as-verification (deterministic firewall)

- **REQ-PTE-040** (Ubiquitous): The system shall gate completion of any parallel or team execution on the deterministic verifier (`mb-flow-verify.sh` + `mb-work-severity-gate.sh`), never on an agent's self-assessment.
- **REQ-PTE-041** (Event-driven): When a pattern is expressed as workflow-as-code, the system shall verify each unit's DoD and tests from that workflow's structured output before integrating the unit.
- **REQ-PTE-042** (Unwanted): If the deterministic verifier returns non-zero for any unit, then the system shall enter a repair loop for that unit and shall not declare the execution finished.

### F. Reuse / backward-compatibility / agent-native constraints

- **REQ-PTE-050** (State-driven): While neither parallel nor team mode is requested, the system shall behave byte-identically to today's sequential `/mb work` (Mode A).
- **REQ-PTE-051** (Ubiquitous): The system shall reuse existing assets — the 9 role-agents, `mb-reviewer`, `plan-verifier`, the worktree layer, `pipeline.yaml`, `mb-flow-verify.sh`, `mb-work-severity-gate.sh`, and `mb-work-budget.sh` — and shall add only thin orchestration glue.
- **REQ-PTE-052** (Ubiquitous): The system shall remain agent-native with no standalone runtime process, letting the host agent own the dispatch loop.
- **REQ-PTE-053** (Ubiquitous): The system shall resolve per-role implementer and teammate models from `pipeline.yaml` using exact model ids and no fuzzy aliases.

### G. pipeline.yaml schema + validator (close the inert-config gap)

- **REQ-PTE-060** (Ubiquitous): The system shall add first-class schema for parallel/team execution to `pipeline.yaml` (an execution-mode / parallelism / patterns block) so the engine consumes it instead of ignoring unknown keys.
- **REQ-PTE-061** (Ubiquitous): The `mb-pipeline-validate.sh` validator shall recognize and validate the parallel/team schema, checking known keys, types, and bounds.
- **REQ-PTE-062** (Unwanted): If the parallel/team config is invalid (unknown pattern, `max_parallel` ≤ 0, or team-mode without a declared fallback on a Team-less host), then the validator shall exit non-zero naming the offending key.

### H. Phasing

- **REQ-PTE-070** (Ubiquitous): The system shall ship Phase 1 (parallel-implement via subagents + `pipeline.yaml` schema + validator) as an independently valuable increment on Claude Code.
- **REQ-PTE-071** (Ubiquitous): The system shall ship Phase 2 (native Team mode + orchestrator scope→mode selection) after Phase 1's parallel-implement is real.
- **REQ-PTE-072** (Ubiquitous): The system shall ship Phase 3 (full pattern library + progress-monitoring polish + cross-agent adapters) last, building on the existing adapter layer.

## Non-Functional Requirements

- **NFR-PTE-001** (Performance): parallel execution of N dependency-disjoint units should reduce wall-clock versus sequential, approaching linear speed-up up to `max_parallel` minus dispatch overhead; the design must state the measured/expected overhead per dispatch.
- **NFR-PTE-002** (Safety): worktree isolation must guarantee that no two concurrent agents mutate the same file; integration is sequential and conflict-detecting.
- **NFR-PTE-003** (Budget): parallel/team waves must reserve tokens per wave and honor `hard_stop_tokens`, reusing `mb-work-budget.sh`; in-flight parallel context multiplies cost and must be bounded.
- **NFR-PTE-004** (Observability): live per-unit progress must be surfaceable at any point during a run (subagent and team modes alike).
- **NFR-PTE-005** (Determinism): completion must be gated by the coded verifier's exit code and be reproducible across runs (no LLM self-certification).
- **NFR-PTE-006** (Cost/quality): parallel implementers/teammates should default to the project's configured implementer tier (this project: Opus) per `pipeline.yaml`, mirroring GSD model-tiering so parallelism does not degrade quality.

## Constraints

- No new third-party runtime dependency on the critical path; determinism lives in POSIX shell / Python check scripts.
- Do not reimplement `parallel-pipeline` waves or the `dynamic-flow` Router/firewall — compose them.
- The base behaviour with no parallel/team request must remain byte-identical (additive migration, gated behind opt-in like `parallel-pipeline`'s v5 major-version gate where applicable).
- Tests must be written before implementation for the deterministic scripts and validators (TDD).

## Out of scope

- A standalone dispatcher, durable-execution journal, or non-agent runtime.
- Cross-provider model execution (`skill:<name>` / `cli:<cmd>`) — deferred (see `parallel-pipeline` G11 / I-045).
- New LLM-judge rubric dimensions.

## Edge cases & failure modes

- Single unit → no parallelism; the sequential path is taken unchanged.
- Dependency cycle among units → reject at decomposition, reusing DAG validation (`parallel-pipeline` REQ-141).
- Worktree merge conflict at integration → halt and surface; never silently overwrite.
- Teammate dies / disconnects mid-task → reassign or retry per the pattern's rule; never drop the slice.
- Host without native Team and without subagents → sequential execution + WARN.
- Independent units exceed `max_parallel` → queue the remainder and dispatch as slots free.
- Mixed dependent + disjoint units → parallelize the disjoint set, serialize the dependent tail.
- A parallel implementer reports green but the deterministic verifier disagrees → verifier wins; unit re-enters repair loop (REQ-PTE-042).
