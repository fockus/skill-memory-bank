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
    full: full-cycle

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
| `execution` | `implement → verify → done` | Plan/spec already exists; this is the simple default `/mb work` path. |
| `governed-execution` | `implement → verify → review ensemble → judge → fix/backlog → done` | Project opts into stronger gates without endless review/fix loops. |
| `full-cycle` | `discuss → sdd → plan → implement → verify → done` | One interactive pass from fuzzy idea to verified work. |
| `requirements-plan` | `discuss → sdd → plan` | Requirements and plans only; stop before implementation. |
| `implement-only` | `implement → verify` | Implement and structurally verify; stop before reviewer. |
| `review-fix` | `verify → review ensemble → judge → fix/backlog → done` | Existing changes need governed review/fix. |
| `review-only` | `verify → review ensemble → judge` | Audit and judge only; no automatic fix dispatch. |

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

4. **Initialise budget (if `--budget TOK` given).** Run `bash scripts/mb-work-budget.sh init <TOK> --mb <bank>`. Subsequent steps call `bash scripts/mb-work-budget.sh check --mb <bank>` after each Task dispatch; exit 1 = warn (log and continue), exit 2 = stop (halt the loop). Add tokens after each Task with `bash scripts/mb-work-budget.sh add <delta> --mb <bank>`.

5. **For each pending item** (iterate over the JSON Lines output):

   The stage body is read from the markers in the source file. For `kind=task` items, read between `<!-- mb-task:N -->` markers. For `kind=stage` items, read between `<!-- mb-stage:N -->` markers.

   ### 5a. Implement step (only if workflow includes `implement`)

   Dispatch via `Task`. **Compose the prompt as engineering-core + tooling-core + role-delta:** inline
   `agents/mb-engineering-core.md` FIRST (shared discipline — TDD, evidence-before-claims, escalation,
   STATUS, anti-rationalization; its primacy / "stricter wins" must stay on top), then
   `agents/mb-tooling-core.md` (graph-first, fail-open code-understanding routing the agent uses to
   understand code before touching it), then the resolved role agent (its domain delta), then the item
   body. The role files reference both cores but do not embed them; this prepend is what makes the
   discipline reach the specialist (a role file dispatched alone would be discipline-thin).
   Pass the resolved `model` and `thinking` from the JSON Line to the Agent/Task call; do not rely on agent frontmatter defaults.

   ```
   Task(
     description="mb-work item <N>: <heading>",
     subagent_type="general-purpose",
      prompt="<contents of agents/mb-engineering-core.md>\n\n---\n\n<contents of agents/mb-tooling-core.md>\n\n---\n\n<contents of agents/<agent>.md>\n\nPlan: <plan path>\nStage: <heading>\n\n<full item body>\n\nLinked context: <if any>",
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

   ```
   Task(
     description="mb-work verify item <N>",
     subagent_type="general-purpose",
     model="<pipeline.yaml roles.verifier.model>",
     thinking="<pipeline.yaml roles.verifier.thinking>",
     prompt="<contents of agents/plan-verifier.md>\n\nSource file: <plan or spec path>\nItem just completed: <N> — <heading>\nDiff:\n<git diff output>"
   )
   ```

   - **Verdict PASS** → continue.
   - **Verdict FAIL** → **halt** the loop. Surface findings. Do not spend reviewer cycles on a verifier-failing item unless the selected workflow explicitly omits `verify`.

   ### 5d. Review step (only if workflow includes `review`)

   If the workflow has no `review_profile`, dispatch the legacy single `roles.reviewer` and parse it with `mb-work-review-parse.sh`.

   If `review_profile: ensemble`, dispatch 3-5 aspect reviewers from `review_ensemble.reviewers` in parallel with fresh scoped context only: plan/spec, verifier report, diff, previous lead report. Then dispatch `review_ensemble.lead_role` to synthesize one canonical report. The lead reviewer must verify previous-cycle issues first, deduplicate aspect findings, separate blocking issues from backlog candidates, and emit strict JSON.

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

   - Use `workflow.loop.max_cycles` (or CLI `--max-cycles N`).
   - Re-dispatch the implementer only with judge `blocking_issues`, not every reviewer/backlog finding.
   - Run protected-path check after the fix.
   - Return to `workflow.loop.returns_to` (normally `verify`), then review/judge again.
   - If max cycles are exhausted and `on_max_cycles=judge_decides`, run judge once more: `GO_WITH_BACKLOG` may close, `NO_GO` stops for human.
   - If max cycles are exhausted and `on_max_cycles=stop_for_human`, halt and ask the user.
   - If `on_max_cycles=continue_with_warning`, require explicit human confirmation before marking WARN; do not silently mark done.

   ### 5g. Item done

   Mark DoD items satisfied in the source file (plan or spec tasks.md) only after all steps in the selected workflow have passed. For governed workflows, `GO` or `GO_WITH_BACKLOG` from judge is required; backlog items must be registered before marking done.

   - Without `--auto`: prompt the user to confirm before moving to the next item.
   - With `--auto`: continue to the next item unless one of the hard stops (below) fired.

6. **End-of-run summary.** When all requested items are processed, summarise: workflow used, items attempted, items PASS / WARN / FAIL, files touched, total budget spent, verifier verdicts, review cycles used. Run `bash scripts/mb-work-budget.sh clear --mb <bank>` to remove the budget state.

## Hard stops for `--auto`

The autopilot continues without per-item prompts **except** when:

| Trigger | Surfaced via | Halt? |
|---------|--------------|-------|
| `max_cycles` reached without `APPROVED` | step 5e + `on_max_cycles=stop_for_human` | yes |
| `plan-verifier` returns FAIL | step 5c | yes |
| `Write` / `Edit` attempt at a `protected_paths` glob without `--allow-protected` | step 5b (`mb-work-protected-check.sh`) | yes |
| `--budget` exhausted | `mb-work-budget.sh check` exit 2 after Task | yes |
| `sprint_context_guard.hard_stop_tokens` reached (190k default) | manual observation; halt and ask user to compact | yes |

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
bash scripts/mb-work-resolve.sh [target] [--mb <path>]
bash scripts/mb-work-range.sh <plan-or-spec> [--range <expr>]
bash scripts/mb-workflow.sh [--mb <path>] [--workflow <name>] [--json|--steps|--loop|max-cycles]
bash scripts/mb-work-plan.sh [--target <ref>] [--range <expr>] [--dry-run] [--mb <path>]

# Review-loop helpers (Sprint 3)
bash scripts/mb-work-review-parse.sh [--lenient] < reviewer-stdout
bash scripts/mb-work-severity-gate.sh --counts <json> | --counts-stdin [--mb <path>] [--workflow <name>]
bash scripts/mb-work-budget.sh init <total> | add <delta> | status | check | clear [--mb <path>]
bash scripts/mb-work-protected-check.sh <files...> [--mb <path>]
```

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
