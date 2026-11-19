# /mb work — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `work [target] [--range A-B] [--dry-run]` — Execute stages from a plan. Auto-selects role-agent per stage (mb-backend / mb-frontend / mb-ios / mb-android / mb-architect / mb-devops / mb-qa / mb-debugger / mb-analyst, fallback mb-developer). Sprint 2: implement-step dispatch + dry-run; Sprint 3 adds review-loop, severity gates, verifier integration.

### work [target] [--workflow NAME] [--pipeline NAME] [--review|--judge|--fix|--brainstorm|--sdd|--plan (+ --no-*)] [--loop N] [--stages CSV] [--range A-B] [--dry-run]

Execute a composable workflow. **Default mode is `execution`: implement (TDD) → verify → done — review is OFF by default.** Compose per run with launch flags (precedence: flags > `pipeline.yaml` > default): add `--review`/`--judge`/`--fix`/`--brainstorm`/`--sdd`/`--plan` (or remove with `--no-*`), pick a preset with `--workflow` (`full` = the whole `discuss → sdd → plan → implement → verify → review → judge → done` chain; `governed-execution`, `full-cycle`, `review-fix`, `review-only`, …), or set an exact list with `--stages a,b,c`. Persist toggles in `pipeline.yaml` (`<stage>.enabled: true`, `review.enabled: true`). `--judge` and `--fix` require review; invalid chains fail fast.

`--fix` adds the review→fix loop: after review (and judge, when composed), blocking findings go back to the implementer and the item re-enters `verify`. **`--loop N` is the alias of `--max-cycles N`** — the ceiling on those cycles. So `/mb work <target> --review --fix --loop 4` = implement → verify → review → fix, repeating up to 4 cycles until the severity gate (or judge) passes, then done.

**Alias** for `/work` — dispatch to `commands/work.md` for the canonical workflow.

**Behavior:**

1. **Resolve workflow** with `mb-workflow.sh` (`--workflow` wins; otherwise `workflow.default`).
2. **Planning steps** (`discuss`, `sdd`, `plan`) run only if the selected workflow includes them.
3. **Resolve target** for execution/review steps (5 forms — see spec §8.2): existing path → substring in `plans/` → topic name → freeform → empty active plan (skips paused/cancelled/done/blocked plans and open `depends_on`; the only eligible, else the only `in_progress`).
4. **Apply `--range`** over plan stages or spec tasks.
5. **Emit JSON Lines** with role/agent/model/thinking/status/DoD metadata.
6. **Dispatch / quality loop** according to selected workflow steps and `workflow.loop`.
7. **Stage close-out** only after all selected workflow gates pass.

**Underlying scripts:**

```bash
bash "$SKILL_DIR"/scripts/mb-workflow.sh [--mb <path>] [--workflow <name>] [--review|--no-review] [--judge|--no-judge] [--fix|--no-fix] [--brainstorm|--sdd|--plan] [--stages <csv>] [--json|--steps|--loop|--max-cycles]
bash "$SKILL_DIR"/scripts/mb-work-resolve.sh [target] [--mb <path>]
bash "$SKILL_DIR"/scripts/mb-work-range.sh <plan> [--range <expr>]
bash "$SKILL_DIR"/scripts/mb-work-plan.sh [--target <ref>] [--range <expr>] [--dry-run] [--mb <path>]
```

**Out of scope:** fully deterministic host-side orchestration for every client UI. The command contract defines the required loop; clients/orchestrators must follow it and use the helper scripts for target resolution, review parsing, severity gates, budget tracking, and protected-path checks.
