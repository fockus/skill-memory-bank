---
description: Execute Memory Bank workflow modes from pipeline.yaml — existing plan/spec execution by default, optional full-cycle requirements→plan→implementation→review flows.
allowed-tools: [Bash, Read, Task]
---

# /mb work [target] [--workflow NAME] [--review] [--fix] [--loop N] [--range A-B] [--auto] [--dry-run] [--budget TOK] [--max-cycles N] [--allow-protected]

Run the executable engine using a workflow mode resolved from `pipeline.yaml`. By default, `/mb work` is intentionally simple: **implement → verify → done** from an already-created plan/spec. Projects can opt into stricter local modes such as **governed-execution** (`implement → verify → review ensemble → judge → fix/backlog → done`), **full-cycle** (`discuss → sdd → plan → implement → verify → done`), **requirements-plan**, **implement-only**, **review-fix**, or **review-only**. Severity gates, judge gates, token budgets, protected-path checks, and the sprint context guard provide hard stops for `--auto` mode.

> **Scope.** Phase 3 Sprint 1 shipped `pipeline.yaml`. Sprint 2 shipped target resolution, range parsing, role-detection, plan emission, implement-step dispatch — and extended execution to spec tasks (`specs/<topic>/tasks.md`) as a first-class source alongside plan stages. **Sprint 3 (this command)** wires the review-loop, severity gates, fix-cycle, plan-verifier integration, `--auto` hard stops, `--budget` token tracking, and protected-path enforcement.
>
> **Phase 4 will add:** `--slim` / `--full` context strategy via `context-slim-pre-agent.sh` and `pre-agent-protected-paths.sh` runtime hooks; `superpowers:requesting-code-review` skill auto-detection in the installer.

## Why /mb work?

Plans declared with `/mb plan` carry stage markers, DoD, and TDD instructions. Specs created with `/mb sdd` carry `<!-- mb-task:N -->` markers in `specs/<topic>/tasks.md`, each linked to REQ-IDs. `/mb work` consumes both for execution modes: pick a work item (stage or task), route it to the right role-agent (mb-backend, mb-frontend, mb-ios, mb-android, mb-architect, mb-devops, mb-qa, mb-analyst, with mb-developer as fallback), let the agent implement against the DoD, verify the result, then put the verified diff through a real reviewer-approval loop instead of trusting the implementer's self-assessment. For full-cycle modes, `/mb work` first delegates to the same contracts as `/mb discuss`, `/mb sdd`, and `/mb plan` before executing work items.

## Reference material

The workflow-mode matrix, JSON Lines schema, sprint-contract / progress-trend /
worked examples, the underlying script inventory, parallel-run
guidance, and the artifact formats (spec tasks as executable source,
plan-as-wrapper, range parsing) live in **`references/work-reference.md`** —
read it when you need any of them (sprint contracts / progress trend / strategic
pivoting are in `references/work-loop-v2.md`). This file keeps the normative
per-item loop.

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

## Per-stage workflow Claude Code follows

When the user types `/mb work [args...]`:

1. **Resolve workflow mode.** Resolve the effective pipeline and selected workflow:

   ```bash
   bash scripts/mb-workflow.sh --mb <bank> --workflow <name-or-empty> [--review|--no-review] [--judge|--no-judge] [--fix|--no-fix] [--brainstorm] [--sdd] [--plan] [--stages a,b,c] --json
   ```

   **Thread every composition flag the user typed into this call verbatim** — that is what turns `/mb work <target> --review --fix --loop 4` into `implement → verify → review → fix → done` with a bounded fix-cycle. `--fix` and `--judge` each require `review` (exit 2 otherwise); a flag-added `fix` on a preset with no loop block gets loop defaults (`returns_to: verify`, `max_cycles` from `pipeline.yaml:review`). The returned JSON contains `steps`, `entrypoint`, `interactive`, and `loop`. The orchestrator MUST follow this workflow instead of hard-coding one order. `--max-cycles N` — and its alias **`--loop N`** — overrides `workflow.loop.max_cycles` for this run only: it is the ceiling on review→fix cycles before `on_max_cycles` handling fires (step 5f), not a count of review dispatches to run unconditionally.

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
   RUN_ID=$(bash scripts/mb-work-state.sh init <source> <first_item_no> \
     --source-path <source_path> --source-topic <source_topic> --mb <bank>)
   ```

   **Thread `--source-path`/`--source-topic` verbatim from the item's JSON Lines fields of the same name — never omit them.** `<source>` is only the *category* (`plan`/`spec`); the eval gate resolves a task's declared `**Eval:**` through the locator fields. Passing the category alone makes every lookup target the non-existent `<bank>/specs/spec/tasks.md`, at which point `eval-red`/`eval-green` refuse with `no Eval declaration resolvable` and the whole red→green gate silently stops applying to real runs.

   `mb-work-state.sh init` resolves `max_cycles` from `workflow.loop.max_cycles` (or CLI `--max-cycles N`) when neither is passed explicitly — pass `--max-cycles N` to `init` when the CLI flag was given. If `--budget TOK` was given, run `bash scripts/mb-work-budget.sh init <TOK> --run-id "$RUN_ID" --mb <bank>`. Subsequent steps call `bash scripts/mb-work-budget.sh check --run-id "$RUN_ID" --mb <bank>` after each Task dispatch; exit 1 = warn (log and continue), exit 2 = stop (halt the loop). Add tokens after each Task with `bash scripts/mb-work-budget.sh add <delta> --run-id "$RUN_ID" --mb <bank>`. Threading `--run-id` means an orphaned `.work-budget.json` left over from a different, aborted run is recognised as stale (warn, exit 1) instead of silently throttling this run.

   **Parallel opt-in (`MB_WORK_PARALLEL`, off by default).** Everything above is the single-run default — unchanged, byte-identical. Driving **several concurrent `/mb work` runs from one Claude Code session** (intra-plan waves, or one plan per git worktree — see *Parallel runs* below) requires exporting `MB_WORK_PARALLEL=1` first, which switches `mb-work-state.sh`/`mb-work-budget.sh` from the legacy singleton files (`.work-state.json` / `.work-budget.json`) to **per-run slots**: `<bank>/.work-state/<run_id>.json` and `<bank>/.work-budget/<run_id>.json`. With the env var set:

   ```bash
   export MB_WORK_PARALLEL=1
   RUN_ID=$(bash scripts/mb-work-state.sh new-run-id)
   bash scripts/mb-work-state.sh init <source> <first_item_no> --run-id "$RUN_ID" \
     --source-path <source_path> --source-topic <source_topic> --mb <bank>
   ```

   `mb-work-state.sh new-run-id` mints a fresh run id up front (prints it, writes nothing) so it can be threaded into `init` from the start. `init` then claims `<source>` for `"$RUN_ID"` in a source→run index: if another **live** (`phase != done`) run already claims that same source, `init` refuses with **exit 4** (`source '<source>' already claimed by run <id>; pass --takeover to override`) — halt the loop for this run (pick a different pending item, or a different source) unless the orchestrator deliberately wants to steal a stale/abandoned claim, in which case pass `--takeover` to force the claim. Thread the same `--run-id "$RUN_ID"` to every subsequent `mb-work-state.sh`, `mb-work-budget.sh`, and `mb-work-checkbox.sh` call for this run — that is what keeps its state, budget, and checkbox-flip gate isolated from any other concurrently running run.

5. **For each pending item** (iterate over the JSON Lines output):

   The stage body is read from the markers in the source file. For `kind=task` items, read between `<!-- mb-task:N -->` markers. For `kind=stage` items, read between `<!-- mb-stage:N -->` markers.

   For every item after the first, re-arm the per-item loop-state (this resets the item's `cycle` counter and `phase` back to `in-progress` while keeping the same session `run_id`):

   ```bash
   bash scripts/mb-work-state.sh init <source> <item_no> --run-id "$RUN_ID" \
     --source-path <source_path> --source-topic <source_topic> --mb <bank>
   ```

   ### 5a0. Eval-first gate (red MANDATORY — before implement)

   For **any task carrying an Eval declaration** — gated or not — **materialise the eval code before implement**; writing the failing test is D-05's first step of the task, not an afterthought. REQ-008 keys this gate on the declaration, not on gatedness: a non-gated docs/config task whose structural Eval is a real file/section/linter check runs the same red→green cycle. Only a validated non-gated **waiver** (`**Eval:** none — waiver: <reason>`) skips it. Then record the observed red through the authoritative writer (never by editing the state JSON directly — direct JSON editing is forbidden):

   ```bash
   # write the exact Eval command to a file, then:
   bash scripts/mb-work-state.sh eval-red --cmd-file <path> --output-re '<ERE>' [--expected-exit <n>] --run-id "$RUN_ID" --mb <bank>
   ```

   The **helper itself** runs the byte-identical `--cmd-file` from the repo root and matches the C1 anchors (`--output-re`, plus `--expected-exit` when declared) against the *actual* observed output and exit — you do not pass a verdict, exit, or match flag; a green/red cannot be spoofed through the CLI. `eval-red` exits:

   - **0** — the declared red was actually observed → proceed to implement.
   - **1** — a **foreign failure** (actual output does not match `--output-re`, or actual exit ≠ `--expected-exit`) or an already-green command. This is a **FAIL that blocks implement** — a fake or absent red is not a contract. **No flag reopens it:** `eval-red` has no `--force`/`--override` and rejects any unknown argument with exit 2, and an item whose declared, non-waived Eval has no proven red→green is refused by `mb-work-state.sh done` with **exit 5** — so the item cannot be closed through the sanctioned sequence either. The two real ways forward are to make the declared red actually appear (fix the anchor, or the command, or the code) or — for a non-gated task only — to waive the Eval in the spec. A user instruction to press on regardless grants no mechanical exemption; record it in `progress.md` through `mb-work-progress-append.sh` and expect the item to stay open.
   - **2** — usage / broken state / uncompilable ERE.

   **Waiver only for non-gated.** A task with no runtime surface may waive the behavioural red (`**Eval:** none — waiver: <reason>`) **only when it is non-gated**; a gated task must carry a real red. The verify step (5c) later runs `eval-green`, which reruns the byte-identical command and demands an actual green.

   ### 5a0b. Quality DoD — render once, give it to all three (C6)

   Render the criterion the work will be judged by ONCE, before dispatching anyone, and keep the path: implementer, reviewer and judge must hold the same bytes, and a second render is how that stops being true.

   ```bash
   QUALITY_DOD=<bank>/tmp/quality-dod-<item_no>.md
   bash scripts/mb-quality-dod.sh --spec <bank>/specs/<topic> --mb <bank> > "$QUALITY_DOD"
   ```

   Exit 1 = a rule source the spec declares does not exist — **halt the item**; a review judged against rules nobody selected is worse than one that never ran (REQ-017). Spec-less (plan) runs skip this step. Inline the file's contents verbatim into the implementer prompt below, into `§5d` via `--quality-dod "$QUALITY_DOD"`, and into the judge prompt in `§5e`. Never edit or reflow it.

   ### 5a1. Contract task: two dispatches, then the red gate

   A task carrying `**Layer:** contract` is ONE checkbox but TWO implementer dispatches: the registry it declares has to be frozen before the checkers that satisfy it exist, and the current loop dispatches an implementer once per item.

   1. **Dispatch A (declare).** Prompt composed exactly as 5a, plus: write NO product or checker files; print `MB_CONTRACT_CHECKERS_JSON={"checkers":[…]}` as its own block **before** the final `MB_WORK_RESULT_JSON=` line, then stop. The envelope stays the last non-empty block, so S5's report contract is untouched.
   2. **Orchestrator.** Validate that JSON, write the fenced ```json Contract-checkers``` block into the task body — the bank is written by the orchestrator, never by the agent — and record `bash scripts/mb-work-state.sh step contract_declared --run-id "$RUN_ID" --mb <bank>`.
   3. **Dispatch B (build).** Hand back the frozen registry; the implementer writes only the checkers and their unit tests.
   4. **Red gate.** Once the checker unit tests are green: `bash scripts/mb-contract-gate.sh red --spec <spec-dir> --mb <bank>`. Exit 0 → proceed to business implementation. Exit 1 (`fake_red` — a checker green before the code exists; `foreign_failure` — it failed for some other reason) or exit 2 → **local hard stop**: item stays open, checkbox is not flipped, no business implement dispatch. Do **not** route this into `mb-work-adapt.sh`: that envelope describes a task's complexity, not a checker that proves nothing, and routing it would defer an immediate refusal until the cycles run out. A requirement no checker can observe is the same hard stop, class "spec defect".

   **Resume.** A schema-valid registry in the task body **and** a `contract_declared` step → skip A, resume at B. Missing either → repeat A. Business implementation stays blocked until `red` exits 0.

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

   **Eval-green first (for any task that recorded an eval-red in 5a0).** Rerun the byte-identical command through the authoritative writer and require an actual green before spending verifier/reviewer cycles:

   ```bash
   bash scripts/mb-work-state.sh eval-green --cmd-file <path> --run-id "$RUN_ID" --mb <bank>
   ```

   The helper reruns the saved (byte-identical) `--cmd-file` and exits 0 **only** on an actual exit 0; a still-red command or a drift of `--cmd-file` vs the recorded `cmd` → exit 1, which **halts** the item (the implementation did not turn its own declared red green).

   **Contract checkers (any spec whose contract task is closed).** Then `bash scripts/mb-contract-gate.sh verify --spec <spec-dir> --mb <bank>`. Exit 1 = verification FAIL, a checker is still red. Exit 2 = the red-evidence gate refused and **no checker ran**: a checker whose red was never observed, or whose registry command changed since it was, cannot be verified against. Both halt the item.

   Then dispatch the plan-verifier before code review when both are present. The verifier catches missing tests, incomplete DoD, broken traceability, and architecture drift before reviewer cycles are spent.

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
   bash scripts/mb-rules-check.sh --files <touched-csv> --out json > <bank>/tmp/rules-check-<N>.json
   bash scripts/mb-review.sh --emit-payload --plan <plan path> --item <N> --run-id "$RUN_ID" --mb <bank> \
     --quality-dod "$QUALITY_DOD" --rules-check-json <bank>/tmp/rules-check-<N>.json
   ```

   Run the checker ONCE and reuse the same JSON for the reviewer and the judge (C6). `mb-review.sh` exits 1 without emitting a payload when that JSON carries a CRITICAL violation — code that already breaks the agreed rules does not get a review spent on it, and no reviewer is dispatched.

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

   Dispatch `roles.judge` with a different model when the project config provides one. Give it: plan/spec/DoD, verifier report, lead-review report, previous judge decision, diff, verification evidence, and the **verbatim contents of `"$QUALITY_DOD"`** — the same bytes §5a and §5d received.

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
   bash scripts/mb-work-state.sh done ${RUN_ID:+--run-id "$RUN_ID"} --mb <bank>
   bash scripts/mb-work-checkbox.sh flip <source> <item_no> ${RUN_ID:+--run-id "$RUN_ID"} --mb <bank>
   ```

   The `${RUN_ID:+--run-id "$RUN_ID"}` form is required, not decorative. Under `MB_WORK_PARALLEL` the state lives in the per-run slot `<bank>/.work-state/<run_id>.json`, so a bare `done --mb <bank>` reads the singleton, finds nothing and exits 2 (`no active work-state`) — the run can be started but never completed through this sequence. With `RUN_ID` unset (the single-run default) the expansion is empty and the commands are byte-identical to the plain form.

   `mb-work-state.sh done` **refuses with exit 5** when the item's declared, non-waived `**Eval:**` has no proven red→green transition in this run's state (no eval record, an unverifiable proof, no observed red, or `green_exit != 0`), and equally when the locator fields resolve to a real tasks.md that has no such item. That refusal is the gate working: re-run `eval-red`/`eval-green` for the item rather than routing around it. A task declaring `Eval: none` (an explicit waiver) and a source with no declaration surface at all stay ungated. On success it sets `phase: "done"` for the current `item_no` — the completion gate `mb-work-checkbox.sh flip` requires before it will touch the source file's DoD bullets. `flip` then converts that item's `⬜`/`[ ]` DoD bullets to `✅`/`[x]`, scoped to its `<!-- mb-stage:N -->` / `<!-- mb-task:N -->` marker block only. **A refused flip (exit 1) means the gate did not truly pass** — treat it as a bug in the loop (state/item mismatch), not as something to work around by editing the file directly.

   Workflows without a `judge` step (e.g. `execution`) still route through this exact sequence: `mb-work-state.sh done` is called once `verify` reports PASS (there is no judge decision to wait for), so the flip stays fully deterministic even without a judge gate.

   **Graph refresh (bounded, fail-open — I-133).** Immediately after `flip`, refresh the code graph through the single-consumer catch-up CLI so it does not silently drift when the opt-in git hook (`hooks/git/post-commit-codegraph.sh`) is not installed. Because this lives right after `flip`, both governed workflows and `judge`-less workflows like `execution` reach it — every path that flips a checkbox also refreshes the graph:

   ```bash
   GRAPH="<bank>/codebase/graph.json"
   [ -f "$GRAPH" ] && python3 scripts/mb-graph-query.py catchup \
     --graph "$GRAPH" --src-root <repo> --json >/dev/null 2>&1 || true
   # fail-open: never block or fail the item loop on graph refresh
   ```

   All guards live INSIDE the CLI — never reimplement them inline and **never spawn `mb-codegraph.py` in the background or take ad-hoc locks**: existing-graph-only (first build stays manual — Stage 1 `/mb map` / Stage 6 `/mb graph --apply`), one consumer via the non-blocking `codebase/.graph.lock` flock, hard budget `MB_GRAPH_CATCHUP_BUDGET` (default 30 s, process-group kill), cooldown after a failed attempt, opt-in layer preservation, kill-switch `MB_GRAPH_AUTOUPDATE=off`. The call is synchronous but bounded; a `locked`/`cooldown`/`timed_out` result is fine — the next query or SessionEnd catches up.

   - Without `--auto`: prompt the user to confirm before moving to the next item.
   - With `--auto`: continue to the next item unless one of the hard stops (below) fired.

6. **End-of-run summary.** When all requested items are processed, summarise: workflow used, items attempted, items PASS / WARN / FAIL, files touched, total budget spent, verifier verdicts, review cycles used. Run `bash scripts/mb-work-budget.sh clear ${RUN_ID:+--run-id "$RUN_ID"} --mb <bank>` and `bash scripts/mb-work-state.sh clear ${RUN_ID:+--run-id "$RUN_ID"} --mb <bank>` to remove the budget and loop-state — the same run-id threading as `done`/`flip`, so a parallel run clears its own slot rather than the singleton.

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
| Active FREEZE on the cross-session board (`<bank>/COORDINATION.md` — the resolved bank, local **or** registered-global **or** legacy; never a hardcoded `.memory-bank/`) covers files of the current item, or an unACKed HANDOVER targets its scope | manual observation at item start (board checkpoint, `references/coordination.md`) | yes — wait for the lifting entry or escalate on the board |

When any hard stop fires, the loop halts even under `--auto`. The orchestrator surfaces the trigger, the item state, and the next reasonable action (rerun with adjusted flags, edit pipeline.yaml, compact, etc.).

## Arguments

| Flag | Meaning | Sprint |
|------|---------|--------|
| `<target>` | Plan / spec topic / freeform / empty | 2 |
| `--workflow NAME` | Select a named workflow from `pipeline.yaml:workflows` | 4 |
| `--range A-B` | Range over stages (plan) or tasks (spec) or sprints (phase) | 2 |
| `--dry-run` | Print selected workflow + execution plan, don't dispatch | 2 |
| `--auto` | Skip per-item confirmation prompts; obey hard stops | 3 |
| `--review` / `--judge` / `--fix` (+ `--no-*`) | Compose stages for this run; `--fix` adds the review→fix loop (requires `--review`) | 4 |
| `--max-cycles N` / `--loop N` | Override `pipeline.yaml` review `max_cycles` — the fix-cycle ceiling | 3 |
| `--budget TOK` | Initialise token budget; halt at `stop_at_percent` | 3 |
| `--allow-protected` | Permit Write/Edit on `protected_paths` globs | 3 |
| `--slim` / `--full` | Context strategy for sub-agents — exports `MB_WORK_MODE=slim` (or `full`) for the loop subshell | Phase 4 (Sprint 2) |
| `--contract` | Opt in to the sprint-contract phase for this run only (persist per-project via `pipeline.yaml:review.require_contract: true`) | work-loop-v2 (Phase 2) |

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
