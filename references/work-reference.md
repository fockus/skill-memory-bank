# `/mb work` — reference material

Companion to `commands/work.md`, which owns the NORMATIVE per-item loop.
Split out so each file stays within the 400-line project limit (S2 review
[26]); nothing here changed in the move. Read this file when you need the
workflow-mode matrix, the JSON Lines schema, the worked examples, the underlying script inventory, or parallel-run
guidance.

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

## Sprint contracts, progress trend, strategic pivoting

See **`references/work-loop-v2.md`**.
