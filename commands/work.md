---
description: Execute Memory Bank workflow modes from pipeline.yaml — existing plan/spec execution by default, optional full-cycle requirements→plan→implementation→review flows.
allowed-tools: [Bash, Read, Task]
---

# /mb work [target] [--workflow NAME] [--range A-B] [--auto] [--dry-run] [--budget TOK] [--max-cycles N] [--allow-protected]

Run the executable engine using a workflow mode resolved from `pipeline.yaml`. By default, `/mb work` is intentionally simple: **implement → verify → done** from an already-created plan/spec. Projects can opt into stricter local modes such as **governed-execution** (`implement → verify → review ensemble → judge → fix/backlog → done`), **full-cycle** (`discuss → sdd → plan → implement → verify → done`), **requirements-plan**, **implement-only**, **review-fix**, or **review-only**. Severity gates, judge gates, token budgets, protected-path checks, and the sprint context guard provide hard stops for `--auto` mode.

> **Scope.** Phase 3 Sprint 1 shipped `pipeline.yaml`. Sprint 2 shipped target resolution, range parsing, role-detection, plan emission, implement-step dispatch — and extended execution to spec tasks (`specs/<topic>/tasks.md`) as a first-class source alongside plan stages. **Sprint 3 (this command)** wires the review-loop, severity gates, fix-cycle, plan-verifier integration, `--auto` hard stops, `--budget` token tracking, and protected-path enforcement.
>
> **Phase 4 will add:** `--slim` / `--full` context strategy via `context-slim-pre-agent.sh` and `pre-agent-protected-paths.sh` runtime hooks; `superpowers:requesting-code-review` skill auto-detection in the installer.

## Why /mb work?

Plans declared with `/mb plan` carry stage markers, DoD, and TDD instructions. Specs created with `/mb sdd` carry `<!-- mb-task:N -->` markers in `specs/<topic>/tasks.md`, each linked to REQ-IDs. `/mb work` consumes both for execution modes: pick a work item (stage or task), route it to the right role-agent (mb-backend, mb-frontend, mb-ios, mb-android, mb-architect, mb-devops, mb-qa, mb-analyst, with mb-developer as fallback), let the agent implement against the DoD, verify the result, then put the verified diff through a real reviewer-approval loop instead of trusting the implementer's self-assessment. For full-cycle modes, `/mb work` first delegates to the same contracts as `/mb discuss`, `/mb sdd`, and `/mb plan` before executing work items.

## Workflow modes from pipeline.yaml

`/mb work` is locally configurable through the effective `pipeline.yaml`:

```yaml
workflow:
  default: execution
  aliases:
    everything: full

workflows:
  execution:
    steps: [implement, verify, done]

governed-execution:
  steps: [implement, verify, review, judge, fix, done]
  review_profile: ensemble
  judge_profile: independent
  loop:
    after: judge
    until: judge_go
    returns_to: verify
    max_cycles: 2
    on_max_cycles: judge_decides
```

Resolution rules:

1. `--workflow NAME` wins.
2. If omitted, use `workflow.default`; if absent, use `execution`.
3. Apply `workflow.aliases.NAME` when present.
4. Resolve `workflows.<name>`.
5. If no `workflows` block exists, fall back to legacy `stage_pipeline`.

Use the helper instead of hand-parsing YAML:

```bash
bash scripts/mb-workflow.sh --mb <bank> --workflow execution --json
bash scripts/mb-workflow.sh --mb <bank> --workflow full --steps
bash scripts/mb-workflow.sh --mb <bank> --workflow review --max-cycles
```

Built-in default modes:

| Workflow | Steps | Use when |
|---|---|---|
| `execution` | `implement → verify → done` | Plan/spec already exists; this is the simple default `/mb work` path. **Review is OFF by default.** |
| `full` | `discuss → sdd → plan → implement → verify → review → judge → done` | The complete composable chain — brainstorm to verified, reviewed, judged work. Alias: `everything`. |
| `governed-execution` | `implement → verify → review ensemble → judge → fix/backlog → done` | Project opts into stronger gates without endless review/fix loops. |
| `full-cycle` | `discuss → sdd → plan → implement → verify → done` | One interactive pass from fuzzy idea to verified work. |
| `requirements-plan` | `discuss → sdd → plan` | Requirements and plans only; stop before implementation. |
| `implement-only` | `implement → verify` | Implement and structurally verify; stop before reviewer. |
| `review-fix` | `verify → review ensemble → judge → fix/backlog → done` | Existing changes need governed review/fix. |
| `review-only` | `verify → review ensemble → judge` | Audit and judge only; no automatic fix dispatch. |

### Composing the pipeline (per-stage flags + precedence)

The stage list is composed from **three layers**, in increasing precedence:

1. **Built-in default** — the `execution` preset (`implement → verify → done`). **Review and judge are OFF by default.**
2. **`pipeline.yaml`** (project-persistent) — `workflow.default: <preset>` selects a preset; per-stage `<stage>.enabled: true` adds a composable stage on top of it.
3. **Launch flags** (per-run, highest) — these win over `pipeline.yaml`.

| Flag | Effect |
|---|---|
| `--workflow <preset>` | Select a preset (e.g. `full`, `governed-execution`). |
| `--review` / `--no-review` | Add / remove the single-reviewer stage. |
| `--judge` / `--no-judge` | Add / remove the independent judge (requires review). |
| `--brainstorm` / `--no-brainstorm` | Add / remove the `discuss` stage (brainstorm is an alias of discuss). |
| `--sdd` / `--no-sdd` | Add / remove the `sdd` stage. |
| `--plan` / `--no-plan` | Add / remove the `plan` stage. |
| `--stages a,b,c` | **Escape hatch** — use exactly this ordered list, overriding the preset and every flag. |
| `--pipeline <name>` | Run a **named pipeline** (`<bank>/pipelines/<name>.yaml`) with its own model routing + workflow. Overrides host auto-binding. See *Selecting a named pipeline* below. |

Rules:

- **Canonical order** is fixed: `discuss → sdd → plan → implement → verify → review → judge → done`. Composition only adds/removes stages; it never reorders them (except `--stages`, which sets an explicit order).
- **`pipeline.yaml` turns stages ON** (`<stage>.enabled: true`); **launch flags turn them ON or OFF** and win over `pipeline.yaml`. The shipped `enabled: false` entries are the off-baseline.
- **`--review` is the single-reviewer path** (resolved via `mb-reviewer-resolve.sh`, gated by `mb-work-severity-gate.sh`). The heavyweight 5-reviewer ensemble stays behind `--workflow governed-execution`.
- **Fail-fast** — `--judge` without review, or `--stages` naming `sdd`/`plan` with no topic/spec input, aborts before execution with a message naming the missing prerequisite.

#### Selecting a named pipeline (multi-pipeline projects)

A project may keep several pipelines under `<bank>/pipelines/<name>.yaml`, each
with its own model routing and workflow, managed by `/mb pipeline` (`list` /
`new` / `use` / `show`). `/mb work` picks one through this ladder (first match wins):

1. `--pipeline <name>` (or the `$MB_PIPELINE` env var).
2. **Host binding** — the pipeline whose `agents:` list includes the current
   code-agent host (`claude-code` / `pi` / `opencode` / `codex` …), auto-detected.
   This is what lets one project run a different pipeline under Claude Code than
   under pi/opencode **without any flag**.
3. `<bank>/.mb-config` `pipeline=<name>` (set by `/mb pipeline use`).
4. the pipeline marked `default: true`.
5. legacy `<bank>/pipeline.yaml`, then the bundled `references/pipeline.default.yaml`.

**Threading.** Resolve the selection once, then prefix every `mb-work-*.sh` /
`mb-workflow.sh` / `mb-reviewer-resolve.sh` invocation with `MB_PIPELINE=<name>`
so all consumers read the same pipeline — they each resolve their config through
`mb-pipeline.sh path`, which honors `$MB_PIPELINE`. Host binding needs no env;
it is detected per call. Confirm the selection up front:

```bash
bash scripts/mb-pipeline.sh list                    # all pipelines; (*) marks the active one
bash scripts/mb-pipeline.sh path --pipeline <name>  # the exact file that will drive this run
```

```bash
# Default flow plus a review:
/mb work my-feature --review
# Full chain minus the sdd stage:
/mb work my-feature --workflow full --no-sdd
# Exactly implement + verify, ignoring the project's default preset:
/mb work my-feature --stages implement,verify
# Validate a composed stage list before running it:
bash scripts/mb-pipeline-validate.sh --stages implement,verify,review,judge,done
```

Existing standalone commands remain first-class:

- `/mb discuss <topic>` — interactive requirements session.
- `/mb sdd <topic>` — create/update spec triple.
- `/mb plan <type> <topic>` — create plan/wrapper.
- `/mb review` — full uncommitted-code review outside the `/mb work` loop.
- `/mb verify` — explicit verifier run outside the loop.

## How `/mb work` resolves your input

The first positional arg `<target>` resolves in this order:

| Form | Input | Resolution |
|------|-------|------------|
| 1 | Existing path (plan `.md` or spec `tasks.md`) | Used as-is, no search performed |
| 2 | Substring of a plan basename | Searches `<bank>/plans/*.md` (excluding `done/`); single hit wins, multiple = ambiguity exit |
| 3 | Topic name | Checks `<bank>/specs/<topic>/tasks.md`; if present with `mb-task` markers, resolves to that file |
| 4 | Freeform (≥ 3 words) | Exits 3; the driver presents candidates from both `plans/` and `specs/` and asks the user to confirm |
| 5 | Empty target | Uses the first plan link inside the `<!-- mb-active-plans -->` block of `roadmap.md` |

**Form 3** is the direct spec-task path: if you have `specs/inventory-sync/tasks.md` containing `<!-- mb-task:N -->` markers, `/mb work inventory-sync` will execute those tasks directly — no plan file required.

**Form 4** candidates include both `plans/*.md` and `specs/*/tasks.md`, so the user can pick either artifact type when input is ambiguous.

Underlying script: `bash scripts/mb-work-resolve.sh [target] [--mb path]`.

**Parallel resolve (opt-in, `MB_WORK_PARALLEL`).** For an **empty target** (Form 5) under `MB_WORK_PARALLEL=1`, pass `--skip-claimed` so a new run doesn't pick an active-plan link another live run already claimed:

```bash
bash scripts/mb-work-resolve.sh --skip-claimed --mb <bank>
```

This drops any active-plan link whose source is claimed by a live (`phase != done`) foreign run before picking one; if every active plan is claimed, it exits 1 (`all active plans claimed`). Without `--skip-claimed` (or with `MB_WORK_PARALLEL` unset), resolution stays byte-identical to the single-run default. Independently of `--skip-claimed`, any resolved path under `MB_WORK_PARALLEL=1` that is already claimed by a live foreign run gets an informational stderr claim-note (`claimed by run <id>; pass --takeover`) — the hard refusal is always `mb-work-state.sh init`'s exit 4 (step 4), never this script.

**Worktree rule (inter-plan vs. intra-plan parallelism).** **Inter-plan parallel runs are supported ONLY from separate git worktrees — one worktree per plan.** A worktree gives each plan its own working tree, index, and `progress.md`/`checklist.md`, so two unrelated plans' file writes and `git add`/commit operations never contend for the same `.git/index` or core files. **Intra-plan parallel** (several stages of the *same* plan running concurrently, in one worktree) is supported directly: each concurrent stage must be independently-scoped work with **a single owner per shared file** — this plan's own dispatch discipline (see *Parallel runs* below) is what prevents two runs from writing the same file at once, not the worktree boundary.

## Spec tasks as executable source (Sprint 2)

`specs/<topic>/tasks.md` is a first-class executable artifact, not a human-only scaffold. A tasks.md file is executable when it contains at least one `<!-- mb-task:N -->` marker.

Example tasks.md fragment:

```markdown
<!-- mb-task:1 -->
### Task 1: Implement repository interface

**Covers:** REQ-001, REQ-002

...DoD items...

<!-- mb-task:2 -->
### Task 2: Add persistence layer
...
```

When `mb-work-plan.sh` reads a spec tasks.md, it emits JSON Lines with `source=spec` and `kind=task`. The `covers` field lists the REQ-IDs the task satisfies.

## Plan-as-wrapper UX

A thin plan file can delegate execution to a spec by declaring `linked_spec` (and optionally `tasks`) in its YAML frontmatter:

```yaml
---
type: feature
topic: inventory-sync-sprint-1
linked_spec: specs/inventory-sync
tasks: 1-3
---
```

When `mb-work-plan.sh` encounters `linked_spec`, it:

1. Resolves `<bank>/specs/inventory-sync/tasks.md`.
2. Applies the `tasks: 1-3` range (overrides any `--range` flag).
3. Emits JSON Lines with `source=spec`, `kind=task`, and `covers` populated from the spec markers.
4. Sets `plan` to the basename of the wrapper plan (for traceability), not the spec.

If `linked_spec` is present but `tasks` is omitted, all tasks from the spec are included.

If `linked_spec` is absent, the plan is treated as a classic plan (`<!-- mb-stage:N -->` flow).

**When to use plan-as-wrapper vs direct spec execution:**

- Use `/mb work <topic>` directly when you want to run all pending tasks from a spec (simple case).
- Use a plan-as-wrapper when Sprint slicing is needed: you want a dated plan record for traceability but the actual work items live in the spec.

## Range parsing (spec §8.3)

`--range A-B` filters which work items run. The format auto-detects from the first marker in the target file:

- **`<!-- mb-stage:N -->`** markers → range is over plan stages.
- **`<!-- mb-task:N -->`** markers → range is over spec tasks.
- **Mixed markers in one file** → `mb-work-range.sh` exits 1 with an explicit error about mixed-format.

Forms: `N` (single), `A-B` (closed), `A-` (open-ended to max). Out-of-bounds → exit 1.

For plan-as-wrapper with `tasks: <range>` in frontmatter, the frontmatter range takes precedence over `--range`.

Underlying script: `bash scripts/mb-work-range.sh <plan-or-spec> [--range expr]`.

## JSON Lines schema

`mb-work-plan.sh` outputs one JSON object per work item:

```json
{
  "plan": "2026-05-21_feature_inventory-sync-sprint-1",
  "stage_no": 2,
  "item_no": 2,
  "heading": "Task 2: Add persistence layer",
  "role": "backend",
  "agent": "mb-backend",
  "model": "opencode-go/qwen3.7-max",
  "thinking": "high",
  "status": "pending",
  "dod_lines": 5,
  "source": "spec",
  "kind": "task",
  "covers": ["REQ-001", "REQ-003"]
}
```

Field reference:

| Field | Type | Description |
|-------|------|-------------|
| `plan` | string | Basename of the plan or wrapper plan file (for traceability) |
| `stage_no` | int | Sequential item number (backward-compat alias of `item_no`) |
| `item_no` | int | Sequential item number (same value as `stage_no`) |
| `heading` | string | Stage or task heading text |
| `role` | string | Detected role (backend, frontend, etc.) |
| `agent` | string | Resolved agent name (from `pipeline.yaml:roles.<role>.agent`) |
| `model` | string | Resolved model id (from `pipeline.yaml:roles.<role>.model`, if configured) |
| `thinking` | string | Resolved thinking level (from `pipeline.yaml:roles.<role>.thinking`, if configured) |
| `status` | string | `pending`, `in-progress`, or `done` |
| `dod_lines` | int | Number of DoD checkbox lines in the item body |
| `source` | string | `plan` for `<!-- mb-stage:N -->` items; `spec` for `<!-- mb-task:N -->` items |
| `kind` | string | `stage` (plan item) or `task` (spec item) |
| `covers` | array | REQ-IDs this task covers (empty list `[]` for stages without Covers) |

Existing consumers that read `stage_no` continue to work — `item_no` is an alias with the same value.

## Per-stage workflow Claude Code follows

When the user types `/mb work [args...]`:

1. **Resolve workflow mode.** Resolve the effective pipeline and selected workflow:

   ```bash
   bash scripts/mb-workflow.sh --mb <bank> --workflow <name-or-empty> --json
   ```

   The returned JSON contains `steps`, `entrypoint`, `interactive`, and `loop`. The orchestrator MUST follow this workflow instead of hard-coding one order. `--max-cycles N` overrides `workflow.loop.max_cycles` for this run only.

2. **Run planning steps only when selected.** If the selected workflow contains:

   - `discuss` — run the `/mb discuss <topic>` contract: one-question-at-a-time interview, write `context/<topic>.md`, EARS-validate it. This is interactive; do not pretend it happened without user answers.
   - `sdd` — run the `/mb sdd <topic>` contract: create/update `specs/<topic>/{requirements.md,design.md,tasks.md}` and validate with `mb-spec-validate.sh`.
   - `plan` — run the `/mb plan <type> <topic>` contract or create a plan-as-wrapper linked to the spec.

   If the selected workflow has only planning steps (for example `requirements-plan`), stop after these artifacts are created and summarize paths. Do not dispatch implementers.

3. **Resolve execution target when execution/review steps are present.** If the workflow contains any of `implement`, `verify`, `review`, `fix`, or `done`, resolve the target and range:

   ```bash
   bash scripts/mb-work-plan.sh [--target ...] [--range ...] --mb <bank>
   ```

   The script outputs JSON Lines as described above, including resolved `agent`, `model`, and `thinking` values from `pipeline.yaml`.

   On `--dry-run`, print the selected workflow + `## Execution Plan` summary and **stop**; do not dispatch.

4. **Establish durable run-state, then initialise budget (if `--budget TOK` given).** Mint the session's `run_id` once, using the first pending item's `source`/`item_no` from step 3's JSON Lines, and reuse it for every item and every budget call for the rest of this run (this is what survives a compaction/abort — see *Resume after interruption* below):

   ```bash
   RUN_ID=$(bash scripts/mb-work-state.sh init <source> <first_item_no> --mb <bank>)
   ```

   `mb-work-state.sh init` resolves `max_cycles` from `workflow.loop.max_cycles` (or CLI `--max-cycles N`) when neither is passed explicitly — pass `--max-cycles N` to `init` when the CLI flag was given. If `--budget TOK` was given, run `bash scripts/mb-work-budget.sh init <TOK> --run-id "$RUN_ID" --mb <bank>`. Subsequent steps call `bash scripts/mb-work-budget.sh check --run-id "$RUN_ID" --mb <bank>` after each Task dispatch; exit 1 = warn (log and continue), exit 2 = stop (halt the loop). Add tokens after each Task with `bash scripts/mb-work-budget.sh add <delta> --run-id "$RUN_ID" --mb <bank>`. Threading `--run-id` means an orphaned `.work-budget.json` left over from a different, aborted run is recognised as stale (warn, exit 1) instead of silently throttling this run.

   **Parallel opt-in (`MB_WORK_PARALLEL`, off by default).** Everything above is the single-run default — unchanged, byte-identical. Driving **several concurrent `/mb work` runs from one Claude Code session** (intra-plan waves, or one plan per git worktree — see *Parallel runs* below) requires exporting `MB_WORK_PARALLEL=1` first, which switches `mb-work-state.sh`/`mb-work-budget.sh` from the legacy singleton files (`.work-state.json` / `.work-budget.json`) to **per-run slots**: `<bank>/.work-state/<run_id>.json` and `<bank>/.work-budget/<run_id>.json`. With the env var set:

   ```bash
   export MB_WORK_PARALLEL=1
   RUN_ID=$(bash scripts/mb-work-state.sh new-run-id)
   bash scripts/mb-work-state.sh init <source> <first_item_no> --run-id "$RUN_ID" --mb <bank>
   ```

   `mb-work-state.sh new-run-id` mints a fresh run id up front (prints it, writes nothing) so it can be threaded into `init` from the start. `init` then claims `<source>` for `"$RUN_ID"` in a source→run index: if another **live** (`phase != done`) run already claims that same source, `init` refuses with **exit 4** (`source '<source>' already claimed by run <id>; pass --takeover to override`) — halt the loop for this run (pick a different pending item, or a different source) unless the orchestrator deliberately wants to steal a stale/abandoned claim, in which case pass `--takeover` to force the claim. Thread the same `--run-id "$RUN_ID"` to every subsequent `mb-work-state.sh`, `mb-work-budget.sh`, and `mb-work-checkbox.sh` call for this run — that is what keeps its state, budget, and checkbox-flip gate isolated from any other concurrently running run.

5. **For each pending item** (iterate over the JSON Lines output):

   The stage body is read from the markers in the source file. For `kind=task` items, read between `<!-- mb-task:N -->` markers. For `kind=stage` items, read between `<!-- mb-stage:N -->` markers.

   For every item after the first, re-arm the per-item loop-state (this resets the item's `cycle` counter and `phase` back to `in-progress` while keeping the same session `run_id`):

   ```bash
   bash scripts/mb-work-state.sh init <source> <item_no> --run-id "$RUN_ID" --mb <bank>
   ```

   ### 5a. Implement step (only if workflow includes `implement`)

   Dispatch via `Task`. **Compose the prompt as engineering-core + tooling-core + role-delta:** inline
   `agents/mb-engineering-core.md` FIRST (shared discipline — TDD, evidence-before-claims, escalation,
   STATUS, anti-rationalization; its primacy / "stricter wins" must stay on top), then
   `agents/mb-tooling-core.md` (graph-first, fail-open code-understanding routing the agent uses to
   understand code before touching it), then the resolved role agent (its domain delta), then the item
   body. The role files reference both cores but do not embed them; this prepend is what makes the
   discipline reach the specialist (a role file dispatched alone would be discipline-thin).
   Pass the resolved `model` and `thinking` from the JSON Line to the Agent/Task call; do not rely on agent frontmatter defaults.

   **Do NOT edit DoD checkboxes** (`⬜`/`[ ]` → `✅`/`[x]`); the loop flips them deterministically via `mb-work-checkbox.sh` only after judge-GO — append this line verbatim to the dispatched prompt so the implementer never self-marks DoD items done.

   ```
   Task(
     description="mb-work item <N>: <heading>",
     subagent_type="general-purpose",
      prompt="<contents of agents/mb-engineering-core.md>\n\n---\n\n<contents of agents/mb-tooling-core.md>\n\n---\n\n<contents of agents/<agent>.md>\n\nPlan: <plan path>\nStage: <heading>\n\n<full item body>\n\nDo NOT edit DoD checkboxes (⬜/[ ] → ✅/[x]); the loop flips them deterministically via mb-work-checkbox.sh only after judge-GO.\n\nLinked context: <if any>",
      model="<json.model>",
      thinking="<json.thinking>",
   )
   ```

   ### 5b. Protected-path check (after every implement/fix dispatch)

   After an implement/fix Task returns, gather the list of files it touched. Run `bash scripts/mb-work-protected-check.sh <files...> --mb <bank>`:

   - Exit 0 → proceed.
   - Exit 1 → if `--allow-protected` was passed, log a warning and continue; otherwise **halt** the loop and report which file violated which glob.

   ### 5c. Verify step (only if workflow includes `verify`)

   Dispatch the plan-verifier before code review when both are present. The verifier catches missing tests, incomplete DoD, broken traceability, and architecture drift before reviewer cycles are spent.

   **Build the diff first — not a bare `git diff`.** Scope it to this run's own baseline and the item's touched files with `mb-work-diff.sh --run-id … --files …`:

   ```bash
   bash scripts/mb-work-diff.sh --run-id "$RUN_ID" --files "<item's touched files>" --mb <bank>
   ```

   The file list is the item's `Files:` line from its body **intersected with** files actually changed since baseline (get the changed-file set with `bash scripts/mb-work-diff.sh --run-id "$RUN_ID" --name-only --mb <bank>`). If the item declares no `Files:` line, fall back to the full baseline diff across every path — omit `--files` entirely: `bash scripts/mb-work-diff.sh --run-id "$RUN_ID" --mb <bank>`, which runs the **single-arg** `git diff <baseline>` form (baseline commit vs. working tree — never `<baseline>..HEAD`), so it sees both any commits made since baseline **and** this item's still-uncommitted edits, since `/mb work` only commits at step 5g. Scoping to `--run-id`'s own `baseline_ref` and `--files` is what keeps a co-running parallel run's edits from leaking into this item's judged diff.

   ```
   Task(
     description="mb-work verify item <N>",
     subagent_type="general-purpose",
     model="<pipeline.yaml roles.verifier.model>",
     thinking="<pipeline.yaml roles.verifier.thinking>",
     prompt="<contents of agents/plan-verifier.md>\n\nSource file: <plan or spec path>\nItem just completed: <N> — <heading>\nDiff:\n<output of mb-work-diff.sh above>"
   )
   ```

   - **Verdict PASS** → continue.
   - **Verdict FAIL** → **halt** the loop. Surface findings. Do not spend reviewer cycles on a verifier-failing item unless the selected workflow explicitly omits `verify`.

   ### 5d. Review step (only if workflow includes `review`)

   **Assemble the payload deterministically first — never a hand-rolled prompt.** Before dispatching any reviewer, build the review payload with the reviewer-2.0 orchestrator, which owns diff discovery, calibration examples, and touched-file test-cache resolution so the reviewer only has to judge one pre-assembled document (REQ-100):

   ```bash
   bash scripts/mb-review.sh --emit-payload --plan <plan path> --item <N> --run-id "$RUN_ID" --mb <bank>
   ```

   **Detecting touched-file test status — a single, unambiguous check:** the assembled payload
   contains a `## Auto-generated findings (MUST INCLUDE)` heading **if and only if** this item's
   touched-file tests were failing (`mb-review.sh` only emits that heading when its resolved
   `tests_pass` is exactly `false` — verified: its `## Prior evidence` section then also prints the
   literal line `tests_pass: False`). Concretely: `grep -q '^## Auto-generated findings' <payload>`
   (or, equivalently, `grep -q 'tests_pass: False' <payload>`) — record the result (e.g.
   `TESTS_FAILING=1` on a match) for the parsing step below. Absence of the heading means tests were
   passing, or no cached evidence existed for this run; treat both the same (do not pass
   `--require-tests-blocker`).

   If the workflow has no `review_profile`, resolve the single reviewer agent with `mb-reviewer-resolve.sh` (it reads `roles.reviewer.agent` — e.g. this project's `codex-cli`, or the skill-default `mb-reviewer` fallback — and applies `override_if_skill_present`, e.g. routing to `superpowers:requesting-code-review` when that skill is installed). Dispatch **that resolved agent** with the assembled payload as its prompt — never a hard-coded `Task(mb-reviewer)` — and parse the verdict with `mb-work-review-parse.sh`.

   If `review_profile: ensemble`, dispatch 3-5 aspect reviewers from `review_ensemble.reviewers` in parallel with fresh scoped context only: plan/spec, verifier report, diff, previous lead report. Reuse the **exact same** `mb-work-diff.sh --run-id "$RUN_ID" --files …` output built for 5c for every aspect reviewer — one diff computation, shared across the ensemble, so every reviewer judges the identical scoped changeset (consistency). Then dispatch `review_ensemble.lead_role` to synthesize one canonical report. The lead reviewer must verify previous-cycle issues first, deduplicate aspect findings, separate blocking issues from backlog candidates, and emit strict JSON.

   **Pre-wave codex health-check (only when a reviewer is external/cross-model):** before dispatching an external review wave — an aspect reviewer or the whole review step routed through the `codex` CLI — run `bash scripts/mb-work-codex-preflight.sh --json --mb <bank>` first. In-model-only review (no external reviewer configured for this run) never runs the preflight at all — it is skipped entirely, so no false SKIPPED note is ever written. If the preflight reports `available:false`, **or** the reviewer's own output later parses (via `--external`, below) as `verdict:"SKIPPED"` (the `codex-reviewer` subagent tripped its own preflight and returned `{"status":"SKIPPED"}`), do not let the judge close a governed item alone silently: write `cross-model review SKIPPED (<reason>)` into this item's stage report **and** append a `NOTE` entry to `<bank>/progress.md` — loud, never silent. Treat the gate as **degraded**, not failed — the in-model reviewer/judge (if any) may still complete the item on the remaining evidence, but the cross-model coverage that would have caught a cross-model-only class of issue simply did not run this cycle.

   **Parsing mode — `--external` for cross-model reviewers:** when the resolved reviewer is external / cross-model (a reviewer dispatched through the `codex` CLI transport, e.g. the global `codex-reviewer` subagent), parse its output with `mb-work-review-parse.sh --external` instead of the strict default — it normalizes a real GPT reviewer's "APPROVED with issues" down to `CHANGES_REQUESTED` (recomputing counts from issues, never trusting self-reported ones), maps the codex-reviewer issue schema (`description`/`recommendation`/`info` severity/`line:null`), and passes a `{"status":"SKIPPED"}` payload straight through as `verdict:"SKIPPED"`. The in-model `mb-reviewer`, and the ensemble's `lead_role` (which always stays in-model even when its aspect reviewers are external), keep the strict parse — no `--external` there.

   **`--require-tests-blocker` — the REQ-103 "cannot drop" safety net, BEFORE the severity gate:** append this flag to the `mb-work-review-parse.sh` call above whenever this item's touched-file tests were failing (the `## Auto-generated findings` fact captured above). If the normalized output still lacks a `category:"tests"` / `severity:"blocker"` issue — the reviewer dropped or downgraded it, or the cross-model review itself parsed as `SKIPPED` — the parser prepends the missing finding, forces `verdict:"CHANGES_REQUESTED"`, and logs a warning; a red test can never silently pass the gate through an omitted, softened, or skipped review. Idempotent (a tests/blocker already present is left untouched, never duplicated) and opt-in: omit the flag when touched-file tests were passing, and parsing stays byte-identical to today (REQ-105). This does not weaken the preflight-based SKIPPED handling above — the pre-wave health-check still fires its own loud stage-report/`progress.md` note regardless of this flag; `--require-tests-blocker` only changes what the *parsed* verdict becomes once tests are known to be failing.

   If the parse exits non-zero (genuinely unparseable reviewer output, not a schema mismatch `--external` already tolerates), perform **exactly one** automatic retry before failing the step: re-dispatch the same reviewer once, appending the parser's stderr text to its prompt so the reviewer can self-correct its output, then re-parse. A second parse failure surfaces the raw reviewer output verbatim and halts the review step — never a second automatic retry.

   - Reviewers report findings; they do **not** decide final completion.
   - The lead report is input to the `judge` step.
   - A reviewer finding is not automatically a fix-loop trigger.

   ### 5e. Judge step (only if workflow includes `judge`)

   Dispatch `roles.judge` with a different model when the project config provides one. Give it: plan/spec/DoD, verifier report, lead-review report, previous judge decision, diff, and verification evidence.

   The judge returns strict JSON with `decision`:

   - `GO` — acceptance criteria met; proceed to done.
   - `GO_WITH_BACKLOG` — acceptance criteria met; register non-blocking `backlog_items` before done.
   - `NO_GO` — only `blocking_issues` return to implementation.

   This is the anti-infinite-loop gate: review can keep discovering improvements, but only judge-blocking issues trigger another fix cycle. Non-blocking findings become backlog.

   ### 5f. Fix-cycle (only if workflow includes `fix`)

   - Call `bash scripts/mb-work-state.sh cycle --mb <bank>` — this is the deterministic, crash-surviving cycle counter (it enforces `workflow.loop.max_cycles` / CLI `--max-cycles N`, resolved once at step 4, **not** the orchestrator's memory of how many fix-cycles have run):
     - **exit 0** — cycle is still within `max_cycles`; proceed with the fix.
     - **exit 3** — **cycle budget exhausted** ("cycle budget exhausted" on stderr). This is a hard stop **even under `--auto`**: do not silently re-dispatch another fix; fall through to the `on_max_cycles` handling below instead.
   - Re-dispatch the implementer only with judge `blocking_issues`, not every reviewer/backlog finding.
   - Run protected-path check after the fix.
   - Return to `workflow.loop.returns_to` (normally `verify`), then review/judge again.
   - If cycle-exhausted (exit 3) and `on_max_cycles=judge_decides`, run judge once more: `GO_WITH_BACKLOG` may close, `NO_GO` stops for human.
   - If cycle-exhausted (exit 3) and `on_max_cycles=stop_for_human`, halt and ask the user.
   - If `on_max_cycles=continue_with_warning`, require explicit human confirmation before marking WARN; do not silently mark done.

   ### 5g. Item done

   Only after all steps in the selected workflow have passed for this item — for governed workflows, `GO` or `GO_WITH_BACKLOG` from judge is required, and backlog items must be registered before marking done — run this deterministic sequence (never hand-edit the checkboxes yourself):

   ```bash
   bash scripts/mb-work-state.sh done --mb <bank>
   bash scripts/mb-work-checkbox.sh flip <source> <item_no> --mb <bank>
   ```

   `mb-work-state.sh done` sets `phase: "done"` for the current `item_no` — the completion gate `mb-work-checkbox.sh flip` requires before it will touch the source file's DoD bullets. `flip` then converts that item's `⬜`/`[ ]` DoD bullets to `✅`/`[x]`, scoped to its `<!-- mb-stage:N -->` / `<!-- mb-task:N -->` marker block only. **A refused flip (exit 1) means the gate did not truly pass** — treat it as a bug in the loop (state/item mismatch), not as something to work around by editing the file directly.

   Workflows without a `judge` step (e.g. `execution`) still route through this exact sequence: `mb-work-state.sh done` is called once `verify` reports PASS (there is no judge decision to wait for), so the flip stays fully deterministic even without a judge gate.

   **Graph refresh (background, fail-open).** Immediately after `flip`, refresh the code graph so it does not silently drift when the opt-in git hook (`hooks/git/post-commit-codegraph.sh`) is not installed. Because this lives right after `flip`, both governed workflows and `judge`-less workflows like `execution` reach it — every path that flips a checkbox also refreshes the graph. Four guards, mirroring the post-commit hook exactly:

   - **exists** — only refresh when `<bank>/codebase/graph.json` already exists. If the graph is absent, the refresh is **skipped as a no-op**; the first build stays manual (Stage 1 `/mb map` / Stage 6 `/mb graph --apply`), this step never creates it.
   - **lock** — acquire `<bank>/.index/.graph-rebuild.lock` via an atomic `mkdir`; if another refresh already holds the lock, skip (one winner, no pile-up).
   - **background** — run the rebuild in a backgrounded subshell (`( ... ) & `) so it never blocks the item loop; release the lock in a `trap ... EXIT` inside the subshell.
   - **fail-open** — the step always returns/exits 0 either way; a broken or slow graph refresh must never fail or stall `/mb work`.

   ```bash
   GRAPH="<bank>/codebase/graph.json"
   if [ -f "$GRAPH" ]; then
     LOCK="<bank>/.index/.graph-rebuild.lock"
     mkdir -p "<bank>/.index" 2>/dev/null || true
     if mkdir "$LOCK" 2>/dev/null; then
       ( trap 'rmdir "$LOCK" 2>/dev/null' EXIT
         python3 scripts/mb-codegraph.py --apply --docs <bank> <repo> >/dev/null 2>&1
       ) >/dev/null 2>&1 &
     fi
   fi
   # fail-open: never block or fail the item loop on graph refresh
   ```

   - Without `--auto`: prompt the user to confirm before moving to the next item.
   - With `--auto`: continue to the next item unless one of the hard stops (below) fired.

6. **End-of-run summary.** When all requested items are processed, summarise: workflow used, items attempted, items PASS / WARN / FAIL, files touched, total budget spent, verifier verdicts, review cycles used. Run `bash scripts/mb-work-budget.sh clear --mb <bank>` and `bash scripts/mb-work-state.sh clear --mb <bank>` to remove the budget and loop-state.

## Sprint contracts, progress trend, and strategic pivoting (work-loop-v2)

Three additive layers wrap the base implement → verify → review → judge → fix loop above (design.md §4/§5/§6,
REQ-110/111/112/113/114). None of them replace a numbered step — they plug into it at a named point.
The scripts below only compute decisions/strings; **dispatch stays the host agent's job** — same
agent-native contract as the rest of this command.

### Sprint contract phase (opt-in, runs before 5a)

- **Gate.** Run this phase for an item only when `--contract` was passed for this invocation, or the
  project's resolved `pipeline.yaml` sets `review.require_contract: true` (design.md §4 "When mandatory";
  default is OFF — there is no dedicated resolver script for this key yet, so read it the same way the
  loop already reads other ad hoc pipeline values, e.g. `sprint_context_guard.hard_stop_tokens`: inspect
  `bash scripts/mb-pipeline.sh show --mb <bank>`). A per-item `<!-- mb-stage:N skip-contract -->` marker
  skips the phase for that one item even when the project requires it.
- **Create/reuse the contract file** (idempotent — a second `create` call for the same plan/stage is a
  no-op that never clobbers a hand-edited draft; the path is always derived through this script, never
  recomputed inline):

  ```bash
  bash scripts/mb-work-contract.sh create --mb <bank> --plan <plan-or-spec path> --stage <N> \
    --role <resolved role> --title "<item heading>"
  ```

  This scaffolds `<bank>/contracts/<plan-topic>_stage-<N>.md` with empty `In scope` / `Plan of attack` /
  `Test plan` / `DoD checkpoints` / `Out of scope` / `Open risks` sections.
- **Dispatch the resolved role-agent** (same `Task`/model/thinking resolution as 5a) to WRITE the
  contract body — concrete in-scope bullets, an ordered plan of attack, a Testing-Trophy-shaped test plan
  with one entry per DoD checkpoint, an explicit (never silent) out-of-scope list, and open risks —
  before any implementation begins.
- **Validate, then review.** `bash scripts/mb-work-contract.sh validate <contract-file>` checks all 7
  frontmatter keys, the `# Contract: <title>` heading, and all 6 body sections are present, naming
  anything missing (never a stack trace). Then dispatch the pipeline-resolved reviewer (same resolution
  as 5d) with the contract content (`mb-work-contract.sh read`) as payload, preamble `review_mode:
  contract` — `agents/mb-reviewer.md` documents the 4-category rubric (`scope` / `dod` / `test_plan` /
  `out_of_scope`; a silent/empty out-of-scope section is a **blocker**). The auto-generated-findings
  pre-injection from 5d does NOT apply here — there are no tests yet.
  - `APPROVED` → contract `status: approved`; proceed to 5a with the approved contract as additional
    implement-step input.
  - `CHANGES_REQUESTED` → generator revises and re-submits for another contract-review cycle, capped at
    **3 contract cycles**; a 4th exhausted cycle is a hard stop for human (there is no code yet to fall
    back on, so this is unconditional — not gated by `on_max_cycles`).
- If implementation later diverges from an approved contract, the normal 5d review flags it as a
  `scope` finding — the contract phase itself never re-runs mid-implementation.

### Progress trend (computed every review cycle, inside 5d)

- Once `mb-work-review-parse.sh` (5d, with or without `--external`) has normalized the reviewer verdict
  into `{"verdict": ..., "counts": {"blocker": N, "major": N, "minor": N}}`, derive this item's stable
  key ONCE through the script's own subcommand — never recompute the hash inline:

  ```bash
  ITEM_KEY=$(bash scripts/mb-work-trend.sh key --plan <plan-or-spec path> --stage <N> --item <M>)
  ```

- Feed the normalized verdict to `compute` to get this cycle's `progress_trend` and refresh the cache for
  next cycle:

  ```bash
  bash scripts/mb-work-trend.sh compute --mb <bank> --item-key "$ITEM_KEY" --verdict-file <normalized-verdict.json>
  # prints exactly one of: improving | stagnant | regressing | null
  ```

  `improving`: this cycle's weighted score (`10*counts.blocker + 3*counts.major + 1*counts.minor`) is
  strictly lower than last cycle's. `stagnant`: within ±1 of last cycle's AND the current score is > 0.
  `regressing`: strictly higher. `null`: first cycle (no previous cache), or a 0/0 converged recheck
  (never counted as stagnant/improving). The cache lives at `<bank>/tmp/last-verdict-<item-key>.json`,
  overwritten every cycle unless `--no-store` is passed.
  - **Known gap (backlog I-099).** `scripts/mb-review.sh` also reserves a `last_verdict_cache_path()`
    helper for this same file, but it is currently inert (its output is discarded) and derives the key
    differently (`mb_sanitize_topic(item)` vs. this script's `sha256(plan+stage+item)`). Until the two
    are reconciled, always derive the key via `mb-work-trend.sh key` above — never mb-review.sh's
    helper — so the cache the loop reads from stays the single source of truth.
- The orchestrator (not any script) tracks `consecutive_stagnant` for this item across cycles: increment
  on `stagnant`, reset to 0 on `improving` / `regressing` / `null`. This tally feeds the pivot decision
  below.

### Strategic pivoting (on a CHANGES_REQUESTED verdict, before the re-dispatch in 5f)

- Ask whether to keep refining or force a fresh start, passing the tracked `consecutive_stagnant` and
  the current cycle number (from `mb-work-state.sh cycle`/`status`):

  ```bash
  bash scripts/mb-work-pivot.sh decide --mb <bank> --consecutive-stagnant <N> --cycle <C> \
    --item-id "$ITEM_KEY" --rationale "<one-line reason>"
  # prints exactly one of: refine | pivot_in_role | pivot_via_architect
  ```

  `refine` while `consecutive_stagnant < pivot_after_cycles` (default 2, resolved from
  `pipeline.yaml:review.pivot_after_cycles`, falling back to a flat top-level key, then the default) —
  this is the existing 5f behavior, unchanged. Once that threshold is reached, `pivot_in_role`; once the
  cycle count also reaches `pivot_escalate_to_architect_on` (default 4,
  `pipeline.yaml:review.pivot_escalate_to_architect_on`), `pivot_via_architect`. A pivot decision (mode
  != `refine`) with `--item-id` given also appends one JSONL line to `<bank>/tmp/pivot-log.jsonl`
  (`ts` / `item_id` / `cycle` / `mode` / `rationale_hash`) — analysis data, intentionally not git-tracked.
- **`pivot_in_role`** — re-dispatch the SAME role-agent (never a different one), replacing the normal
  "fix these issues" framing with the script's own discard-and-restart instruction:

  ```bash
  bash scripts/mb-work-pivot.sh prompt-prefix --mode pivot_in_role --stagnant <N>
  ```

  This tells the agent to discard the current approach rather than patch it, read the issue list as
  constraints on a fresh design (not a literal edit list), implement a different
  architecture/strategy/abstraction from scratch, and state a one-line "Pivot rationale: ..." at the top
  of its work.
- **`pivot_via_architect`** — heavier, two-step dispatch, reached only at cycle ≥
  `pivot_escalate_to_architect_on`: first dispatch `mb-architect` with the issue list and current code
  state to produce a redesign sketch at `.memory-bank/notes/<date>_pivot-<topic>.md`; then dispatch the
  role-agent with both the issue list and the architect's sketch, prefixed with
  `bash scripts/mb-work-pivot.sh prompt-prefix --mode pivot_via_architect --stagnant <N>` (its output
  appends the two-step escalation text to the same discard-and-restart instruction).
- Either pivot mode still runs through the SAME 5f mechanics afterward (protected-path check, return to
  `verify`, review/judge again) — pivoting changes what the agent is asked to do, not the loop's control
  flow, and does not reset or extend `max_cycles`.

### Max-cycle policy (already covered by 5f — restated for completeness)

`on_max_cycles: stop_for_human` is the shipped default in `references/pipeline.default.yaml` (previously
`continue_with_warning` — see the `[Unreleased]` CHANGELOG entry for the migration note and the 5f
cycle-exhausted handling above for the full behavior). This applies identically whether the exhausted
cycles were plain `refine` cycles or included one or more pivots.

## Concurrent core-file writes

Two core files are written during a run — under concurrent (parallel) runs each has exactly one writer discipline, never a free-form prose edit:

- **`progress.md` appends** go through the locked, atomic, append-only helper — **required** under `MB_WORK_PARALLEL` (recommended always, even single-run, since it is safe with no contention):

  ```bash
  bash scripts/mb-work-progress-append.sh --text "<entry>" --mb <bank>
  ```

  It serializes concurrent writers behind an owner-token lock, builds the new content in a temp file, and atomically `mv`s it over `progress.md` — no writer ever sees, or produces, a partial/interleaved file. Fail-safe: a lock it cannot acquire in time (or any write error) degrades to a stderr warning and exit 0 — it never wedges the loop, and it never rewrites or removes existing content (append-only).
- **`checklist.md` / DoD bullets** are flipped **only** by `mb-work-checkbox.sh flip` (reaffirming I-093) — never a hand-edit, and never any other script. This is what keeps two concurrent runs from racing on the same checkbox: `flip` is gated on the run's own `.work-state` slot reporting `phase == "done"` for that exact item before it touches a byte of the source file.

**Durable vs. ephemeral progress signal.** During a run, the **durable** record of what is actually done is the DoD checkboxes in the source file (flipped only via `mb-work-checkbox.sh`) plus each run's `.work-state` slot (`phase`, `item_no`, `steps[]`) — that is what a resumed session, or another concurrent run, must trust. `TaskUpdate` (or any other UI-facing status ping) is **ephemeral** — a live-progress signal for the human/orchestrator's benefit only, never the source of truth for whether an item completed, and never something another run or a resumed session should rely on.

**Worktree mode note.** Under the inter-plan-worktree pattern (see the worktree rule above and *Parallel runs* below), `progress.md`/`checklist.md` are per-worktree files — cross-plan appends physically cannot contend, so the append helper's serialization only matters for **intra-plan** concurrent stages sharing one worktree.

## Resume after interruption

`.work-state.json` is the durable source of truth for "is this item actually done", surviving compaction and abort — checkbox appearance in the plan/spec is not. Before resolving items on a fresh invocation (a new session picking the same target back up):

```bash
bash scripts/mb-work-state.sh status --mb <bank>
```

- Empty `{}` (no state, or state cleared by a prior clean end-of-run) — start fresh from step 3.
- `phase: "in-progress"` for the item currently at `item_no` — this item is **mid-flight**: do **not** treat it as done even if its DoD checkboxes look flipped in the source file. The loop flips checkboxes deterministically only after judge-GO (`mb-work-state.sh done`, wired in a later stage) — `phase` in `.work-state.json`, not checkbox appearance, is the source of truth. Resume by re-entering the loop for that item at the next unresolved step (inspect `steps[]`), or, if in doubt, safely restart from `implement` for that item.
- `phase: "done"` — the item completed cleanly; proceed to the next pending item.

**Parallel runs.** Under `MB_WORK_PARALLEL=1`, `mb-work-state.sh status` (no `--run-id`) only ever sees the singleton path — to enumerate every **live parallel run** (each per-run slot under `<bank>/.work-state/*.json`, plus the singleton if present), use:

```bash
bash scripts/mb-work-state.sh status --all
# alias:
bash scripts/mb-work-state.sh list
```

This prints a JSON array of every run's state (run_id, source, item_no, phase, …), so a resuming session can tell which sources are still claimed by a live (`phase != done`) run before minting its own `run_id` and calling `init`.

## Hard stops for `--auto`

The autopilot continues without per-item prompts **except** when:

| Trigger | Surfaced via | Halt? |
|---------|--------------|-------|
| `max_cycles` reached (cycle-exhausted) | `mb-work-state.sh cycle` exit 3 at step 5f + `on_max_cycles` handling | yes |
| `plan-verifier` returns FAIL | step 5c | yes |
| `Write` / `Edit` attempt at a `protected_paths` glob without `--allow-protected` | step 5b (`mb-work-protected-check.sh`) | yes |
| `--budget` exhausted | `mb-work-budget.sh check` exit 2 after Task | yes |
| `sprint_context_guard.hard_stop_tokens` reached (190k default) | manual observation; halt and ask user to compact | yes |
| `cross-model review SKIPPED` under `--auto` (`mb-work-codex-preflight.sh` reports `available:false`, or the reviewer parses as `verdict:"SKIPPED"`) | step 5d preamble | yes — a skipped cross-model gate requires explicit user confirmation before the loop proceeds, even under `--auto` |
| Claim refused (exit 4) — `mb-work-state.sh init --run-id` under `MB_WORK_PARALLEL` finds `<source>` already claimed by another live run | step 4 (`mb-work-state.sh init`) | yes — stop this run and pick a different pending item/source, or pass `--takeover` to steal a stale/abandoned claim |
| Active FREEZE on the cross-session board (`.memory-bank/COORDINATION.md`) covers files of the current item, or an unACKed HANDOVER targets its scope | manual observation at item start (board checkpoint, `references/coordination.md`) | yes — wait for the lifting entry or escalate on the board |

When any hard stop fires, the loop halts even under `--auto`. The orchestrator surfaces the trigger, the item state, and the next reasonable action (rerun with adjusted flags, edit pipeline.yaml, compact, etc.).

## Arguments

| Flag | Meaning | Sprint |
|------|---------|--------|
| `<target>` | Plan / spec topic / freeform / empty | 2 |
| `--workflow NAME` | Select a named workflow from `pipeline.yaml:workflows` | 4 |
| `--range A-B` | Range over stages (plan) or tasks (spec) or sprints (phase) | 2 |
| `--dry-run` | Print selected workflow + execution plan, don't dispatch | 2 |
| `--auto` | Skip per-item confirmation prompts; obey hard stops | 3 |
| `--max-cycles N` | Override `pipeline.yaml` review `max_cycles` | 3 |
| `--budget TOK` | Initialise token budget; halt at `stop_at_percent` | 3 |
| `--allow-protected` | Permit Write/Edit on `protected_paths` globs | 3 |
| `--slim` / `--full` | Context strategy for sub-agents — exports `MB_WORK_MODE=slim` (or `full`) for the loop subshell | Phase 4 (Sprint 2) |
| `--contract` | Opt in to the sprint-contract phase for this run only (persist per-project via `pipeline.yaml:review.require_contract: true`) | work-loop-v2 (Phase 2) |

## Examples

```bash
# Empty target: pick first active plan from roadmap.md mb-active-plans block
/mb work
/mb work --auto

# Execute all tasks from specs/inventory-sync/tasks.md (topic = Form 3 resolution)
/mb work inventory-sync

# Narrow to spec tasks 1-2 using --range
/mb work inventory-sync --range 1-2

# Single spec task by number
/mb work inventory-sync --range 3

# Plan-as-wrapper: thin plan delegates execution to linked spec
# (plan frontmatter: linked_spec: specs/inventory-sync, tasks: 1-3)
/mb work plans/2026-05-21_feature_inventory-sync-sprint-1.md

# Dry-run: show execution plan for a spec without dispatching
/mb work inventory-sync --dry-run

# Backward compat: classic plan with mb-stage markers (no linked_spec)
/mb work plans/2026-05-21_refactor_auth-service.md

# Classic plan with stage range
/mb work auth-refactor --range 2-4

# Autopilot with budget cap using workflow.default (usually execution)
/mb work --auto --budget 200000

# Full interactive one-pass flow: discuss -> sdd -> plan -> implement -> verify -> review -> fix
/mb work "inventory sync" --workflow full-cycle

# Requirements/planning only, then stop
/mb work "inventory sync" --workflow requirements-plan

# Implement and verify only, no reviewer
/mb work inventory-sync --workflow implement-only --range 2

# Review existing changes and loop fixes until approval
/mb work inventory-sync --workflow review-fix

# Allow up to 5 review cycles per item (overrides workflow.loop.max_cycles)
/mb work --auto --max-cycles 5
```

## Underlying scripts

```bash
# Resolution + range + plan emission (Sprint 2)
bash scripts/mb-work-resolve.sh [target] [--skip-claimed] [--mb <path>]
bash scripts/mb-work-range.sh <plan-or-spec> [--range <expr>]
bash scripts/mb-workflow.sh [--mb <path>] [--workflow <name>] [--json|--steps|--loop|max-cycles]
bash scripts/mb-work-plan.sh [--target <ref>] [--range <expr>] [--dry-run] [--mb <path>]

# Review-loop helpers (Sprint 3)
bash scripts/mb-work-review-parse.sh [--lenient|--external] < reviewer-stdout
bash scripts/mb-work-severity-gate.sh --counts <json> | --counts-stdin [--mb <path>] [--workflow <name>]
bash scripts/mb-work-budget.sh init <total> [--run-id ID] | add <delta> [--run-id ID] | status [--run-id ID] | check [--run-id ID] | clear [--run-id ID] [--mb <path>]
bash scripts/mb-work-protected-check.sh <files...> [--mb <path>]

# Durable loop-state (I-093): max_cycles enforcement by exit code + resume across compaction/abort
bash scripts/mb-work-state.sh init <source> <item_no> [--run-id ID] [--max-cycles N] [--takeover] [--mb <path>]
bash scripts/mb-work-state.sh step <name> | cycle | status [--all] | list | done | clear [--run-id ID] [--mb <path>]

# Per-run state+budget slots (I-094, opt-in MB_WORK_PARALLEL=1): mints a fresh run id via
# new-run-id, then --run-id ID threads it through init/status/cycle/done/clear (state) and
# init/add/status/check/clear (budget) above — each resolves <bank>/.work-state/<run_id>.json
# and <bank>/.work-budget/<run_id>.json instead of the legacy singleton files. init on a
# source already claimed by another live run exits 4 (pass --takeover to override).
bash scripts/mb-work-state.sh new-run-id

# Deterministic DoD-checkbox flip (I-093): only fires once .work-state.json phase == done
bash scripts/mb-work-checkbox.sh flip <plan-or-spec> <item_no> [--run-id ID] [--mb <path>]

# Codex preflight (I-093): fail-safe availability/auth health-check run before an
# external/cross-model review wave (step 5d preamble). Always exits 0 (advisory only).
bash scripts/mb-work-codex-preflight.sh [--json] [--mb <path>]

# Baseline-scoped diff for verify/review (I-094): single-arg `git diff <baseline>` form
# (baseline commit vs. working tree — sees uncommitted stage work too, never <baseline>..HEAD).
bash scripts/mb-work-diff.sh --run-id ID [--files "p1 p2 ..."] [--baseline REF] [--name-only] [--mb <path>]

# Locked, atomic, append-only progress.md writer (I-094): required under MB_WORK_PARALLEL,
# recommended always. checklist.md/DoD bullets stay single-writer via mb-work-checkbox.sh only.
bash scripts/mb-work-progress-append.sh --text "<entry>" | --file <path> [--mb <path>]

# Sprint contract (work-loop-v2, REQ-110): opt-in scope-lock reviewed before implement.
# create is idempotent (never clobbers); path is the single source of truth for the file location.
bash scripts/mb-work-contract.sh create --mb <bank> --plan <path> --stage <N> [--role <role>] [--title <title>]
bash scripts/mb-work-contract.sh read   --mb <bank> --plan <path> --stage <N>
bash scripts/mb-work-contract.sh path   --mb <bank> --plan <path> --stage <N>
bash scripts/mb-work-contract.sh validate <contract-file>

# Progress trend (work-loop-v2, REQ-111/114): item key + trend computed from the normalized
# verdict on every review cycle; maintains <bank>/tmp/last-verdict-<item-key>.json.
bash scripts/mb-work-trend.sh key --plan <path> --stage <N> --item <M>
bash scripts/mb-work-trend.sh compute --mb <bank> --item-key <key> [--verdict-file <file>] [--no-store]

# Strategic pivot (work-loop-v2, REQ-112/114): refine|pivot_in_role|pivot_via_architect decision
# from consecutive-stagnant cycles vs pivot_after_cycles/pivot_escalate_to_architect_on; telemetry
# to <bank>/tmp/pivot-log.jsonl (never git-tracked). prompt-prefix emits the re-dispatch text.
bash scripts/mb-work-pivot.sh decide --mb <bank> --consecutive-stagnant <N> --cycle <C> [--item-id <id>] [--rationale <text>]
bash scripts/mb-work-pivot.sh prompt-prefix --mode pivot_in_role|pivot_via_architect --stagnant <N>
```

## Parallel runs

Two supported patterns for driving several `/mb work` runs concurrently from one Claude Code session — both opt in via `MB_WORK_PARALLEL=1` and everything documented above (per-run slots, `new-run-id`, claim exit-4, baseline-scoped diff, `--skip-claimed`, the append helper):

| Pattern | When to use | How |
|---|---|---|
| **Intra-plan waves** | Several **independent stages of the same plan** (a "wave" with no dependency between them) need to run at once, in one worktree. | Each stage's dispatch mints its own `run_id` via `mb-work-state.sh new-run-id`, threads `--run-id` through state/budget/checkbox, and claims its own `<source>` (the plan/spec + item) via `init`. **A single owner per shared file** — never let two concurrently-running stages write the same file. |
| **Inter-plan worktrees** | Two or more **unrelated plans** need to run at once. | One `git worktree` per plan (see the worktree rule above) — each gets its own working tree, index, `progress.md`, and `checklist.md`, so cross-plan writes never contend. Per-run state/budget slots still apply per worktree. |

**Sync vs. async spawn rule.** Dispatch **sync** (wait for the Task/agent to return before continuing) whenever the next step in *this* item's sequence depends on the result — e.g. verify waiting on implement, judge waiting on review. Dispatch **async** (background) **only** for truly independent waves — stages/items with no dependency on each other's output, typically distinct intra-plan-wave stages or separate inter-plan-worktree plans.

**Mandatory background report delivery.** An async/background agent's final turn text is **not** automatically delivered to the team lead / orchestrator — only an idle notification reaches it. Every background dispatch **MUST** deliver its complete final report via `SendMessage` to the dispatching session/agent before ending its turn; if `SendMessage` is unavailable at runtime, it must write the report to `<bank>/.reports/<name>-<item>.md` instead, so the orchestrator can pick it up from disk. Skipping this means the work happened but the result is silently lost to the lead.

**Optional self-claim pull mode.** Instead of the orchestrator assigning each item to a specific agent up front, it may **publish all pending items as tasks BEFORE spawning any agent**, then spawn a pool of agents that each **self-claim** a task by calling `mb-work-state.sh init <source> <item_no> --run-id "$RUN_ID"`: exit 0 means this agent now owns that item, **exit 4** means another agent already claimed it — the losing agent picks the next unclaimed pending item instead of double-working the same one. This mode still needs **a single writer per shared file**: if two self-claimed items touch the same file, that file's edits must be serialized (sequential dispatch, or one owning agent) regardless of how the items themselves were claimed.

## Out of scope (Phase 4)

- `--slim` / `--full` context strategy via `context-slim-pre-agent.sh` runtime hook.
- `--allow-protected` enforcement at Write/Edit hook level (deterministic check at step 3b stays in /mb work).
- `superpowers:requesting-code-review` skill detection wired by the installer based on `pipeline.yaml:roles.reviewer.override_if_skill_present`.

## Related

- `/mb plan <type> <topic>` — produces the plan file `/mb work` consumes.
- `/mb sdd <topic>` — creates `specs/<topic>/{requirements,design,tasks}.md`; `tasks.md` is directly executable by `/mb work`.
- `/mb config` — manage `pipeline.yaml` (roles → agent mapping, review_rubric, severity_gate, max_cycles, on_max_cycles, budget thresholds, protected_paths).
- `/mb verify` — explicit plan/spec verification (also runs as the verify step inside the loop).
- `/mb done` — close the session after a successful `/mb work` run.
