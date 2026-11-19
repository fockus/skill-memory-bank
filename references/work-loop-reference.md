# /mb work — loop reference

Reference material moved out of `commands/work.md` to keep that file under the 400-line zone limit (`references/work-reference.md` is full too). The normative per-item loop stays in `commands/work.md`; this file holds the lookup tables.

## Target resolution forms

The first positional arg `<target>` resolves in this order:

| Form | Input | Resolution |
|------|-------|------------|
| 1 | Existing path (plan `.md` or spec `tasks.md`) | Used as-is, no search performed |
| 2 | Substring of a plan basename | Searches `<bank>/plans/*.md` (excluding `done/`); single hit wins, multiple = ambiguity exit |
| 3 | Topic name | Checks `<bank>/specs/<topic>/tasks.md`; if present with `mb-task` markers, resolves to that file |
| 3b | OpenSpec change (`<id>` or path to `openspec/changes/<id>`) | Runs `mb-openspec.sh import` (new) or `sync <topic>` (already imported), then resolves to `specs/<topic>/tasks.md`. A conflict or error exits 1 before any work; resolve with `mb-openspec.sh sync <topic> --take openspec|bank`. An explicit OpenSpec target never falls to a native topic: a native or differently-linked topic of the same name, a symlink/archive/foreign path exits 1; a bare id that also matches a plan name exits 2 (use `openspec/changes/<id>` or the full plan file name) |
| 4 | Freeform (≥ 3 words) | Exits 3; the driver presents candidates from both `plans/` and `specs/` and asks the user to confirm |
| 5 | Empty target | A plan link inside the `<!-- mb-active-plans -->` block of `roadmap.md` (`scripts/mb_work_active.py`): skips `status: paused\|cancelled\|done\|blocked` and open `depends_on`; the only eligible link, else the only `in_progress` one, else exit 2 |

**Form 3** is the direct spec-task path: if you have `specs/inventory-sync/tasks.md` containing `<!-- mb-task:N -->` markers, `/mb work inventory-sync` will execute those tasks directly — no plan file required.

**Form 3b** end of run: print `mb-openspec.sh export <topic> --mb <bank>` (dry-run) and ask the user before the same command with `--write`; never write OpenSpec unasked.

**Form 4** candidates include both `plans/*.md` and `specs/*/tasks.md`, so the user can pick either artifact type when input is ambiguous.

## Worktree rule

**Worktree rule (inter-plan vs. intra-plan parallelism).** **Inter-plan parallel runs are supported ONLY from separate git worktrees — one worktree per plan.** A worktree gives each plan its own working tree, index, and `progress.md`/`checklist.md`, so two unrelated plans' file writes and `git add`/commit operations never contend for the same `.git/index` or core files. **Intra-plan parallel** (several stages of the *same* plan running concurrently, in one worktree) is supported directly: each concurrent stage must be independently-scoped work with **a single owner per shared file** — this plan's own dispatch discipline (see *Parallel runs* below) is what prevents two runs from writing the same file at once, not the worktree boundary.

## Hard-stop epilogue

When any hard stop fires, the loop halts even under `--auto`. The orchestrator surfaces the trigger, the item state, and the next reasonable action (rerun with adjusted flags, edit pipeline.yaml, compact, etc.).

## Durable vs. ephemeral progress

During a run, the **durable** record of what is actually done is the DoD checkboxes in the source file (flipped only via `mb-work-checkbox.sh`) plus each run's `.work-state` slot (`phase`, `item_no`, `steps[]`) — that is what a resumed session, or another concurrent run, must trust. `TaskUpdate` (or any other UI-facing status ping) is **ephemeral** — a live-progress signal for the human/orchestrator's benefit only, never the source of truth for whether an item completed, and never something another run or a resumed session should rely on.

## Arguments

| Flag | Meaning | Sprint |
|------|---------|--------|
| `<target>` | Plan / spec topic / freeform / empty | 2 |
| `--workflow NAME` / `--tier T` | Select a named workflow from `pipeline.yaml:workflows`, or the one `effort_tiers.T` maps to | 4 |
| `--verify stage\|plan\|run\|off` / `--cost premium\|optimal\|economy` / `--host H` / `--qa` | Verifier cadence; cost tier (models per role class); host override; QA on for this run (5c2) | presets |
| `--range A-B` | Range over stages (plan) or tasks (spec) or sprints (phase) | 2 |
| `--dry-run` | Print selected workflow + execution plan, don't dispatch | 2 |
| `--auto` | Continue the authorized scope without per-item prompts; obey hard stops | 3 |
| `--review` / `--judge` / `--fix` (+ `--no-*`) | Compose stages for this run; `--fix` adds the review→fix loop (requires `--review`) | 4 |
| `--max-cycles N` / `--loop N` | Override `pipeline.yaml` review `max_cycles` — the fix-cycle ceiling | 3 |
| `--budget TOK` | Initialise token budget; halt at `stop_at_percent` | 3 |
| `--no-adapt` | No ADaPT fork (5c1): an escalation or failed verify halts the item as before | adapt-lite |
| `--allow-protected` | Permit Write/Edit on `protected_paths` globs | 3 |
| `--slim` / `--full` | Context strategy for sub-agents — exports `MB_WORK_MODE=slim` (or `full`) for the loop subshell | Phase 4 (Sprint 2) |
| `--contract` | Opt in to the sprint-contract phase for this run only (persist per-project via `pipeline.yaml:review.require_contract: true`) | work-loop-v2 (Phase 2) |

## Related commands

- `/mb plan <type> <topic>` — produces the plan file `/mb work` consumes.
- `/mb sdd <topic>` — creates `specs/<topic>/{requirements,design,tasks}.md`; `tasks.md` is directly executable by `/mb work`.
- `/mb config` — manage `pipeline.yaml` (roles → agent mapping, review_rubric, severity_gate, max_cycles, on_max_cycles, budget thresholds, protected_paths).
- `/mb verify` — explicit plan/spec verification (also runs as the verify step inside the loop).
- `/mb done` — close the session after a successful `/mb work` run.
