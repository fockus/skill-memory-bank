---
type: spec-design
topic: Universal Orchestrator — portable Python DAG/gate/registry/runner/actualize for Memory Bank
status: draft
created: 2026-06-09
linked_requirements: requirements.md
linked_tasks: tasks.md
---

# Design: universal-orchestrator

## Architecture

Clean-Architecture layering, dependencies pointing inward; every layer is reusable outside Claude Code.

```
                ┌─────────────────────────────────────────────────────────────┐
  IO / CLI      │ mb-pipeline-run.py (runner spine) · mb-graph-query.py (tracks│
                │ /collisions subcmds) · mb-gate.sh · mb-registry.sh ·         │
                │ mb-actualize.sh · adapters (claude -p / Codex / OpenCode)    │
                └───────────────▲─────────────────────────▲───────────────────┘
                                │                          │
  Pure derived   ┌──────────────┴───────────┐   ┌──────────┴───────────────┐
                 │ codegraph_collision.py    │   │ gate aggregation (counts │
                 │ (file→phases inversion,   │   │ → severity buckets)      │
                 │ collide edges, track      │   └──────────┬───────────────┘
                 │ layout, topo-sort)        │              │
                 └──────────────▲────────────┘              │
                                │                           │
  Extractors /    ┌─────────────┴───────────────────────────┴──────────────┐
  primitives      │ EXISTING (reused unchanged): codegraph_loader.load_graph │
  (reused)        │ · codegraph_analytics.build_file_graph · mb-work-        │
                  │ severity-gate.sh (comparator SSOT) · mb-test-run.sh ·     │
                  │ mb-work-budget.sh · sc_lock/sc_fm_set · sc_resolve_mb ·   │
                  │ mb-plan-sync/done/roadmap-sync (actualize writers)        │
                  └──────────────────────────────────────────────────────────┘
```

**Five subsystems, each EXTENDS an existing seam:**

1. **Collision-DAG** — `codegraph_collision.py` (pure, deps-free). Inverts `{phase: {files}} → {file: {phases}}`, emits
   `collides_with` edges (weight = shared-file count) and directed `depends_on` edges, then layers them into parallel tracks
   (undirected collision graph → graph-coloring into mutually-exclusive tracks; directed `depends_on` → topo order). Output is
   `graph.json` JSON-Lines, loaded by the **existing** `codegraph_loader.load_graph` (which silently skips unknown record
   types — verified). Reuses `build_file_graph`'s projection pattern but **drops** the `_MAX_DEFINING_FILES=8` prune. A
   `networkx`-free greedy-coloring fallback guarantees a layout in CI.
2. **Gate** — `mb-gate.sh` fans out deterministic check runners (file-size, lint, type, test, flag-ON-smoke), normalizes each
   into `{blocker, major, minor}` counts, and calls the **single existing comparator** `mb-work-severity-gate.sh`. Config is a
   new `gates:` block in `pipeline.yaml` (`version: 2`, additive).
3. **Registry** — `mb-registry.sh` + `<bank>/.orchestrator/active.json`, mutated under `sc_lock` (mkdir-atomic + TTL).
   Branch-claim = the anti-duplicate primitive; TTL auto-releases crashed runners.
4. **Runner** — `mb-pipeline-run.py`, the standalone Python spine that ports the `/mb work` loop and drives subagents through a
   host **adapter** (`claude -p` interactive; Codex/OpenCode sequential for cron/CI). Schedules collision-DAG tracks
   concurrently in worktrees; enforces timeout/PID/cancel; halt-on-red.
5. **Actualize** — `mb-actualize.sh` factors out the proven `mb-plan-done.sh` transaction and adds a **git-fact reconciler**
   that reads `git diff baseline...HEAD` and reconciles marker-fenced state. Triggered on gate-pass.

## Interfaces

```python
# Collision-DAG (pure)
class CollisionDag(Protocol):
    def build(self, phases: list[Phase]) -> Graph: ...          # phases → JSON-Lines nodes+edges
    def tracks(self, graph: Graph) -> list[list[PhaseId]]:      # layered parallel schedule
        ...                                                      # deterministic; networkx-free fallback

# Phase = {id, plan, files: set[str], depends_on: list[PhaseId], parallel_safe: bool, flag: str|None}

# Gate check runner — every runner returns this shape; the gate maps it into counts
class CheckRunner(Protocol):
    def run(self, ctx: GateCtx) -> CheckResult: ...   # CheckResult = {name, ok: bool, findings:[{severity,msg}]}
# severity ∈ {blocker, major, minor} ONLY. Comparator = mb-work-severity-gate.sh (unchanged).

# Registry CRUD (under sc_lock)
class Registry(Protocol):
    def claim(self, branch: str, entry: Entry) -> bool: ...   # False if live claim exists (anti-dup)
    def heartbeat(self, workflow_id: str) -> None: ...
    def release(self, workflow_id: str) -> None: ...
    def reap_stale(self) -> list[Entry]: ...                  # TTL / dead-PID auto-release

# Host adapter (the portability seam)
class HostAdapter(Protocol):
    def dispatch(self, prompt: str, *, model: str, timeout_s: int, cwd: Path) -> AgentResult: ...
# AgentResult.text parsing MUST tolerate a leading "[MEMORY BANK: ACTIVE]" preamble.

# Actualize
def actualize(bank: Path, *, baseline: str) -> ReconcileReport: ...   # git facts → marker-fenced writes
```

Exit-code / JSON contract for the new `mb-graph-query.py tracks|collisions` subcommands mirrors the existing
`EXIT_OK=0 / NO_MATCH / INVALID_INPUT / MISSING_GRAPH` so the runner needs no new IPC.

## Decisions

### ADR-1 — Relationship to existing prior-art specs (KEY REVIEW DECISION)
**Context.** The skill already has `parallel-pipeline` (wave-DAG executor + worktree-per-plan + cherry-pick merge + adapter
layer §10 + model registry), `work-loop-v2` (progress-trend pivot, additive pipeline.yaml migration), and `reviewer-2.0`
(calibrated reviewer) — all `status: ready/queued` but **UNIMPLEMENTED** (no `mb-pipeline-run.py` / `mb_pipeline_plan.py` exist).
**Options.** (a) Build `universal-orchestrator` standalone (duplicates parallel-pipeline). (b) Implement parallel-pipeline first,
then layer this on. (c) Make `universal-orchestrator` the **umbrella** that absorbs parallel-pipeline's worktree/merge/adapter
design as its runner foundation, folds in work-loop-v2 (progress-trend) and reviewer-2.0 (gate evidence) as sub-behaviors, and
adds the net-new collision-DAG↔code-graph marriage, the gate object, the registry, and the git-fact actualizer.
**Decision (recommended, pending review).** Option (c). Mark the three prior-art specs `phase_of: universal-orchestrator` and
reuse their designs verbatim where proven (parallel-pipeline §5 worktree, §6/§7 merge, §10 adapter). **This is the single most
important decision for the user to confirm** — it prevents the very DRY/duplication the retrospective warned about.
**Consequences.** One coherent umbrella; the prior-art specs become implementation chapters, not competitors. Requires editing
their frontmatter to `phase_of` and a short note in `mb-skill-v2`.

### ADR-2 — Collision-DAG storage: sibling file
**Decision.** Write collision records to a **sibling** `<bank>/codebase/collision-dag.json`, not appended into `graph.json`.
**Rationale.** Keeps base `graph.json` byte-identical (REQ-UO-007); the two have different rebuild semantics (`graph.json` from
source via `mb-codegraph.py`; `collision-dag.json` from plans + `git diff`). Both load via the same `load_graph`.

### ADR-3 — Phase→files derivation: authored `touches:` line, git-validated
**Decision.** A phase's file set is the SSOT-authored `touches: path/**` line(s) in the plan body, **validated** post-hoc
against `git diff baseline...HEAD` per stage. Fallback when absent: parse `Create:`/`Modify:` DoD file references.
**Rationale.** Scheduling must happen **before** implementation exists (git diff is empty pre-run → chicken-and-egg). Authoring
discipline is the price of pre-run parallelization; git-diff validation catches drift between declared and actual touches.

### ADR-4 — Status vocabulary SSOT
**Decision.** Canonical set `{queued, in_progress, done, blocked, paused}` (the `mb-drift.sh` #13 vocabulary, which
`mb-roadmap-sync.sh` already renders). Non-canonical values map deterministically (`ready → queued`, `active → in_progress`);
the actualizer normalizes on write.
**Rationale.** Three divergent vocabularies silently drop plans from roadmap rendering today; one SSOT + a normalization table
ends the drift. Aligns with the already-shipped `mb-drift.sh` #13/#14.

### ADR-5 — Merge strategy for completed tracks
**Decision.** Because collision-DAG tracks are **file-disjoint by construction**, default to sequential fast-forward / rebase
merge; retain parallel-pipeline's squash→cherry-pick as the fallback for **soft-collision** (co_change) tracks that may touch
near-coupled files.
**Rationale.** Disjoint file sets cannot conflict; the simpler merge avoids cherry-pick overhead where it is provably safe.

### ADR-6 — networkx-free, reproducible track layout
**Decision.** Greedy graph-coloring over a **fixed node sort** (plan, stage), seed-free and deterministic; `networkx` Louvain
communities are an optional refinement hint only.
**Rationale.** `networkx` is optional and returns `None` in CI; the runner must always produce the same tracks for the same
plans (reproducibility), so the deterministic fallback is the primary path.

## Risks & mitigation

| Risk | Prob | Impact | Mitigation |
|------|------|--------|------------|
| Runner spine is the largest net-new piece (Python loop driving `claude -p` concurrently in worktrees) | H | H | Reuse parallel-pipeline §5–§10 design verbatim; port `/mb work` loop shape; ship runner LAST after DAG/gate/registry/actualize are independently green |
| `claude -p` prints `[MEMORY BANK: ACTIVE]` preamble → breaks JSON parsing (already bit session-end) | H | M | Preamble-tolerant extractor in the adapter (REQ-UO-032); reuse session-end's proven workaround |
| Dropping `_MAX_DEFINING_FILES=8` → a hot shared file forms a giant `collides_with` clique → over-serialization | M | M | Report hot-contention files (file_betweenness); allow an explicit `serialize:` override; consider refactoring the hotspot |
| Three divergent status vocabularies mislabel plans | M | M | ADR-4 SSOT + normalization table; `mb-drift.sh` #13 already guards canonical vocab |
| Prior-art specs treated as running code (they are unimplemented) | M | M | ADR-1 declares them authoritative-DESIGN, not code; verify scripts absent before extending |
| Worktree + symlinked-bank concurrency races on marker-fenced files | M | H | Serialize all bank mutations under `sc_lock` (REQ-UO-034) |
| Budget partition across concurrent tracks undesigned (single `.work-budget.json`) | M | M | Per-track reservation wrapper over `mb-work-budget.sh`; halt-on-budget per track |
| DRY debt (role-detection duplicated in `mb_work_items.py` + `mb-work-plan.sh`) compounded if built upon | L | M | Consolidate role-detection into `mb_work_items.py` before the runner depends on it |
| `actualize` claims a REQ done on test *presence* not *pass* | M | H | REQ-UO-044: require `mb-test-run.sh` actually ran green via the gate, not `traceability-gen` grep |

## Open questions (resolve before `tasks.md`)

1. **ADR-1 confirmation** — umbrella-absorb prior-art specs, or keep separate? (Recommended: absorb.)
2. **Soft-collision threshold** — at what `co_change` weight does a non-overlapping phase pair become a serialize constraint?
3. **Budget reservation policy** — how is the global token budget partitioned across N concurrent tracks?
4. **Primary headless adapter** — is `claude -p` viable in CI (it obeys `CLAUDE.md`), or is Codex/OpenCode the primary cron path?
5. **flag-ON-smoke config schema** — where is the flag set (env/config/per-project) and how are smoke keys selected (pytest marker / id list in `pipeline.yaml`)?

> `tasks.md` is intentionally deferred until the user reviews this PRD and answers the open questions (especially ADR-1).
