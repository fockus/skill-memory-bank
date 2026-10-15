---
type: feature
topic: qa-pipeline-integration
status: in_progress
depends_on: []
parallel_safe: false
linked_specs: []
created: 2026-10-14
---
# Plan: feature — qa-pipeline-integration

**Baseline commit:** 952d490b6ac6fec7212b405ea7c17cec84fa299e

## Context

**Problem:** `/mb qa` (commands/qa.md, agents/mb-qa-runner.md, scripts/mb-qa-bug.sh) runs only by hand. `qa.md`
already promises that `/mb work` and `/mb team` run it at the end and that open critical/major bugs block "done", but
nothing implements that. The owner wants QA configured once in the pipeline, bugs fixed in a loop, and the run to
continue along the chain after the bugs are fixed (AGR-098).

**Expected result:** with `qa.enabled: true` in `pipeline.yaml` (or `/mb work --qa`), `/mb work` runs `mb-qa-runner`
at the configured point; open `critical`/`major` bugs of the run re-dispatch the implementer with the bug reports,
the stand is refreshed by `qa.prepare`, QA re-runs, and on a clean gate the item continues to review/judge/done.
Medium/low bugs stay in `qa/bugs.md` and are listed in the run summary. With QA off, every resolver/plan output is
byte-identical to today. `/mb drive` and `/mb team` see open blocking bugs through a `qa` firewall check.

**Decisions (AGR-098):** QA lives inside verify (quality-track Task 14 contract, AGR-008): no new canonical step name.
`qa.cadence` = `stage | plan | run` (`run` covers several plans), default `plan`; `qa.position` =
`before_review | after_review`, default `before_review`. Gate blocks on `critical` (→ `blocker`) and `major`.
The QA fix loop is QA's own (like verify FAIL → implementer), so it works in the default `medium` workflow that has
no `fix`/`review` steps.

**Related files:**
- `references/pipeline.default.yaml`, `docs/pipeline-yaml.md` — config schema and docs
- `scripts/mb-workflow.sh` — resolved workflow JSON (`verify_cadence` precedent, `CADENCES`)
- `scripts/mb-work-plan.sh` — per-item `verify`/`final_verify` flags (lines ~105-118, ~386-392)
- `scripts/mb_pipeline_validate_core.py`, `scripts/mb_pipeline_validate_blocks.py` — block validation
- `scripts/mb-work-state.sh` — `cycle` counter precedent (exit 3 = budget spent)
- `scripts/mb-work-severity-gate.sh` — `--gate`, `--counts-stdin`, `--ignore-approval`
- `scripts/mb-flow-verify.sh` — default check set and `SEVERITY` map (~304, ~419)
- `commands/work.md` §5c/5f/5g/6, `commands/qa.md`, `agents/mb-qa-runner.md`, `scripts/mb-qa-bug.sh`

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: QA config contract — schema, resolver, per-item flags, bug JSON

**Role:** backend

Boundary: public contract (pipeline.yaml keys + resolver JSON) that stages 2 and 3 consume.

**Files:** references/pipeline.default.yaml, scripts/mb-workflow.sh, scripts/mb-work-plan.sh, scripts/mb_pipeline_validate_blocks.py, scripts/mb_pipeline_validate_core.py, scripts/mb-qa-bug.sh, scripts/mb-work-state.sh, tests/bats/test_mb_qa_bug.bats, tests/bats/test_mb_workflow_qa.bats, tests/pytest/test_pipeline_validate_qa.py

**What to do:**
- `pipeline.default.yaml`: top-level `qa:` block, `enabled: false`, `cadence: plan`, `position: before_review`,
  `selector: "all"`, `prepare: ""`, `gate: {critical: 0, major: 0}`, `max_cycles: 3`,
  `on_max_cycles: stop_for_human` (comment per key, one line each).
- Validator: `qa` block — booleans/enums (`cadence` ∈ stage|plan|run, `position` ∈ before_review|after_review,
  `on_max_cycles` ∈ stop_for_human|continue_with_warning), non-negative ints in `gate` with keys only from
  critical|major|medium|low, `max_cycles` ≥ 1, `selector`/`prepare` strings. Unknown keys → error.
- `mb-workflow.sh`: `--qa` flag (env `FLAG_QA=on`), host override `hosts.<host>.qa`, emit `"qa": {...resolved}` in
  the JSON **only when enabled**; `--qa` without a resolvable block uses the defaults. Off → output unchanged.
- `mb-work-plan.sh`: `--qa` passthrough and per-item `"qa": true|false` computed like `verify` from `qa.cadence`
  (stage → every item; plan → last pending item; run → last item of the last target). Key emitted only when QA is on.
- `mb-qa-bug.sh list --json [--open] [--run ID]`: normalized review shape
  `{"verdict","counts":{blocker,major,medium,minor},"issues":[{severity,category:"qa",file:<scenario>,line:<step>,message:<id title>,fix:""}]}`,
  mapping critical→blocker, major→major, medium→medium, low→minor; `--run` keeps bugs whose body has
  `- Run: <id>` or `- Seen again: <id>` (runner writes `- Run:`; update `agents/mb-qa-runner.md` bug template in Stage 2).
- `mb-work-state.sh qa-cycle [--max N]`: separate crash-surviving counter `qa_cycle`; exit 3 when spent (mirror `cycle`).

**Testing (TDD — tests BEFORE implementation):**
- bats golden: `mb-workflow.sh` and `mb-work-plan.sh` JSON with QA off is byte-identical to the pre-change output on
  a fixture bank (capture golden before editing).
- bats: `--qa` adds `qa` with defaults; `qa.enabled: true` in fixture pipeline does the same; cadence stage/plan/run
  sets per-item `qa` flags as specified, including multi-target `run`.
- bats: `list --json` mapping, counts, `--run` filter, empty registry → APPROVED with zero counts; output passes
  `mb-work-review-parse.sh` and `mb-work-severity-gate.sh --gate '{"blocker":0,"major":0}'` exits 1 with one open
  critical and 0 with only medium/low.
- bats: `qa-cycle` increments, exits 3 past `--max`, independent from `cycle`.
- pytest: validator accepts the default block, rejects each bad value and unknown key.

**Code rules:** SRP (bug JSON stays in mb-qa-bug.sh, config in resolver), YAGNI (no new step name), byte-identity when off.

<!-- mb-stage:2 -->
### Stage 2: `/mb work` QA step and fix loop

**Role:** backend

Boundary: orchestration layer (command/agent prompts) over the Stage 1 contract.

**Files:** commands/work.md, commands/qa.md, agents/mb-qa-runner.md, docs/pipeline-yaml.md, scripts/mb-qa-bug.sh, tests/bats/test_mb_qa_bug.bats, tests/pytest/test_mb_qa_command.py, tests/pytest/test_work_qa_contract.py

**What to do:**
- `work.md` new §5c2 "QA (only when step 1 JSON has `qa` and the item has `qa: true`)":
  - Position: `before_review` → right after a PASS of 5c; `after_review` → after the review/judge gate passes, before 5g.
  - Run `qa.prepare` (non-zero exit → halt with its output; this is an environment failure, not a bug).
  - Dispatch `mb-qa-runner` per `qa.md` § run with `selection = qa.selector`, `expected_build = git rev-parse HEAD`
    (or working-tree marker) and `run_id = <work run id>-qa<cycle>`.
  - Gate: one deterministic command `mb-qa-bug.sh gate --run <qa run id> [--gate '<qa.gate JSON>']` (new subcommand,
    default gate `{"critical":0,"major":0}`): maps qa.gate keys to blocker|major|medium|minor, gives every level the
    gate does not name an unbounded limit, pipes only the open-bug `counts` of that run into
    `mb-work-severity-gate.sh --counts-stdin --ignore-approval --gate <mapped>` and returns its exit (0 pass, 1 fail,
    2 input error). Stage 1 found: a missing level means limit 0, and `--ignore-approval` refuses a payload with a verdict.
    Exit 0 → continue the chain. Exit 1 → `mb-work-state.sh qa-cycle --max <qa.max_cycles>`; exit 0 → re-dispatch
    the implementer with the blocking bugs (full bug bodies + evidence paths) and the instruction "regression test
    first when the defect is reachable from tests; never edit `<bank>/qa/`", then halt if the fix diff touches
    `<bank>/qa/test_cases/`, protected-path check, 5b1 evidence, 5c verify, back to 5c2.
    Exit 3 → `on_max_cycles` (stop_for_human halts; continue_with_warning needs explicit human confirmation).
  - Any scenario BLOCKED or SKIP → halt as environment failure (QA did not finish), never counted as a fix cycle.
  - Medium/low bugs: listed in the item report and in §6 summary, not fixed.
- `work.md` §6 summary: QA runs, cycles used, bugs opened/fixed/left by severity, report paths.
- `mb-qa-runner.md`: accept `expected_build`; if the stand shows a different build or none can be read while
  `expected_build` is set and README `## Target` names how to read the build → all scenarios BLOCKED "stale stand";
  bug template gains `- Run: <run_id>`.
- `qa.md` § When to run: point to `pipeline.yaml` `qa:` / `--qa` instead of the current unimplemented promise.
- `docs/pipeline-yaml.md`: `## qa` section — keys, defaults, the loop in five lines.

**Testing (TDD — tests BEFORE implementation):**
- pytest contract: work.md §5c2 exists and names `qa.prepare`, `mb-qa-runner`, `list --json`, `--ignore-approval`,
  `qa-cycle`, both positions, `on_max_cycles`; §6 mentions QA; runner prompt has `expected_build` and `- Run:`.
- Live smoke (manual, recorded in the plan report): fixture project with one passing and one failing cli scenario,
  `/mb work --qa` on a one-stage plan → QA FAIL → implementer fix → QA PASS → item done; second run with an unfixable
  bug stops at `max_cycles`.

**Code rules:** KISS (reuse severity gate and state counter), no duplicated host dispatch text (reference qa.md § run).

<!-- mb-stage:3 -->
### Stage 3: `qa` firewall check for `/mb drive` and `/mb team`

**Role:** backend

Boundary: parallel chunk — disjoint files from Stage 2, depends only on Stage 1 `list --json`.

**Files:** scripts/mb-flow-verify.sh, references/scripts.md, CHANGELOG.md, tests/bats/test_mb_flow_verify_qa.bats

**What to do:**
- Add `qa` to the default check set: runner prints `{"name":"qa","ok":<no open critical/major>,"findings":[<id severity title>]}`;
  `ok: null` (skip) when `<bank>/qa/bugs.md` is absent, so projects without QA are unaffected.
- `SEVERITY["qa"] = "blocker"`.
- CHANGELOG: one line under the `/mb qa` entry; `references/scripts.md`: the new `list --json` and `qa-cycle` forms.

**Testing (TDD — tests BEFORE implementation):**
- bats: no registry → check skipped, firewall verdict unchanged; one open critical → `qa` fails as blocker;
  only medium/low open → `qa` ok; fixed critical → ok.

**Code rules:** quote every interpolated path with `_shq` like the neighbouring checks.

---

## DoD (whole plan)

- [x] QA off: `mb-workflow.sh` and `mb-work-plan.sh` outputs byte-identical to baseline (golden bats green)
- [x] `qa:` block validated; every invalid value and unknown key rejected (pytest green)
- [x] `--qa` / `qa.enabled` emit resolved `qa` and per-item `qa` flags for stage, plan and run cadences (bats green)
- [x] `mb-qa-bug.sh list --json` feeds `mb-work-severity-gate.sh`: open critical → exit 1, only medium/low → exit 0 (bats green)
- [x] `qa-cycle` counter exits 3 past `max_cycles`, independent from `cycle` (bats green)
- [x] work.md §5c2 describes prepare → runner → gate → fix → re-verify → re-QA → continue, both positions, on_max_cycles (pytest contract green)
- [x] Live smoke: failing scenario fixed in the loop and the item reaches done; unfixable bug stops at max_cycles (report in plan notes)
- [x] `/mb drive` firewall fails on an open critical bug and is unchanged without `qa/bugs.md` (bats green)
- [x] Targeted tests green, ruff and shellcheck clean on changed files; full suite run before commit with reds classified

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| QA re-tests a stale stand after a fix and burns cycles | H | `qa.prepare` before every QA run; runner compares `expected_build`, stale → BLOCKED, not FAIL, not a cycle |
| Resolver/plan output drifts for users without QA | M | golden byte-identity tests captured before the first edit |
| Flaky scenario loops forever | M | `qa.max_cycles` hard stop via `qa-cycle` exit 3; flaky bugs keep their severity and stay visible |
| Fix agent "fixes" by changing scenarios | L | implementer prompt forbids editing `<bank>/qa/`; §5c2 halts when the fix diff touches `<bank>/qa/test_cases/` |
| Browser unavailable on a host (Pi/OpenCode without MCP) | L | runner falls back to `@playwright/cli` + Chromium; any BLOCKED/SKIP halts as environment failure |

## Gate (plan success criterion)

On a fixture project, `/mb work --qa` turns a failing acceptance scenario into a filed critical bug, fixes it in the
loop, re-runs QA green and completes the item, while every resolver/plan output with QA off stays byte-identical.

## Live smoke report (2026-10-14)

Fixture `/tmp/qa-loop` (CLI `greet.sh`, scenario `greeting.md @smoke`, default pipeline with `qa.enabled: true`, `selector: "@smoke"`), followed `work.md` §5c2 step by step; runner dispatched through the qa.md inline fallback (agent not installed yet).
- Resolver emitted `qa` (cadence plan, before_review, gate critical/major 0, max_cycles 3); `mb-work-plan.sh` marked item 1 `qa: true`.
- Low bug (missing comma) → filed `low`, `gate` exit 0 → chain continues, bug stays in `qa/bugs.md`.
- Crash (`exit 1`) → filed `critical` with Impact line, `gate` exit 1 (`blocker=1 > gate=0`), `qa-cycle` → 1.
- Implementer got the bug body: regression test red → fix → green; `qa/test_cases/` untouched.
- Re-run `-qa1`: PASS, runner set BUG-001 `fixed`, `gate` exit 0, `done` + `flip` closed the item.
- Unfixable path: `qa-cycle --max 3` → rc 0,0,0,3 (fourth call = budget spent → `on_max_cycles`).
- Unfixable path, real loop with the installed `mb-qa-runner` agent (fixture `/tmp/qa-loop2`, `qa.max_cycles: 1`): `-qa0` FAIL → BUG-001 critical, `gate` exit 1, `qa-cycle --max 1` rc 0; no effective fix; `-qa1` FAIL → same bug as `repeat` (`- Seen again: …-qa1`), `gate` exit 1, `qa-cycle` rc 3 "qa_cycle budget exhausted" → `on_max_cycles: stop_for_human`.

## Verify cycle 1 fixes

- CRITICAL byte-blind golden compare → `cmp -s` (tests/bats/test_mb_workflow_qa.bats); stdlib fallback `qa` pinned (tests/pytest/test_mb_pipeline_validate_r2.py); open-major firewall case added (tests/bats/test_mb_flow_verify_qa.bats).
- Verify cycle 2: the runner's stand-down SKIP bypassed the all-BLOCKED halt (dead stand → 1 BLOCKED + SKIPs, no bugs, gate 0). §5c2 and the hard-stop row now halt on any BLOCKED or SKIP; pinned by `test_work_qa_halts_on_any_unrun_scenario`; docs/pipeline-yaml.md aligned.
