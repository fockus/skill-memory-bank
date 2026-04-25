---
description: Execute stages from a plan with auto-selected role-agents and a per-stage implement → review → fix → verify loop with severity gates and budget/protected-path hard stops.
allowed-tools: [Bash, Read, Task]
---

# /mb work [target] [--range A-B] [--auto] [--dry-run] [--budget TOK] [--max-cycles N] [--allow-protected]

Run the executable engine over a plan. Per stage, the engine dispatches an **implement** step to the auto-selected role-agent, an **mb-reviewer** review step, looped fix steps when the reviewer requests changes (capped at `max_cycles`), and a **plan-verifier** verify step before marking the stage done. Severity gates, token budgets, protected-path checks, and the sprint context guard provide hard stops for `--auto` mode.

> **Scope.** Phase 3 Sprint 1 shipped `pipeline.yaml`. Sprint 2 shipped target resolution, range parsing, role-detection, plan emission, implement-step dispatch. **Sprint 3 (this command)** wires the review-loop, severity gates, fix-cycle, plan-verifier integration, `--auto` hard stops, `--budget` token tracking, and protected-path enforcement.
>
> **Phase 4 will add:** `--slim` / `--full` context strategy via `context-slim-pre-agent.sh` and `pre-agent-protected-paths.sh` runtime hooks; `superpowers:requesting-code-review` skill auto-detection in the installer.

## Why /mb work?

Plans declared with `/mb plan` carry stage markers, DoD, and TDD instructions. `/mb work` is the runtime that consumes them: pick a stage, route it to the right role-agent (mb-backend, mb-frontend, mb-ios, mb-android, mb-architect, mb-devops, mb-qa, mb-analyst, with mb-developer as fallback), let the agent implement against the DoD, then put the diff through a real review-loop instead of trusting the implementer's self-assessment.

## Target resolution (spec §8.2)

The first positional arg `<target>` resolves in this order:

1. **Existing path** — used as-is.
2. **Substring of plan basename** — searches `<bank>/plans/*.md` (excluding `done/`); single hit wins, multiple hits = ambiguity exit.
3. **Topic name** — checks `<bank>/specs/<topic>/tasks.md`.
4. **Freeform (≥3 words)** — exits 3 with a candidate list. Claude Code (the orchestrator) reads the candidates, asks the user to confirm a match, and re-invokes with the resolved target.
5. **Empty** — uses the first plan inside `<!-- mb-active-plans -->` of `roadmap.md`.

Underlying script: `bash scripts/mb-work-resolve.sh [target] [--mb path]`.

## Range parsing (spec §8.3)

`--range A-B` filters which work items run. The level auto-detects:

- **Plan target** → range is over `<!-- mb-stage:N -->` markers.
- **Phase target** (multiple sprint-plans, each with `sprint:` frontmatter) → range is over sprint numbers.

Forms: `N` (single), `A-B` (closed), `A-` (open-ended to max). Out-of-bounds → exit 1.

Underlying script: `bash scripts/mb-work-range.sh <plan> [--range expr]`.

## Per-stage workflow Claude Code follows

When the user types `/mb work [args...]`:

1. **Resolve + range + plan emission.** Run `bash scripts/mb-work-plan.sh [--target ...] [--range ...] --mb <bank>`. The script outputs JSON Lines, one object per stage:

   ```json
   {"plan": "...", "stage_no": 2, "heading": "...", "role": "backend", "agent": "mb-backend", "status": "pending", "dod_lines": 5}
   ```

   On `--dry-run`, prepend a `## Execution Plan` summary header and **stop**; do not dispatch.

2. **Initialise budget (if `--budget TOK` given).** Run `bash scripts/mb-work-budget.sh init <TOK> --mb <bank>`. Subsequent steps call `bash scripts/mb-work-budget.sh check --mb <bank>` after each Task dispatch; exit 1 = warn (log and continue), exit 2 = stop (halt the loop). Add tokens after each Task with `bash scripts/mb-work-budget.sh add <delta> --mb <bank>`.

3. **For each pending stage** (iterate over the JSON Lines output):

   ### 3a. Implement step

   Read the stage block (heading + body between `<!-- mb-stage:N -->` markers). Dispatch via `Task`:

   ```
   Task(
     description="mb-work stage <N>: <heading>",
     subagent_type="general-purpose",
     prompt="<contents of agents/<agent>.md>\n\nPlan: <plan path>\nStage: <heading>\n\n<full stage body>\n\nLinked context: <if any>"
   )
   ```

   ### 3b. Protected-path check

   After the implement Task returns, gather the list of files it touched. Run `bash scripts/mb-work-protected-check.sh <files...> --mb <bank>`:

   - Exit 0 → proceed.
   - Exit 1 → if `--allow-protected` was passed, log a warning and continue; otherwise **halt** the loop and report which file violated which glob.

   ### 3c. Review step

   Dispatch the reviewer through `Task` (subagent name from `pipeline.yaml:roles.reviewer.agent`, default `mb-reviewer`):

   ```
   Task(
     description="mb-work review stage <N>",
     subagent_type="general-purpose",
     prompt="<contents of agents/mb-reviewer.md>\n\nPlan: <plan path>\nStage: <heading>\n\nDiff:\n<git diff output>\n\nReview rubric:\n<pipeline.yaml review_rubric section>\n\n<previous issue list, on fix-cycle>"
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
   - If `on_max_cycles == "continue_with_warning"`: log the unresolved issues, mark the stage as `WARN`, proceed to 3f anyway.

   ### 3f. Verify step

   Dispatch the plan-verifier:

   ```
   Task(
     description="mb-work verify stage <N>",
     subagent_type="general-purpose",
     prompt="<contents of agents/plan-verifier.md>\n\nPlan file: <plan path>\nStage just completed: <N> — <heading>"
   )
   ```

   The verifier returns its 7-check structured report.

   - **Verdict PASS** → proceed to 3g.
   - **Verdict FAIL** → **halt** the loop. Surface the verifier's findings. The user decides whether to re-implement or abandon.

   ### 3g. Stage-done

   - Mark DoD items satisfied in the plan (or run `bash scripts/mb-plan-sync.sh` if the plan was edited by the implementer).
   - Without `--auto`: prompt the user to confirm before moving to the next stage.
   - With `--auto`: continue to the next stage unless one of the hard stops (below) fired.

4. **End-of-run summary.** When all requested stages are processed, summarise: stages attempted, stages PASS / WARN / FAIL, files touched, total budget spent. Run `bash scripts/mb-work-budget.sh clear --mb <bank>` to remove the budget state.

## Hard stops for `--auto`

The autopilot continues without per-stage prompts **except** when:

| Trigger | Surfaced via | Halt? |
|---------|--------------|-------|
| `max_cycles` reached without `APPROVED` | step 3e + `on_max_cycles=stop_for_human` | yes |
| `plan-verifier` returns FAIL | step 3f | yes |
| `Write` / `Edit` attempt at a `protected_paths` glob without `--allow-protected` | step 3b (`mb-work-protected-check.sh`) | yes |
| `--budget` exhausted | `mb-work-budget.sh check` exit 2 after Task | yes |
| `sprint_context_guard.hard_stop_tokens` reached (190k default) | manual observation; halt and ask user to compact | yes |

When any hard stop fires, the loop halts even under `--auto`. The orchestrator surfaces the trigger, the stage state, and the next reasonable action (rerun with adjusted flags, edit pipeline.yaml, compact, etc.).

## Arguments

| Flag | Meaning | Sprint |
|------|---------|--------|
| `<target>` | Plan / topic / freeform / empty | 2 |
| `--range A-B` | Range over stages (plan) or sprints (phase) | 2 |
| `--dry-run` | Print execution plan, don't dispatch | 2 |
| `--auto` | Skip per-stage confirmation prompts; obey hard stops | 3 |
| `--max-cycles N` | Override `pipeline.yaml` review `max_cycles` | 3 |
| `--budget TOK` | Initialise token budget; halt at `stop_at_percent` | 3 |
| `--allow-protected` | Permit Write/Edit on `protected_paths` globs | 3 |
| `--slim` / `--full` | Context strategy for sub-agents — exports `MB_WORK_MODE=slim` (or `full`) for the loop subshell so `hooks/mb-context-slim-pre-agent.sh` produces the trimmed prompt as `additionalContext`. `--full` is the default | Phase 4 (Sprint 2) |

## Examples

```bash
/mb work                                # active plan, all stages, interactive
/mb work --auto                         # active plan, autopilot
/mb work --dry-run                      # show what would run
/mb work auth-refactor --range 2-4      # plan "auth-refactor", stages 2..4
/mb work inventory --range 1            # specs/inventory/tasks.md, stage 1
/mb work --auto --budget 200000         # autopilot, halt at 200k tokens
/mb work --auto --max-cycles 5          # autopilot, allow up to 5 review cycles
```

## Underlying scripts

```bash
# Resolution + range + plan emission (Sprint 2)
bash scripts/mb-work-resolve.sh [target] [--mb <path>]
bash scripts/mb-work-range.sh <plan> [--range <expr>]
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
- `/mb config` — manage `pipeline.yaml` (roles → agent mapping, review_rubric, severity_gate, max_cycles, on_max_cycles, budget thresholds, protected_paths).
- `/mb verify` — explicit plan verification (also runs as the verify step inside the loop).
- `/mb done` — close the session after a successful `/mb work` run.
