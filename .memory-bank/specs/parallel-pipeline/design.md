---
spec_id: parallel-pipeline
topic: Parallel pipeline — configurable wave-based DAG executor with worktree isolation
status: draft
author: brainstorming-session
created: 2026-05-24
parent_roadmap: harness-upgrade (S5 of S1..S5)
addresses_gaps: [parallel-execution, configurable-pipeline, multi-plan-orchestration]
depends_on_specs: [reviewer-2.0, work-loop-v2]
soft_depends_on_specs: [handoff-v2, cost-multi-model]
breaking_changes: no (additive — new command, new yaml section, existing /mb work unchanged)
inspired_by: https://github.com/fockus/claude-skill-build
---

# Parallel pipeline — Design (S5 of harness-upgrade)

Adds a configurable, wave-based pipeline engine alongside the existing `/mb work` command. The engine dispatches multiple subagents in parallel, supports loops between phases, gates between waves, and runs each plan inside its own git worktree.

Inspired by `fockus/claude-skill-build` (wave model + worktree isolation). Schema-compatible with that skill at the yaml level; the engine is our own.

## 1. Goals & Non-goals

### Goals

- **G1** — Configurable pipeline via `pipeline.yaml`: phases / roles / parallelism / on_failure / loop_target / gate. DAG validated at load time.
- **G2** — Default OOTB workflow (`references/pipeline.default.yaml`): `implement → test → architect-review → fix → judge-gate` with loops (test fail → implement; review CHANGES_REQUESTED → fix).
- **G3** — Wave-based execution: within a phase, all items dispatched in parallel; phases separated by `wait` of all Tasks.
- **G4** — Worktree-per-plan: every plan runs inside its own git worktree. Items inside one plan share a tree (the plan disciplines scope).
- **G5** — Opt-in: new command `/mb run`. The existing `/mb work` (without flags) preserves current sequential behavior — full backward compat.
- **G6** — Schema-compatible with claude-skill-build (common keys `phases / role / parallelism / on_failure / gate`); the engine itself is independent.
- **G7** — Budget control: per-wave reservation check + global `hard_stop_tokens` — fail-fast on exceed.
- **G8** — Cross-plan parallel execution. `/mb run plan-1 plan-2 plan-3` runs all in their own worktrees, then merges sequentially.
- **G9** — Cross-agent dispatch via adapter layer. First cut: Claude Code (native parallel), Pi (native parallel), Codex/OpenCode (sequential fallback).
- **G10** — `pivot_on_stagnant` integration with S2 (work-loop-v2): when reviewer's `progress_trend` is stagnant for N cycles, automatically escalate via `mb-architect`.
- **G11** — **Multi-provider per-phase model dispatch.** Each phase can declare its own model (e.g., `judge` runs GPT-5.5 while `implement` runs Claude Sonnet). Cross-provider invocation goes through a host-agnostic resolver: in Claude Code via a wrapping skill (e.g., `openai-gpt-skill`), in Pi/Codex/OpenCode via their native CLI/SDK. Default behaviour preserved: empty `model:` field → host's default Anthropic model + Task tool.

### Non-goals

- Native streaming of partial model outputs back into orchestrator state — backlog (I-043).
- Auto-selection of cheapest passing model per phase via historical telemetry — backlog (I-044).
- Worktree per item (sub-isolation within a plan) — backlog (I-036).
- DAG cycles outside `loop_target` (e.g., A → B → C → A through arbitrary paths) — backlog (I-037).
- Dynamic role creation at runtime — backlog (I-038).
- Real-time UI / progress bars — backlog (I-039).
- Auto-merge conflict resolution via mb-architect — backlog (I-040).
- Engine sharing with claude-skill-build (extracted shared package) — backlog (I-041).
- Full Python re-write of the executor — backlog (I-042).
- Replace `/mb work` semantics — never (additive only).

## 1.5 Operating modes — preserved economic vs new parallel

This sub-project is **additive**. The skill ends up with two distinct operating modes that the user picks per task:

### Mode A — economic / sequential (existing `/mb work`, default)

- Main agent does everything itself: reads plan, implements stages, dispatches sub-agents (mb-reviewer / mb-test-runner) only when delegation is explicitly needed.
- One worktree (the current one), one stage at a time, sequential fix-cycles.
- **Cheapest in tokens**, easiest to debug, predictable for small/medium plans.
- **No behavior change.** This spec does NOT touch `/mb work`. It remains the default and unchanged path.

### Mode B — parallel / wave-pipeline (new `/mb run`, opt-in)

- Pipeline engine reads `pipeline.yaml`, dispatches multiple sub-agents in parallel per wave.
- Worktree per plan; multi-plan parallel; loops; gates; pivots; budget reserves.
- **Faster in wall-clock time** when items are independent and the plan is large.
- **More expensive in tokens** because parallel dispatch multiplies in-flight context.
- Opt-in: requires explicit `/mb run` invocation.

### Decision matrix

| Situation | Recommended mode |
|-----------|------------------|
| Small plan (≤3 stages, low risk) | A (`/mb work`) — overhead of pipeline not worth it |
| Mid-size plan with independent stages | B (`/mb run --preset=fast`) — fast + cheap |
| Large plan with dependencies + review loops | B (`/mb run --preset=standard`) — full pipeline pays off |
| Critical or security-sensitive plan | B (`/mb run --preset=strict`) — adds security + verify phases |
| Multiple plans queued (e.g., a phase of sub-projects) | B (`/mb run plan-1 plan-2 ...`) — parallel by design |
| Budget very tight, exploratory work | A (`/mb work`) — total control over token spend |

### Hard guarantee

`/mb work` semantics are **frozen** by this spec. Any future change to it is a separate decision, never bundled with `/mb run` work.

## 2. Architecture overview

```
USER: /mb run plan-A                     (single plan)
USER: /mb run plan-A plan-B plan-C       (multi-plan)
                │
                ▼
   commands/run.md  (NEW thin entrypoint)
                │
                ▼
   scripts/mb_pipeline_plan.py  (Python planner)
     • parse pipeline.yaml + selected preset
     • parse each plan/spec → items
     • validate DAG (cycles only with max_loops)
     • emit exec_graph.json  (pure data)
                │
                ▼
   exec_graph.json  (file-based handoff)
                │
                ▼
   scripts/mb-pipeline-run.sh  (bash executor)
     FOR each plan in parallel:
       git worktree add .git/mb-worktrees/<topic>
       symlink .memory-bank into worktree
       FOR each wave (sequential):
         emit wave-<plan>-<phase>-dispatches.json
         hand control to active adapter for dispatch
         wait for *.result.json files
         evaluate phase gate / on_failure
       squash worktree commits → cherry-pick to root
       remove worktree
                │
                ▼
   adapter-specific dispatch
     • Claude Code → main agent reads dispatches.json,
                     issues N parallel Task() in one response
     • Pi          → adapters/pi/dispatch.ts spawns subagents
     • Codex       → adapters/codex/dispatch.sh sequential CLI loop
     • OpenCode    → adapters/opencode/dispatch.sh sequential CLI loop
```

Reused (unchanged) primitives:
- `scripts/mb-work-severity-gate.sh`
- `scripts/mb-work-budget.sh`
- `scripts/mb-work-protected-check.sh`
- `scripts/mb-review.sh` (post-S1)
- `scripts/mb-done-gates.sh` (post-S3, if present)
- `agents/*` dispatched via Task (or per-adapter native subagent API)

## 3. File inventory

### New files

| Path | Kind | Purpose |
|------|------|---------|
| `commands/run.md` | command | Thin entry point for `/mb run` |
| `scripts/mb_pipeline_plan.py` | python | Planner — yaml + plans → exec_graph.json |
| `scripts/mb-pipeline-run.sh` | bash | Executor — worktree lifecycle + wave coordination |
| `scripts/mb-work-budget-wave.sh` | bash | Wrap existing budget check for per-wave reservation |
| `scripts/mb-pipeline-merge.sh` | bash | Sequential cherry-pick merge phase + conflict surface |
| `scripts/mb-pipeline-state.sh` | bash | Read/write `.memory-bank/tmp/state-<plan>.json` for resume |
| `scripts/mb-pipeline-model-resolve.sh` | bash | **G11** — resolve `phases[].model` alias → JSON with provider/id/via/invocation_hint per §10.5 |
| `adapters/claude-code/dispatch.md` | doc | Claude Code dispatch protocol — main agent reads dispatches.json, issues N Task() in one response; routes `via: skill:<name>` through Skill tool |
| `adapters/pi/dispatch.ts` | TypeScript | Pi native parallel subagent dispatch |
| `adapters/codex/dispatch.sh` | bash | Codex sequential CLI loop fallback |
| `adapters/opencode/dispatch.sh` | bash | OpenCode sequential CLI loop fallback |
| `tests/bats/test_mb_pipeline_run_single_plan.bats` | bats | Single-plan end-to-end |
| `tests/bats/test_mb_pipeline_run_multi_plan.bats` | bats | Multi-plan parallel execution |
| `tests/bats/test_mb_pipeline_loops.bats` | bats | loop_back semantics with max_loops |
| `tests/bats/test_mb_pipeline_budget_reserve.bats` | bats | per-wave reserve halt; global hard stop |
| `tests/bats/test_mb_pipeline_cherry_pick_conflict.bats` | bats | Conflict → fail-fast, worktree preserved |
| `tests/bats/test_mb_pipeline_resume_after_halt.bats` | bats | State cache resume; `--restart` flag |
| `tests/bats/test_mb_pipeline_gate_on_entry.bats` | bats | Skip fix phase when review APPROVED |
| `tests/bats/test_mb_pipeline_dispatch_specs_format.bats` | bats | dispatches.json contract validation |
| `tests/bats/test_mb_pipeline_pivot_on_stagnant.bats` | bats | S2 integration: pivot_via_architect on stagnant trend |
| `tests/pytest/test_pipeline_plan_schema_validation.py` | pytest | Planner DAG validation |
| `tests/pytest/test_pipeline_plan_preset_resolution.py` | pytest | Layered merge of presets |
| `tests/pytest/test_pipeline_plan_emit_exec_graph.py` | pytest | exec_graph.json shape |
| `tests/pytest/test_pipeline_plan_merge_order.py` | pytest | depends_on → merge_order |
| `tests/pytest/test_pipeline_model_registry.py` | pytest | **G11** — registry parsing, alias validation, `via:` regex |
| `tests/bats/test_mb_pipeline_model_resolve.bats` | bats | **G11** — resolver output JSON contract per §10.5 |
| `tests/bats/test_mb_pipeline_model_fallback.bats` | bats | **G11** — `on_model_unsupported` policy across adapters |
| `docs/parallel-pipeline.md` | docs | User-facing guide (includes G11 "judge via GPT-5.5" worked example) |

### Project-owned (runtime)

- `.git/mb-worktrees/<plan-topic>/` — per-plan worktrees
- `.memory-bank/tmp/wave-<plan>-<phase>-dispatches.json` — per-wave dispatch specs
- `.memory-bank/tmp/result-<dispatch_id>.json` — per-dispatch results
- `.memory-bank/tmp/state-<plan>.json` — plan execution state cache (for resume)

### Modified files

| Path | Change |
|------|--------|
| `references/pipeline.default.yaml` | New top-level section `pipeline.{version, default_pipeline, presets, execution}` with 3 presets (fast/standard/strict) per §4. Existing top-level keys unchanged. |
| `commands/work.md` | Add note that `/mb work` is the sequential path; `/mb run` is the parallel pipeline path. No behavior changes. |
| `scripts/mb-doctor.sh` (or wherever doctor checks live) | Add `check_orphan_worktrees` (>7 days under `.git/mb-worktrees/` → warn). |
| `install.sh` | Distributes new adapter files; verifies `.git/mb-worktrees/` is gitignored (it is by default under `.git/`); registers `commands/run.md`. |
| `agents/*.md` | (Optional, low-cost) add `avg_tokens_per_dispatch` frontmatter for budget estimation; falls back to 8000 if absent. |
| `CHANGELOG.md` | Document the new command + new yaml section + new adapters. |

## 4. Pipeline YAML schema

The new top-level `pipeline:` block lives in `references/pipeline.default.yaml` (skill baseline) and optionally `.memory-bank/pipeline.yaml` (project override).

```yaml
pipeline:
  version: 1
  default_pipeline: standard

  # G11 — model registry. Aliases decouple phases from concrete model IDs
  # and from the host-specific invocation mechanism. Empty / absent registry
  # falls back to host default (Anthropic via native Task dispatch).
  models:
    judge_default:
      provider: openai            # anthropic | openai | google | local | <custom>
      id: gpt-5.5
      via: skill:openai-gpt       # native | skill:<name> | cli:<cmd>
    architect_premium:
      provider: anthropic
      id: claude-opus-4-7
      via: native                 # default Task dispatch on Claude Code
    fast_review:
      provider: anthropic
      id: claude-haiku-4-5
      via: native

  presets:

    standard:
      phases:
        - name: implement
          role: developer
          parallelism: per_item
          on_failure: { kind: retry, max: 3 }
        - name: test
          role: tester
          parallelism: per_item
          on_failure: { kind: loop_back, to: implement, max_loops: 3 }
        - name: review
          role: architect-reviewer
          model: architect_premium   # G11 — explicit per-phase model
          parallelism: single
          on_failure: { kind: loop_back, to: implement, max_loops: 2 }
        - name: fix
          role: developer
          parallelism: per_issue
          gate_on_entry: review_changes_requested
          on_failure: { kind: halt }
        - name: judge
          role: judge
          model: judge_default       # G11 — cross-provider GPT-5.5 judge
          parallelism: none
          gate:
            kind: hard
            severity_blocker_max: 0
            severity_major_max: 0
            severity_minor_max: 3

    fast:
      phases:
        - { name: implement, role: developer, parallelism: per_item }
        - { name: review, role: reviewer, model: fast_review, parallelism: per_item,
            gate: { kind: hard, severity_blocker_max: 0 } }

    strict:
      phases:
        - { name: implement, role: developer, parallelism: per_item }
        - { name: test, role: tester, parallelism: per_item,
            on_failure: { kind: loop_back, to: implement, max_loops: 3 } }
        - { name: security, role: security-reviewer, parallelism: single,
            on_failure: { kind: loop_back, to: implement, max_loops: 2 } }
        - { name: review, role: architect-reviewer, model: architect_premium, parallelism: single,
            on_failure: { kind: loop_back, to: implement, max_loops: 2 } }
        - { name: fix, role: developer, parallelism: per_issue,
            gate_on_entry: review_changes_requested }
        - { name: verify, role: plan-verifier, parallelism: per_item,
            gate: { kind: hard } }
        - { name: judge, role: judge, model: judge_default, parallelism: none,
            gate: { kind: hard } }

  execution:
    max_concurrent_tasks: 6
    budget_per_wave_pct: 30
    budget_global_hard_stop: 190000
    worktree_root: ".git/mb-worktrees"
    cleanup_orphan_worktrees_days: 7
    active_adapter: claude-code
    fallback_to_sequential: true
    # G11 — if a phase requests a model whose `via:` is unsupported by the
    # active adapter (e.g., `skill:openai-gpt` on Codex), what should we do?
    on_model_unsupported: fallback  # fallback | halt | warn
```

### Field semantics

- `phases[].parallelism ∈ {per_item, per_issue, single, none}`
  - `per_item` — one dispatch per work item; runs in parallel within the wave.
  - `per_issue` — one dispatch per unresolved issue from the previous review (used by `fix`).
  - `single` — one dispatch per plan (one architect reviewing all items together).
  - `none` — pure phase with no dispatches (e.g., aggregation gates).
- `phases[].on_failure.kind ∈ {retry, loop_back, halt, escalate, pivot_on_stagnant}`
- `phases[].gate.kind ∈ {hard, soft, none}`
- `phases[].gate_on_entry` — phase is skipped if the named signal was not emitted by a previous phase (e.g., `review_changes_requested`).
- `phases[].model` — optional alias from the top-level `pipeline.models:` registry. If absent → host default (Anthropic via native Task dispatch on Claude Code, native subagent API on Pi, default CLI model on Codex/OpenCode). See §10.5.
- `pipeline.models.<alias>.via ∈ {native, skill:<name>, cli:<cmd>}`:
  - `native` — use the host agent's native dispatch (Task tool / Pi subagent API / CLI flag).
  - `skill:<name>` — invoke a named skill that wraps the model (e.g., `skill:openai-gpt` in Claude Code calls a user-installed wrapper skill).
  - `cli:<cmd>` — shell out to a custom command (e.g., `cli:openai chat -m gpt-5.5`).
- `execution.on_model_unsupported ∈ {fallback, halt, warn}` — adapter behaviour when the active host cannot honour a phase's `model.via:`:
  - `fallback` — silently use host default + log to `state-<plan>.json`.
  - `halt` — exit ≠ 0 before dispatching the phase.
  - `warn` — fallback + stderr WARN per dispatch.

### Validation rules (planner exit ≠ 0 on violation)

- Phase `name` unique within preset.
- `on_failure.to` references an existing phase.
- Cycles allowed only when every step of the cycle has `max_loops`.
- All referenced roles map to an entry in `pipeline.yaml:roles.<role>.agent`.
- `parallelism` value in the allowed set.
- Every `phases[].model` references an existing key in `pipeline.models`.
- Every `pipeline.models.<alias>.via` matches `^(native|skill:[a-z0-9_\-]+|cli:.+)$`.
- `execution.on_model_unsupported` ∈ allowed set.

### Layered merge

Project `.memory-bank/pipeline.yaml:pipeline.presets.<name>.phases` either fully replaces or partially overrides the default. The merge is per-phase (matched by `name`); unmatched phases retain default behavior.

## 5. Worktree lifecycle

```
SINGLE PLAN
  resolve baseline_commit from plan frontmatter
  git worktree add .git/mb-worktrees/<plan-topic> <baseline_commit>
  symlink .memory-bank → original .memory-bank/   ← so checklist/progress writes still land in main bank
  cd into worktree, execute all waves
  judge-gate PASS:
    git -C <worktree> rev-list <baseline>..HEAD | git diff-tree → squash to one commit on a temp branch
    git cherry-pick <squashed-commit> on original branch
    git worktree remove .git/mb-worktrees/<plan-topic>
  judge-gate FAIL or any halt:
    preserve worktree
    stderr: structured error + worktree path
    exit 2

MULTI PLAN
  For each plan in parallel: do the SINGLE-PLAN steps up to "judge-gate PASS, squashed-commit ready".
  Sequential merge phase (Lead):
    For plan in merge_order:
      git cherry-pick <plan's squashed-commit>
      on conflict: git cherry-pick --abort, halt, preserve worktrees for plans not yet merged.
  Remove worktrees for plans that successfully merged.
```

### Why symlink `.memory-bank`

All agents dispatched inside the worktree need to read/write the SAME `.memory-bank/` (checklist, progress, status, traceability). Without a symlink, each worktree would have its own divergent copy, and the final cherry-pick would conflict on every shared bank file.

Symlink, not bind mount, because git worktrees are designed for additive (not isolated) views; the bank is metadata, not source.

### Orphan worktree cleanup

`scripts/mb-doctor.sh` adds `check_orphan_worktrees`:

- For each directory under `.git/mb-worktrees/` older than `cleanup_orphan_worktrees_days`:
  - WARN: `orphan worktree <path> (age <N>d). To remove: git worktree remove --force <path>`
- Never auto-deletes — user-driven to protect against losing uncommitted work.

### Cherry-pick conflict policy (first cut)

- Conflict → `git cherry-pick --abort` → halt the merge phase
- Worktrees of unmerged plans preserved
- stderr surfaces: `<conflicted files>`, plan topics, suggested next steps:
  - `cd .git/mb-worktrees/<topic>` to inspect
  - `/mb run --merge-resume <topic>` to retry merge after resolution (future command — backlog)
- Auto-resolve via mb-architect — backlog (I-040).

## 6. Planner contract

```
$ python scripts/mb_pipeline_plan.py \
    --plans path/to/plan-1.md [path/to/plan-2.md ...] \
    [--preset standard|fast|strict] \
    [--out exec_graph.json]
```

Output (`exec_graph.json`):

```json
{
  "schema_version": 1,
  "preset": "standard",
  "execution": {
    "max_concurrent_tasks": 6,
    "budget_per_wave_pct": 30,
    "budget_global_hard_stop": 190000,
    "worktree_root": ".git/mb-worktrees",
    "active_adapter": "claude-code"
  },
  "plans": [
    {
      "plan_id": "2026-05-23_feature_reviewer-v2",
      "topic": "reviewer-v2",
      "baseline_commit": "bf4fceea...",
      "worktree_path": ".git/mb-worktrees/reviewer-v2",
      "items": [
        { "item_id": "stage-1", "title": "Orchestrator skeleton...", "covers": [] },
        { "item_id": "stage-2", "title": "...", "covers": [] }
      ],
      "phases": [
        {
          "phase_id": "implement",
          "role": "developer",
          "parallelism": "per_item",
          "dispatches": [
            { "dispatch_id": "stage-1", "subagent_type": "mb-developer",
              "expected_artifact": ".memory-bank/tmp/result-stage-1.json" },
            { "dispatch_id": "stage-2", "subagent_type": "mb-developer",
              "expected_artifact": ".memory-bank/tmp/result-stage-2.json" }
          ],
          "on_failure": { "kind": "retry", "max": 3 },
          "gate": null
        },
        {
          "phase_id": "test",
          "role": "tester",
          "parallelism": "per_item",
          "dispatches": [...],
          "on_failure": { "kind": "loop_back", "to": "implement", "max_loops": 3 }
        }
      ]
    }
  ],
  "merge_order": ["reviewer-v2"]
}
```

The planner is a **pure function**: same inputs → same output. No side effects. Useful for unit testing (pytest) and for `cat exec_graph.json | jq` debugging.

## 7. Executor contract

```
$ bash scripts/mb-pipeline-run.sh \
    --graph exec_graph.json \
    [--dry-run] \
    [--continue-on-failed-plan] \
    [--restart]
```

Pseudocode:

```bash
load exec_graph.json
init_budget_global $(jq .execution.budget_global_hard_stop graph)

for plan in plans[]:
    if state_exists(plan) and not RESTART:
        resume from last_phase
    else:
        create_worktree $plan.worktree_path $plan.baseline_commit
        symlink_memory_bank_into $plan.worktree_path

    for phase in plan.phases[from last_phase:]:
        if not budget_ok($execution.budget_per_wave_pct):
            halt "global budget exhausted before phase $phase"

        if phase.gate_on_entry and not signal_present(phase.gate_on_entry):
            mark_skipped; continue

        emit_dispatches_json $plan $phase
            → .memory-bank/tmp/wave-<plan>-<phase>-dispatches.json

        hand_off_to_adapter $active_adapter \
            < dispatches.json
            (Claude Code: returns to main agent which issues N Task())
            (Pi: spawns native subagents)
            (Codex/OpenCode: sequential CLI loop)

        wait for all expected_artifact files
        collect_results

        save_state $plan $phase

        evaluate phase.gate (if any):
            FAIL hard → consult on_failure:
                retry            → re-emit dispatches, increment counter
                loop_back        → next_phase = target, increment loop counter
                escalate         → dispatch escalation role then continue
                pivot_on_stagnant→ if trend stagnant N times: pivot_via_architect (S2)
                                   else: retry
                halt             → exit 2

    squash worktree commits → cherry-pick to root branch

    if cherry-pick conflict:
        git cherry-pick --abort
        preserve worktree
        if --continue-on-failed-plan: continue with next plan
        else: halt

    remove worktree
```

### dispatches.json contract

```json
{
  "wave_id": "reviewer-v2/implement/cycle-1",
  "role": "developer",
  "model_class": "balanced",
  "parallelism": "per_item",
  "max_concurrent": 6,
  "dispatches": [
    {
      "dispatch_id": "stage-1",
      "subagent_type": "mb-developer",
      "prompt": "<fully-assembled prompt with item context>",
      "expected_artifact": ".memory-bank/tmp/result-stage-1.json"
    }
  ]
}
```

Each adapter consumes this format and translates it into native dispatch primitives.

## 8. Failure semantics

### Loop counter scope

Per `(source_phase, target_phase)` pair. Independent counters:
- `test → loop_back implement` increments `test_to_implement_loops`.
- `review → loop_back implement` increments `review_to_implement_loops`.

These do not share state. Each has its own `max_loops`.

### Reaching max_loops

`max_loops` reached → halt the plan. Worktree preserved, structured error.

### `pivot_on_stagnant` (S2 integration)

When `on_failure.kind == pivot_on_stagnant`:
- Read latest reviewer verdict's `progress_trend` field (S2 must be deployed).
- If trend is `stagnant` for `stagnant_threshold` consecutive cycles → dispatch `mb-architect` to write a redesign sketch to `.memory-bank/notes/<date>_pivot-<topic>.md`, then re-dispatch the implementer with the sketch.
- If trend is `improving` or `regressing` → behave as `retry`.

### Gate kinds

- `hard` — FAIL halts the plan unless `on_failure` rescues.
- `soft` — FAIL emits WARN, continues.
- `none` — phase has no gate (e.g., pure implement phase).

## 9. Budget control

- **Global hard stop**: `execution.budget_global_hard_stop` (default 190000). Identical to `sprint_context_guard.hard_stop_tokens`. On exceed: halt.
- **Per-wave reserve**: `execution.budget_per_wave_pct` (default 30%). Before each wave, executor reserves `wave_estimate × 1.3` tokens. If available budget is less, the wave is skipped and the plan halts.
- **Wave estimate**: per-dispatch budget read from `agents/<role>.md` frontmatter `avg_tokens_per_dispatch`; default 8000.
- **Existing `mb-work-budget.sh`** is reused for per-dispatch tracking. A new wrapper `mb-work-budget-wave.sh` aggregates per-wave reservation.

## 10. Cross-agent dispatch (adapters)

### Capability matrix

| Agent | Parallel dispatch | Worktree | Fallback |
|-------|------------------|----------|----------|
| **Claude Code** | ✅ native (multi-Task in one response) | ✅ | — |
| **Pi** | ✅ native (Pi subagent API) | ✅ | — |
| **Codex** | ⚠️ sequential CLI loop | ✅ | sequential |
| **OpenCode** | ⚠️ sequential CLI loop | ✅ | sequential |
| **Cursor / Windsurf / Cline / Kilo** | TBD (not in S5 scope) | ⚠️ | sequential |

### Adapter resolution

`execution.active_adapter` selects the dispatch implementation. Set by `install.sh` based on the detected agent, or by the user.

### Claude Code adapter

`adapters/claude-code/dispatch.md` documents the protocol:

1. Executor writes `wave-<plan>-<phase>-dispatches.json`.
2. Control returns to `commands/run.md`, which instructs the main agent to read the file and issue N `Task()` calls in a single response — Claude Code dispatches them in parallel internally.
3. Each Task writes its result to the `expected_artifact` path.
4. Executor resumes via `wait_for_artifacts` loop.

### Pi adapter

`adapters/pi/dispatch.ts` (TypeScript, native to Pi):

- Reads dispatches.json.
- Calls Pi native subagent spawn API in parallel for each dispatch.
- Writes results to `expected_artifact` paths.
- Returns control to executor.

### Codex / OpenCode adapters

`adapters/{codex,opencode}/dispatch.sh`:

- Sequential loop over `dispatches[]`.
- Each iteration runs the CLI (`codex run` / `opencode run`) with the assembled prompt.
- Result captured into `expected_artifact`.
- stderr WARN: `running in sequential mode — <agent> does not natively support parallel subagents`.

## 10.5 Multi-provider model dispatch (G11)

**Motivation.** Judge / reviewer phases benefit from an independent model than the implementer — both to avoid same-model rubber-stamping and to optimise cost (e.g., GPT-5.5 as judge over Claude Sonnet implementer; or Claude Opus as judge over Haiku implementer). The pipeline must support this without leaking provider details into role-agent prompts.

### Three-layer resolution

```
phases[].model: <alias>                  ← phase declaration
        │
        ▼
pipeline.models.<alias>:                 ← registry entry
  provider: openai
  id: gpt-5.5
  via: skill:openai-gpt
        │
        ▼
adapters/<active>/model-invoke.<ext>     ← host-specific implementation
```

### Resolver script

`scripts/mb-pipeline-model-resolve.sh <plan> <phase-name>` outputs JSON:

```json
{
  "alias": "judge_default",
  "provider": "openai",
  "id": "gpt-5.5",
  "via": "skill:openai-gpt",
  "host_supported": true,
  "fallback_used": false,
  "invocation_hint": {
    "kind": "skill",
    "name": "openai-gpt",
    "args": { "model": "gpt-5.5" }
  }
}
```

Called by the executor before assembling each `dispatches.json`. Each dispatch entry gains a `model:` sub-object — the adapter decides what to do with it.

### Per-adapter implementation

| Adapter | `via: native` | `via: skill:<name>` | `via: cli:<cmd>` |
|---------|---------------|---------------------|-------------------|
| **Claude Code** | `Task()` with default Anthropic model | Main agent invokes the named skill via Skill tool, passing prompt + `expected_artifact` path | Adapter shells out and captures stdout → `expected_artifact` |
| **Pi** | Pi native subagent API | Pi extension wrapping the skill (if Pi exposes skill bridge); else fallback per `on_model_unsupported` | Adapter shells out from Pi process |
| **Codex** | `codex run` with default model | Not supported in S5 → fallback | `codex run --model-cmd=...` if Codex provides hook; else shell-out |
| **OpenCode** | `opencode run` with default model | OpenCode plugin if available; else fallback | Shell-out |

### Fallback behaviour

When the active adapter cannot honour `via:`:
1. Read `execution.on_model_unsupported`.
2. If `fallback` (default) — use host default model + append `model_fallback: { alias, reason }` to `state-<plan>.json`.
3. If `halt` — executor exits ≠ 0 before dispatching the phase.
4. If `warn` — fallback + stderr WARN once per phase.

### Claude Code "judge via OpenAI" worked example

```yaml
pipeline:
  models:
    judge_gpt:
      provider: openai
      id: gpt-5.5
      via: skill:openai-gpt        # user has this skill installed globally
  presets:
    standard:
      phases:
        - { name: judge, role: judge, model: judge_gpt, parallelism: none,
            gate: { kind: hard } }
```

Execution flow:
1. Executor reaches the `judge` phase.
2. `mb-pipeline-model-resolve.sh` returns `via: skill:openai-gpt`.
3. Executor writes `wave-<plan>-judge-dispatches.json` with `invocation_hint.kind=skill`.
4. Claude Code adapter (main agent) reads the file, sees one dispatch, calls `Skill(skill="openai-gpt", args={prompt: ..., output_path: ...})` instead of `Task(...)`.
5. The skill writes verdict JSON to `expected_artifact`; executor proceeds.

### Discovery and validation

- `scripts/mb-pipeline-validate.sh` extended: for every `via: skill:<name>`, when run in Claude Code, probe `~/.claude/skills/<name>/` and emit `[warn]` if missing (not a hard error — user may install later).
- For `via: cli:<cmd>`, `command -v <first-token>` check on validation.
- For `via: native` with `provider != anthropic` on Claude Code → hard error (no native cross-provider path).

### Security and cost

- API keys for non-Anthropic providers live in the wrapping skill / CLI tool — pipeline.yaml NEVER stores credentials.
- Per-phase tokens charged to whichever provider's account the `via:` targets — pipeline budget tracker (`mb-work-budget-wave.sh`) only sees the Anthropic side. Cross-provider cost telemetry → backlog (I-044).
- `pipeline.models.<alias>` should support optional `cost_hint: { input_per_1k, output_per_1k }` (free-form metadata; not enforced) so docs can compute back-of-envelope projections.

## 11. Testing strategy

### Integration (≈65%)

Bats files per §3 inventory. Each bats stub mocks `Task` dispatch by writing the expected_artifact directly, then asserts executor behavior.

### Python (≈20%)

Pytest files for planner correctness — pure data transformations.

### E2E (≈5%)

One real run on a synthetic two-stage plan; verify git log shows the squashed commit.

### Static

- `shellcheck` on all new bash scripts.
- `ruff` + `mypy` on planner.
- `mb-rules-check.sh` CLEAN on all new files.

## 12. Definition of Done (SMART)

- [ ] `scripts/mb_pipeline_plan.py` exists; ruff + mypy + ≥4 pytest files PASS.
- [ ] `scripts/mb-pipeline-run.sh` exists; shellcheck clean.
- [ ] `scripts/mb-pipeline-merge.sh`, `scripts/mb-pipeline-state.sh`, `scripts/mb-work-budget-wave.sh` exist; shellcheck clean.
- [ ] `commands/run.md` documents flags (`--preset`, `--restart`, `--continue-on-failed-plan`, `--dry-run`).
- [ ] `references/pipeline.default.yaml` has the `pipeline:` block with 3 presets per §4.
- [ ] Schema validation: invalid yaml → planner exit ≠ 0 with structured stderr.
- [ ] 3 presets (fast/standard/strict) work end-to-end on synthetic plans.
- [ ] Single-plan path works: worktree → waves → squash → cherry-pick → cleanup.
- [ ] Multi-plan path works: 2+ plans → 2+ worktrees → sequential merge.
- [ ] Symlink `.memory-bank` into worktree works; bank writes during pipeline land in the main bank.
- [ ] `pivot_on_stagnant` works (S2 integration), verified by bats on a stub reviewer JSON.
- [ ] Pi adapter implements native parallel subagent dispatch.
- [ ] Codex + OpenCode adapters implement sequential fallback.
- [ ] Claude Code adapter documented in `adapters/claude-code/dispatch.md`.
- [ ] `mb-doctor` has `check_orphan_worktrees`.
- [ ] `dispatches.json` contract validated by bats.
- [ ] Resume after halt works; `--restart` invalidates state.
- [ ] **G11 — multi-provider model dispatch:**
  - [ ] `scripts/mb-pipeline-model-resolve.sh` exists; shellcheck clean; resolves alias → JSON per §10.5.
  - [ ] `references/pipeline.default.yaml` ships an example `pipeline.models:` registry with `judge_default` (commented as opt-in for users with an OpenAI wrapping skill).
  - [ ] Schema validator rejects unknown `model:` alias and malformed `via:` values.
  - [ ] Claude Code adapter routes `via: skill:<name>` through `Skill(...)` instead of `Task(...)`.
  - [ ] Codex / OpenCode adapters honour `execution.on_model_unsupported` (fallback/halt/warn).
  - [ ] Pi adapter at minimum honours `via: native` + `via: cli:<cmd>`; `via: skill:<name>` documented as Pi-version-dependent.
  - [ ] `docs/parallel-pipeline.md` has a worked "judge via GPT-5.5 from Claude Code" example end-to-end.
  - [ ] At least 1 pytest case + 2 bats cases cover model resolution + fallback path.
- [ ] All 11 bats files PASS; ≥5 pytest files PASS.
- [ ] `docs/parallel-pipeline.md` exists, ≥250 lines, covers all design sections.
- [ ] `CHANGELOG.md` `[Unreleased]` enumerates new command + yaml block + adapters.
- [ ] `install.sh` distributes new scripts + adapters; idempotent.
- [ ] `/mb verify` clean — no regression in existing bats / pytest.
- [ ] Manual smoke: real `/mb run` on a synthetic 2-stage plan with Claude Code — see parallel dispatch in real session, final commit.

## 13. Hard dependencies

- **S1 (reviewer-v2)** — pipeline calls `scripts/mb-review.sh` for review phases; calibrated reviewer is what makes `progress_trend` reliable.
- **S2 (work-loop-v2)** — `progress_trend` field on reviewer verdicts; `pivot_via_architect` mechanics underpin `pivot_on_stagnant`.

## 14. Soft dependencies

- **S3 (handoff-v2)** — if present, `/mb run` final step invokes `scripts/mb-done-gates.sh` before declaring the plan done. Otherwise falls back to `severity_gate` only.
- **S4 (cost-multi-model)** — if present, role-default model is sourced from `references/model-aliases.yaml` (Anthropic tiers per role). G11's `pipeline.models:` registry **extends** S4: phase-level `model:` field overrides role-default and adds cross-provider support (`via: skill:*` / `via: cli:*`). Without S4: G11 still works, registry entries simply have no role-default to layer on.
- **User-installed model-wrapping skills** — when `pipeline.models.<alias>.via = skill:<name>` (G11), the host agent must have that skill available. In Claude Code: `~/.claude/skills/<name>/`. Missing skill → `on_model_unsupported` behaviour kicks in. Pipeline does NOT ship wrapping skills (separation of concerns: skill = provider integration; pipeline = orchestration).

## 15. Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| Symlink `.memory-bank` breaks on Windows or non-POSIX filesystems | Document; offer mirror+merge fallback as backlog. |
| Cherry-pick conflicts on multi-plan runs block progress | First-cut policy: halt and surface; backlog I-040 for auto-resolve. |
| Parallel Task dispatch exhausts global budget mid-wave | Per-wave reserve check halts before launch; conservative `budget_per_wave_pct=30%`. |
| Adapter for Codex / OpenCode runs sequential and confuses users expecting parallelism | Clear stderr WARN at every wave; documented in `docs/parallel-pipeline.md`. |
| Pi adapter complexity (TypeScript dispatch) blocks S5 ship | Pi marked hard requirement; if blocked, escalate to user before shipping. |
| Loop counters allow infinite churn under noisy reviewer | S1 calibration suite verifies trend stability; planner forces `max_loops` on every cycle. |
| State cache (`state-<plan>.json`) becomes stale on git operations | `--restart` always invalidates; `mb-doctor` can detect mismatch (worktree HEAD vs state). |
| Worktrees accumulate during chaotic interrupted runs | `mb-doctor` orphan check; user-driven cleanup. |
| **G11**: user references a `via: skill:<name>` that isn't installed on the host | `mb-pipeline-validate.sh` probes skill dirs, emits `[warn]`; runtime `on_model_unsupported` policy fires. |
| **G11**: cross-provider judge produces verdicts incompatible with reviewer JSON schema | Wrapping skill MUST output strict schema; pipeline rejects malformed JSON via `mb-work-review-parse.sh`. Doc the schema contract in `docs/parallel-pipeline.md`. |
| **G11**: cross-provider API key leakage via pipeline.yaml | Schema forbids credential fields; documented as "keys live in wrapping skill / shell env, never in registry". Validator scans for common key patterns and rejects. |
| **G11**: cross-provider latency/timeout differs from Anthropic Task | Per-alias optional `timeout_sec:` (free-form); adapter enforces via `timeout` shell builtin or skill-level option. |
| **G11**: cost asymmetry surprises user (judge phase 10× more expensive than implement) | `cost_hint:` metadata on aliases + dry-run shows projected wave cost. Telemetry → backlog I-044. |

## 16. Out-of-scope follow-ups (backlog)

- I-036 — worktree per item (sub-isolation within plan).
- I-037 — DAG cycles outside `loop_target`.
- I-038 — dynamic role creation at runtime.
- I-039 — real-time UI / progress bars.
- I-040 — auto-merge conflict resolution via mb-architect.
- I-041 — extract pipeline engine to a shared package with claude-skill-build.
- I-042 — full Python re-write of the executor.
- I-043 — native streaming of partial model outputs back into orchestrator state (G11 follow-up).
- I-044 — auto-selection of cheapest passing model per phase via historical telemetry (G11 follow-up).

## 17. Open questions to resolve during implementation

- Exact `pivot_on_stagnant` threshold default — start at 2, tune via pivot-log telemetry from S2.
- Whether to lock `.memory-bank/handoff/` (S3) during multi-plan runs — likely yes, since multiple plans could trigger handoff actualize simultaneously.
- Pi subagent API stability — verify before spec close; if unstable, downgrade to sequential fallback with a warning.
- Exact cherry-pick squash strategy — `git merge --squash` vs `git rebase -i --autosquash` vs manual `git diff | git apply`; settle in implementation.
- **G11**: canonical name of the OpenAI-wrapping skill we expect users to install (does it exist in the ecosystem already? if not, ship a reference one in a separate sister-skill or document the contract so users can write their own).
- **G11**: should `pipeline.models.<alias>.via: cli:<cmd>` accept arbitrary shell or only a whitelist of known providers — security trade-off vs flexibility.
- **G11**: per-phase `model:` precedence vs `roles.<role>.model` (from S4 cost-multi-model) — confirm phase-level wins (current spec assumption).
