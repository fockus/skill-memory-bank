---
type: spec-design
topic: parallel-team-execution
status: draft
created: 2026-06-14
linked_requirements: requirements.md
linked_tasks: tasks.md
---

# Design: parallel-team-execution

> Architecture, interfaces, and decisions backing requirements.md.
> SKELETON — section structure + reuse map + decision stubs. Flesh out the `<!-- TODO -->` parts.

## Architecture

The feature is a thin **orchestration layer** over `/mb work` that adds two new execution modes beside the
existing sequential one, plus a pattern selector and a monitoring/verification spine. **Nothing here owns a
dispatch loop** — the host agent's native subagent/Team features are the runtime (REQ-PTE-052).

```
/mb work <target> [--mode auto|sequential|subagent|team] [--pattern <name>]
  │
  ├─ 1. decompose      → dependency-disjoint work units (DAG)        [REQ-PTE-001/005]
  ├─ 2. select mode    → scope→mode matrix + deterministic floor     [REQ-PTE-012/022]
  ├─ 3. select pattern → pattern catalogue (templates/*.md)          [REQ-PTE-020/021]
  ├─ 4. dispatch
  │      ├─ sequential   = today's Mode A (byte-identical)           [REQ-PTE-050]
  │      ├─ subagent     = N implementers, worktree-per-unit         [REQ-PTE-002/003/004]
  │      └─ team         = persistent teammates (TeamCreate)         [REQ-PTE-010/011]
  ├─ 5. monitor        → live per-unit status in mb-flow fence       [REQ-PTE-030/031/032]
  ├─ 6. verify (code)  → mb-flow-verify.sh + severity-gate per unit  [REQ-PTE-040/041/042]
  └─ 7. integrate      → sequential-after-unit-green merge           [REQ-PTE-006]
```

**Reuse map (compose, do not reimplement — REQ-PTE-024/051):**
- `parallel-pipeline` engine → wave dispatch, worktree layer, DAG validation, budget reservation.
- `dynamic-flow` → `mb-flow-verify.sh` firewall + `<!-- mb-flow -->` runtime fence + route-floor pattern.
- review-ensemble (`work.md`:326) → the proven parallel-dispatch primitive to generalize into patterns.
- `composable-work-pipeline` → flag/preset/`pipeline.yaml` stage resolution that `--mode`/`--pattern` plug into.

<!-- TODO: a component diagram; the exact boundary between this layer and parallel-pipeline's /mb run. -->

## Interfaces

Define contracts as deterministic scripts (POSIX sh / Python) + skill prompts (agent-native, no runtime).

- **Work-unit decomposer** — input: plan/spec + `git diff --name-only` scope; output: a unit DAG (id, files, deps, role). <!-- TODO: format (JSON Lines? reuse roadmap depends_on topo-sort?) -->
- **Mode selector** — input: unit DAG + scope signals; output: one of `sequential|subagent|team` + justification. Deterministic floor forces ≥ wave/team on protected/interface/multi-plan scope. <!-- TODO: matrix thresholds -->
- **Pattern catalogue** — `patterns/<name>.md` declarative templates (phases, per-phase skill, boundary checks, retry, fallback). <!-- TODO: schema; minimal set: sequential, parallel-fanout, pipeline, wave-DAG, loop-until-dry, adversarial-verify, judge-panel -->
- **`pipeline.yaml` schema additions** — first-class `execution`/`implement.parallelism`/`patterns` block consumed by the engine and validated by `mb-pipeline-validate.sh`. <!-- TODO: exact keys + bounds (max_parallel>0, mode enum, fallback required) -->
- **Runtime fence** — `<!-- mb-flow -->…<!-- /mb-flow -->` block carrying mode, pattern, per-unit status, team membership. Idempotent regen, content outside fence byte-preserved. <!-- TODO: field list -->
- **Verifier hook** — reuse `mb-flow-verify.sh` (exit 0/1/2) per unit before integration; sole completion authority.

<!-- TODO: define each as a real contract (inputs/outputs/error conditions) anchoring contract tests. -->

## Decisions

ADR-style stubs — fill Decision/Rationale.

- **D1 — Worktree granularity.** Context: parallel-pipeline isolates per *plan*; this spec parallelizes *units within* a plan. Options: (a) worktree-per-unit, (b) shared tree + file-lease, (c) worktree-per-plan only. <!-- Decision: ? Rationale: ? Consequences: ? -->
- **D2 — Team-mode transport.** Context: native Team = TeamCreate + SendMessage (persistent) vs ephemeral subagents. Options: (a) Team only on hosts that expose it + degrade, (b) emulate team via long-lived subagents. <!-- Decision: ? -->
- **D3 — Pattern-as-code boundary.** Context: REQ-PTE-023 wants reproducible patterns expressible as workflow-as-code. Options: (a) declarative `.md` templates only, (b) `.md` + optional coded workflow script the orchestrator runs and reads structured output from. <!-- Decision: ? -->
- **D4 — Where the scope→mode matrix lives.** Options: (a) deterministic script, (b) skill prompt + deterministic floor script (like dynamic-flow analyze-task). <!-- Decision: ? -->
- **D5 — pipeline.yaml schema vs backward-compat.** Must make the block first-class WITHOUT breaking existing files (additive; validator accepts absence). <!-- Decision: ? -->
- **D6 — Opt-in gate.** Mirror parallel-pipeline's major-version/opt-in so default `/mb work` stays byte-identical (REQ-PTE-050). <!-- Decision: flag? pipeline.yaml? version gate? -->

## Risks & mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Token cost multiplies with in-flight parallel context | H | H | Per-wave budget reserve + `hard_stop_tokens` (reuse `mb-work-budget.sh`); cap `max_parallel`; mode=auto picks sequential for small scope (NFR-PTE-003) |
| Worktree merge conflict at integration | M | M | Dependency-disjoint decomposition (no shared files) + sequential-after-green merge + halt-and-surface on conflict (REQ-PTE-006, edge cases) |
| Host lacks native Team / subagents | M | M | Degrade ladder team→subagent→sequential + stderr WARN; correctness preserved (REQ-PTE-007/013) |
| pipeline.yaml schema drift / inert config (today's bug) | M | M | First-class schema + `mb-pipeline-validate.sh` rejects invalid config (REQ-PTE-060/061/062); contract tests |
| LLM self-certifies completion | M | H | Deterministic firewall is sole authority; red verify blocks done (REQ-PTE-040/042) |
| Decomposition mis-identifies a hidden dependency → race | L | H | Worktree isolation prevents file race; deterministic floor forces serial on interface/protected scope (REQ-PTE-022) |
| Scope creep vs parallel-pipeline / dynamic-flow | M | M | Compose, do not reimplement; explicit reuse map; this spec adds only the thin glue (REQ-PTE-024/051) |
