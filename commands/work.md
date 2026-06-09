---
description: Execute stages or spec tasks from a plan/spec with auto-selected role-agents and a per-item implement → review → fix → verify loop with severity gates and budget/protected-path hard stops.
allowed-tools: [Bash, Read, Task]
---

# /mb work [target] [--range A-B] [--auto] [--dry-run] [--budget TOK] [--max-cycles N] [--allow-protected]

Run the executable engine over a plan or spec. Per work item, the engine dispatches an **implement** step to the auto-selected role-agent, an **mb-reviewer** review step, looped fix steps when the reviewer requests changes (capped at `max_cycles`), and a **plan-verifier** verify step before marking the item done. Severity gates, token budgets, protected-path checks, and the sprint context guard provide hard stops for `--auto` mode.

> **Scope.** Phase 3 Sprint 1 shipped `pipeline.yaml`. Sprint 2 shipped target resolution, range parsing, role-detection, plan emission, implement-step dispatch — and extended execution to spec tasks (`specs/<topic>/tasks.md`) as a first-class source alongside plan stages. **Sprint 3 (this command)** wires the review-loop, severity gates, fix-cycle, plan-verifier integration, `--auto` hard stops, `--budget` token tracking, and protected-path enforcement.
>
> **Phase 4 will add:** `--slim` / `--full` context strategy via `context-slim-pre-agent.sh` and `pre-agent-protected-paths.sh` runtime hooks; `superpowers:requesting-code-review` skill auto-detection in the installer.

## Why /mb work?

Plans declared with `/mb plan` carry stage markers, DoD, and TDD instructions. Specs created with `/mb sdd` carry `<!-- mb-task:N -->` markers in `specs/<topic>/tasks.md`, each linked to REQ-IDs. `/mb work` is the runtime that consumes both: pick a work item (stage or task), route it to the right role-agent (mb-backend, mb-frontend, mb-ios, mb-android, mb-architect, mb-devops, mb-qa, mb-analyst, with mb-developer as fallback), let the agent implement against the DoD, then put the diff through a real review-loop instead of trusting the implementer's self-assessment.

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
| `status` | string | `pending`, `in-progress`, or `done` |
| `dod_lines` | int | Number of DoD checkbox lines in the item body |
| `source` | string | `plan` for `<!-- mb-stage:N -->` items; `spec` for `<!-- mb-task:N -->` items |
| `kind` | string | `stage` (plan item) or `task` (spec item) |
| `covers` | array | REQ-IDs this task covers (empty list `[]` for stages without Covers) |

Existing consumers that read `stage_no` continue to work — `item_no` is an alias with the same value.

## Per-stage workflow Claude Code follows

When the user types `/mb work [args...]`:

1. **Resolve + range + plan emission.** Run `bash scripts/mb-work-plan.sh [--target ...] [--range ...] --mb <bank>`. The script outputs JSON Lines as described above.

   On `--dry-run`, prepend a `## Execution Plan` summary header and **stop**; do not dispatch.

2. **Initialise budget (if `--budget TOK` given).** Run `bash scripts/mb-work-budget.sh init <TOK> --mb <bank>`. Subsequent steps call `bash scripts/mb-work-budget.sh check --mb <bank>` after each Task dispatch; exit 1 = warn (log and continue), exit 2 = stop (halt the loop). Add tokens after each Task with `bash scripts/mb-work-budget.sh add <delta> --mb <bank>`.

3. **For each pending item** (iterate over the JSON Lines output):

   The stage body is read from the markers in the source file. For `kind=task` items, read between `<!-- mb-task:N -->` markers. For `kind=stage` items, read between `<!-- mb-stage:N -->` markers.

   ### 3a. Implement step

   Dispatch via `Task`. **Compose the prompt as engineering-core + tooling-core + role-delta:** inline
   `agents/mb-engineering-core.md` FIRST (shared discipline — TDD, evidence-before-claims, escalation,
   STATUS, anti-rationalization; its primacy / "stricter wins" must stay on top), then
   `agents/mb-tooling-core.md` (graph-first, fail-open code-understanding routing the agent uses to
   understand code before touching it), then the resolved role agent (its domain delta), then the item
   body. The role files reference both cores but do not embed them; this prepend is what makes the
   discipline reach the specialist (a role file dispatched alone would be discipline-thin).

   ```
   Task(
     description="mb-work item <N>: <heading>",
     subagent_type="general-purpose",
     prompt="<contents of agents/mb-engineering-core.md>\n\n---\n\n<contents of agents/mb-tooling-core.md>\n\n---\n\n<contents of agents/<agent>.md>\n\nPlan: <plan path>\nStage: <heading>\n\n<full item body>\n\nLinked context: <if any>"
   )
   ```

   ### 3b. Protected-path check

   After the implement Task returns, gather the list of files it touched. Run `bash scripts/mb-work-protected-check.sh <files...> --mb <bank>`:

   - Exit 0 → proceed.
   - Exit 1 → if `--allow-protected` was passed, log a warning and continue; otherwise **halt** the loop and report which file violated which glob.

   ### 3c. Review step

   Resolve the reviewer agent name first:

   ```bash
   REVIEWER=$(bash scripts/mb-reviewer-resolve.sh --mb <bank>)
   ```

   The resolver reads `pipeline.yaml:roles.reviewer.agent` (default `mb-reviewer`) and honours `roles.reviewer.override_if_skill_present` when the named skill directory exists in `MB_SKILLS_ROOT` (default `~/.claude/skills`). With the `superpowers` skill installed it returns `superpowers:requesting-code-review`; otherwise it returns `mb-reviewer`.

   Dispatch the reviewer through `Task` with `$REVIEWER` as `subagent_type` (or as the agent prompt path when the resolver returns an `mb-`-prefixed local agent). Inline `agents/mb-tooling-core.md` ahead of the reviewer prompt so the reviewer can use the graph tools (`graph_impact` for blast-radius, `graph_tests` for coverage) when scoring the diff:

   ```
   Task(
     description="mb-work review item <N>",
     subagent_type="general-purpose",
     prompt="<contents of agents/mb-tooling-core.md>\n\n---\n\n<contents of agents/mb-reviewer.md>\n\nPlan: <plan path>\nItem: <heading>\n\nDiff:\n<git diff output>\n\nReview rubric:\n<pipeline.yaml review_rubric section>\n\n<previous issue list, on fix-cycle>"
   )
   ```

   The reviewer returns strict JSON.

   ### 3d. Parse & gate

   Parse the reviewer's stdout:

   ```bash
   bash scripts/mb-work-review-parse.sh < reviewer-stdout
   ```

   Then apply the severity gate:

   ```bash
   bash scripts/mb-work-severity-gate.sh --counts-stdin --mb <bank>
   ```

   - **Exit 0 (PASS)** → go to 3f (verify step).
   - **Exit 1 (FAIL)** → fix-cycle (3e).

   ### 3e. Fix-cycle

   - If `cycle < max_cycles` (from `pipeline.yaml:stage_pipeline[step=review].max_cycles`, override with `--max-cycles N`): re-dispatch the implementer Task with the issue list appended to the prompt. Increment `cycle`. Return to 3c.
   - If `cycle == max_cycles` and `pipeline.yaml:stage_pipeline[step=review].on_max_cycles == "stop_for_human"`: **halt** the loop, surface the open issues, ask the user how to proceed.
   - If `on_max_cycles == "continue_with_warning"`: log the unresolved issues, mark the item as `WARN`, proceed to 3f anyway.

   ### 3f. Verify step

   Dispatch the plan-verifier:

   ```
   Task(
     description="mb-work verify item <N>",
     subagent_type="general-purpose",
     prompt="<contents of agents/plan-verifier.md>\n\nSource file: <plan or spec path>\nItem just completed: <N> — <heading>"
   )
   ```

   The verifier returns its 7-check structured report.

   - **Verdict PASS** → proceed to 3g.
   - **Verdict FAIL** → **halt** the loop. Surface the verifier's findings. The user decides whether to re-implement or abandon.

   ### 3g. Item done

   - Mark DoD items satisfied in the source file (plan or spec tasks.md).
   - Without `--auto`: prompt the user to confirm before moving to the next item.
   - With `--auto`: continue to the next item unless one of the hard stops (below) fired.

4. **End-of-run summary.** When all requested items are processed, summarise: items attempted, items PASS / WARN / FAIL, files touched, total budget spent. Run `bash scripts/mb-work-budget.sh clear --mb <bank>` to remove the budget state.

## Hard stops for `--auto`

The autopilot continues without per-item prompts **except** when:

| Trigger | Surfaced via | Halt? |
|---------|--------------|-------|
| `max_cycles` reached without `APPROVED` | step 3e + `on_max_cycles=stop_for_human` | yes |
| `plan-verifier` returns FAIL | step 3f | yes |
| `Write` / `Edit` attempt at a `protected_paths` glob without `--allow-protected` | step 3b (`mb-work-protected-check.sh`) | yes |
| `--budget` exhausted | `mb-work-budget.sh check` exit 2 after Task | yes |
| `sprint_context_guard.hard_stop_tokens` reached (190k default) | manual observation; halt and ask user to compact | yes |

When any hard stop fires, the loop halts even under `--auto`. The orchestrator surfaces the trigger, the item state, and the next reasonable action (rerun with adjusted flags, edit pipeline.yaml, compact, etc.).

## Arguments

| Flag | Meaning | Sprint |
|------|---------|--------|
| `<target>` | Plan / spec topic / freeform / empty | 2 |
| `--range A-B` | Range over stages (plan) or tasks (spec) or sprints (phase) | 2 |
| `--dry-run` | Print execution plan, don't dispatch | 2 |
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

# Autopilot with budget cap
/mb work --auto --budget 200000

# Allow up to 5 review cycles per item
/mb work --auto --max-cycles 5
```

## Underlying scripts

```bash
# Resolution + range + plan emission (Sprint 2)
bash scripts/mb-work-resolve.sh [target] [--mb <path>]
bash scripts/mb-work-range.sh <plan-or-spec> [--range <expr>]
bash scripts/mb-work-plan.sh [--target <ref>] [--range <expr>] [--dry-run] [--mb <path>]

# Review-loop helpers (Sprint 3)
bash scripts/mb-work-review-parse.sh [--lenient] < reviewer-stdout
bash scripts/mb-work-severity-gate.sh --counts <json> | --counts-stdin [--mb <path>]
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
