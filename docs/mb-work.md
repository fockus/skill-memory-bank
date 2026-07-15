# /mb work — the execution engine

`/mb work` is the command that actually drives implementation. Everything else in Memory Bank
(plans, specs, requirements) produces artifacts for a human or an agent to read; `/mb work` is
the one command that reads those artifacts back and dispatches real work against them, stage by
stage or task by task, with deterministic gates in between.

## Why it exists

Plans created with `/mb plan` carry `<!-- mb-stage:N -->` markers, a DoD, and TDD instructions.
Specs created with `/mb sdd` carry `<!-- mb-task:N -->` markers in `specs/<topic>/tasks.md`, each
one linked to REQ-IDs from `requirements.md`. `/mb work` consumes both as first-class executable
sources: it picks a work item, routes it to the right role-agent (`mb-backend`, `mb-frontend`,
`mb-ios`, `mb-android`, `mb-architect`, `mb-devops`, `mb-qa`, `mb-analyst`, with `mb-developer` as
the generic fallback), lets that agent implement against the item's DoD, verifies the result, and
— when the workflow calls for it — puts the diff through a real reviewer-approval loop instead of
trusting the implementer's own "looks done to me."

## The default loop: implement → verify → done

By design, `/mb work` is **simple by default**. The built-in `execution` workflow is:

```
implement → verify → done
```

Review is **OFF by default**. There is no reviewer dispatch, no judge, no fix-cycle unless you
explicitly ask for one. This matters because the composable pipeline described below layers
review/judge/discuss/sdd/plan stages on top of this baseline — the baseline itself stays cheap
and fast for the common case of "I already have a plan, just build it."

## Composable pipeline: opting into more

The full stage vocabulary, in canonical (fixed) order, is:

```
discuss → sdd → plan → implement → verify → review → judge → fix → done
```

`fix` is an internal loop mechanic (only reachable via the judge's `NO_GO` verdict inside a
governed fix cycle, see below) — it isn't directly composable through the flags in the table
below. Composition only ever adds or removes the composable stages from this order — it never
reorders them, except through the `--stages` escape hatch which sets an explicit list. Three layers combine, in
increasing precedence:

1. **Built-in default** — the `execution` preset (`implement → verify → done`).
2. **`pipeline.yaml`** (project-persistent) — `workflow.default: <preset>` selects a named preset;
   per-stage `<stage>.enabled: true` toggles a stage on for every run in this project.
3. **Launch flags** (per-run, highest precedence) — these win over `pipeline.yaml`.

| Flag | Effect |
|------|--------|
| `--workflow <preset>` | Select a named preset (`full`, `governed-execution`, `full-cycle`, `requirements-plan`, `implement-only`, `review-fix`, `review-only`, …). |
| `--review` / `--no-review` | Add / remove the single-reviewer stage for this run. |
| `--judge` / `--no-judge` | Add / remove the independent judge (requires `--review`). |
| `--brainstorm` / `--no-brainstorm` | Add / remove the `discuss` stage. |
| `--sdd` / `--no-sdd` | Add / remove the `sdd` stage. |
| `--plan` / `--no-plan` | Add / remove the `plan` stage. |
| `--stages a,b,c` | Escape hatch — run exactly this ordered list, overriding preset and flags. |
| `--pipeline <name>` | Run a named pipeline (`<bank>/pipelines/<name>.yaml`) with its own model routing. |

The single-reviewer path resolved by `--review` goes through `mb-reviewer-resolve.sh` and is
gated by `mb-work-severity-gate.sh`. The heavier 5-reviewer ensemble (aspect reviewers + a lead
reviewer synthesizing one report) only exists behind `--workflow governed-execution` or an
equivalent named workflow with `review_profile: ensemble`.

## Target resolution

The first positional argument resolves in this order: an existing path is used as-is; a substring
matches a plan basename under `<bank>/plans/*.md`; a topic name checks
`<bank>/specs/<topic>/tasks.md` for `mb-task` markers; a freeform phrase (3+ words) surfaces
candidates from both `plans/` and `specs/` for the user to confirm; an empty target falls back to
the first active-plan link in `roadmap.md`'s `<!-- mb-active-plans -->` block.

A "plan-as-wrapper" file can delegate execution to a spec entirely by declaring `linked_spec` (and
optionally `tasks: 1-3`) in its YAML frontmatter — this keeps a dated plan record for traceability
while the real work items live in the spec. `--range A-B` narrows execution to specific stages or
tasks; the marker style in the target file (`mb-stage` vs `mb-task`) determines which one applies.

## Per-item steps

For each pending item the loop resolved from the target:

- **Implement (5a)** — dispatched via `Task`, with the engineering-core preamble, tooling-core
  preamble, and the resolved role-agent's own file all prepended ahead of the item body. The
  implementer never self-marks DoD checkboxes done — the loop flips them deterministically later.
- **Protected-path check (5b)** — every file the implement/fix step touched is checked against
  `pipeline.yaml:protected_paths`. A violation halts the run unless `--allow-protected` was passed.
- **Verify (5c)** — the plan-verifier reviews the scoped diff (built via `mb-work-diff.sh`, never a
  bare `git diff`) against the item's DoD before any reviewer cycle is spent. A FAIL here halts the
  loop.
- **Review (5d)** — only when the workflow includes it. `mb-review.sh --emit-payload` assembles one
  deterministic markdown payload (plan context, diff, calibration examples, prior test evidence,
  and an auto-generated `tests` blocker when touched-file tests are red) so the reviewer only has
  to judge, never re-derive context. The resolved reviewer agent (or the 3-5 aspect reviewers plus
  a lead reviewer, in ensemble mode) emits strict JSON, parsed by `mb-work-review-parse.sh`.
- **Judge (5e)** — only when the workflow includes it. Returns `GO`, `GO_WITH_BACKLOG`, or `NO_GO`.
  This is the anti-infinite-loop gate: reviewers can keep finding improvements, but only a judge
  `NO_GO` sends the item back to implementation. Non-blocking findings become backlog items.
- **Fix cycle (5f)** — only on `NO_GO`, bounded by `workflow.loop.max_cycles` (default 2), enforced
  by the durable state machine in `mb-work-state.sh` so cycle-counting survives a crash or a
  compaction. Exhausting the budget triggers `on_max_cycles` handling — the bundled governed
  workflows with a fix step (`governed-execution`, `review-fix`) default to `judge_decides`;
  `stop_for_human` is only the no-fix `review-only` preset's terminal behavior.
- **Done (5g)** — only after every selected-workflow gate has passed for this item. The loop runs
  `mb-work-state.sh done` then `mb-work-checkbox.sh flip <source> <item_no>` — the only mechanism
  that is allowed to turn a DoD `⬜`/`[ ]` into `✅`/`[x]`. A refused flip means the loop's own state
  is out of sync, never something to work around by hand-editing the source file.

## Severity gates

Every reviewer finding is classified `blocker` / `major` / `minor`. The default gate (configurable
in `pipeline.yaml:review.severity_gate` or a named workflow's own rubric) allows zero blockers,
zero majors, and up to three minors before a cycle counts as passing. The reviewer's own verdict
(`APPROVED` / `CHANGES_REQUESTED`) and the severity-gate's pass/fail decision are deliberately
decoupled: the reviewer reports honest findings, the gate — driven by `mb-work-severity-gate.sh` —
decides whether those findings block the item.

## Sprint contracts, progress trend, and strategic pivoting (work-loop-v2)

Three additive layers wrap the base loop without replacing any numbered step:

- **Sprint contract phase** (opt-in via `--contract`, or mandatory per-project via
  `pipeline.yaml:review.require_contract: true`) runs before the implement step. It scaffolds a
  contract file (`<bank>/contracts/<plan-topic>_stage-<N>.md`) with In-scope / Plan-of-attack /
  Test-plan / DoD-checkpoints / Out-of-scope / Open-risks sections, has the role-agent write it,
  and sends it through a dedicated 4-category reviewer pass (`scope` / `dod` / `test_plan` /
  `out_of_scope`) before any code is written — a silent, empty out-of-scope section is a blocker.
  Capped at 3 contract-review cycles before a hard stop for human.
- **Progress trend** is computed every review cycle from the normalized reviewer verdict:
  `improving` (this cycle's weighted score is strictly lower than last cycle's), `stagnant`
  (within ±1 and still positive), `regressing` (strictly higher), or `null` (first cycle). The
  weighted score is `10*blocker + 3*major + 1*minor`, cached per item so consecutive cycles can be
  compared.
- **Strategic pivoting** watches consecutive `stagnant` cycles. Below `pivot_after_cycles` (default
  2) the loop keeps refining as before. At or above that threshold it forces a `pivot_in_role`
  re-dispatch — the same role-agent is told to discard the current approach and design something
  different, rather than patch the same idea again. Once the cycle count also reaches
  `pivot_escalate_to_architect_on` (default 4), the loop escalates to `pivot_via_architect`: a
  redesign sketch from `mb-architect` first, then the role-agent implementing against that sketch.

These three layers are fully opt-in and additive — a project that never sets `--contract` or hits
a stagnant trend sees byte-identical behavior to the base loop.

## Hard stops under `--auto`

Autopilot mode (`--auto`) skips per-item confirmation prompts but never skips a genuine hard stop:
cycle-budget exhaustion, a plan-verifier FAIL, a protected-path violation without
`--allow-protected`, budget exhaustion (`--budget TOK`), the sprint context guard's hard-stop
token threshold, a skipped cross-model review wave, a claim refused under parallel execution, or
an active FREEZE on the cross-session coordination board covering the current item's files. Every
hard stop surfaces the trigger and the next reasonable action instead of silently continuing.

## Related

- [Reviewer 2.0](reviewer-2.md) — the calibrated review payload assembly this loop's review step
  depends on.
- [Coordination board](coordination.md) — the cross-session protocol `/mb work` checks before
  claiming shared files under parallel execution.
- [pipeline.yaml reference](pipeline-yaml.md) — the config file that drives roles, workflows, and
  every gate described above.
- `/mb verify` — the same plan-verifier contract, runnable standalone outside the loop.
- `/mb done` — closes the session once a run finishes.
