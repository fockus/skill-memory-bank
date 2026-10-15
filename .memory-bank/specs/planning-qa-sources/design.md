---
type: spec-design
topic: planning-qa-sources
status: draft
created: 2026-10-15
linked_requirements: requirements.md
---

# Design: planning-qa-sources

> Slice S1 of `[SPEC:autopilot]`. Lightweight by construction (NFR-001, AGR-075, AGR-078): four coarse
> implementation tasks, no new script, no new Python package, no verifier of its own. Every change
> extends an existing script or prompt contract; `/mb work` output stays byte-identical when no QA
> option is on (REQ-019).

## Architecture

Two halves meet at one existing hand-off, the `/mb work` per-item JSON Line.

```
planning time                                       execution time (/mb work)
─────────────                                       ─────────────────────────
/mb plan ─┐                                         step 1/3: plan `qa: on` ⇒ --qa (C5)
/mb sdd ──┼─ mb-plan.sh --tier [--qa|--no-qa]       mb-work-plan.sh ─► JSON Line
          │   [--spec <topic>]                         + spec_path, plan_path   (C4)
          │   └─► plan frontmatter `qa:` (C1)        │
          │       + QA DoD item                       ├─► plan-verifier: Spec / Plan wrapper /
          └─ mb-qa (authoring mode, 1 dispatch)        │     QA cases / QA report lines      (C6)
              └─► qa/test_cases/<topic>/<id>.md (C2)  ├─► mb-review.sh --source … ⇒ ## Sources (C6)
                                                      ├─► judge: same ## Sources bytes     (C6)
/mb qa run (runner) ── skips needs_spec, proof:test   └─► 5c2 QA: selection @<topic>        (C5)
mb-qa-bug.sh set BUG-N fixed ─► reg-bug-N.md (C3)
```

Layering: the deterministic parts (QA declaration, wrapper scaffold, regression case, JSON fields,
payload section) live in existing scripts and are tested by bats; the judgement parts (tier, which
paths are "key", whether an expected result is derivable, coverage reading) stay in prompts and are
tested through the prompt-contract harness `tests/bats/lib/discuss_contract.bash`
(`assert_clause` + `assert_clause_load_bearing`), never by bare `grep -q`.

## Interfaces

### C1 — QA declaration of a plan (`qa:` frontmatter) — owner: `scripts/mb-plan.sh`

`mb-plan.sh <type> <topic> [--context <path>] [--sdd] [--tier small|standard|large|extra] [--qa|--no-qa] [--spec <topic>] [mb_path]`

- Without `--tier` the scaffold is byte-identical to today (no `qa:` line) — existing callers and
  tests are untouched.
- With `--tier`, one frontmatter line `qa: <declaration>`; first match wins:

| # | Condition | Declaration | QA DoD item |
|---|-----------|-------------|-------------|
| 1 | `--no-qa` (the prompt passes it for a user phrase such as "no QA") | `off — disabled` | no |
| 2 | effective `qa.enabled: false` (project `pipeline.yaml` over the bundled default) | `off — disabled` | no |
| 3 | tier `small`, no `--qa`, `qa.enabled: auto` (or unset) | `off — small tier` | no |
| 4 | `<bank>/qa/README.md` absent | `off — no QA target` | no |
| 5 | otherwise — tier standard/large/extra under `auto`, or any tier with `--qa` or `qa.enabled: true` | `on` | yes |

`qa.enabled` is three-valued (user decision 2026-10-15, design D3): `auto` = the tier rule above,
`true` = on for every tier, `false` = off. Plan time reads `qa.enabled` only (not `hosts.<h>.qa`).

- `on` appends to the last stage's DoD list: ``- [ ] QA: `/mb qa run @<topic>` passes qa.gate (no open critical or major bug)``.
- `--spec <topic>` writes `linked_spec: specs/<topic>` into the frontmatter, refuses (exit 1) when
  `<bank>/specs/<topic>/tasks.md` is absent, and titles stage 1 `Execute specs/<topic>` with the line
  ``**Run:** `/mb work <this plan>` — `specs/<topic>/tasks.md` is the source of truth.`` The single
  stage keeps `mb-plan-sync.sh` working (a stage-less wrapper exits 2 there, measured).
- stdout stays one line, the plan path. Unknown tier → exit 1. `mb-plan.sh` stays ≤ 300 lines (SRP).
- The tier → QA table is documented once, in `references/effort-tiers.md` (a `**QA:**` line per
  tier); `commands/plan.md`, `commands/sdd.md` and `agents/mb-qa.md` reference it.

### C2 — QA case catalog (`<bank>/qa/test_cases/<topic>/<id>.md`) — owner: `commands/qa.md` § new

Extends the shipped `/mb qa` scenario format (AGR-102: one catalog, no `specs/<topic>/qa.md`):

```yaml
---
id: <file stem>                 # unique within the catalog
tags: [<topic>]                 # `@<topic>` selects the plan's cases
driver: browser | cli | api
covers: [REQ-001, REQ-004]      # spec REQ ids; for a plan without REQs: DoD-<n> (n-th DoD bullet)
origin: specified | derived | regression
proof: live | test | both
status: needs_spec              # only when the expected result is not derivable (REQ-008)
---
```

- Written by `mb-qa` in **test-case authoring mode** (new section of `agents/mb-qa.md`): input plan
  path, topic, tier, requirements source (spec `requirements.md`, linked context, or plan DoD);
  writes only under `qa/test_cases/<topic>/`, never tests or product code; count rule from C1's
  tier table (standard: one per key user path; large/extra: one per externally testable REQ);
  `origin: specified` when the expected result is literal in a REQ/DoD line, `derived` when inferred.
- Live selection (`commands/qa.md` § run, `agents/mb-qa-runner.md`): cases with
  `status: needs_spec` or `proof: test` are not run; they are passed as `not_run` and listed under
  `## Not verified` as `<case> — not run: needs_spec` / `not run: proof test`. They are not Results
  rows, so the report title (which `/mb work` §5c2 reads for BLOCKED/SKIP) is unaffected.
- Only the authoring step and C3 write cases; `/mb work` §5c2 already halts a fix diff that touches
  `qa/test_cases/`.

### C3 — Regression case on fix — owner: `scripts/mb-qa-bug.sh set`

`mb-qa-bug.sh [--mb <bank>] set <BUG-NNN> fixed`, for a bug of severity critical or major:

- reads `- Scenario: <bank-relative case path>, step <N>` from the bug body; when that case exists,
  writes `<its dir>/reg-<bug-nnn lowercased>.md` (e.g. `reg-bug-003.md`) unless it exists:
  `id` = stem, `tags`/`driver`/`covers` copied from the source case (`covers: []` when it has none),
  `origin: regression`, `proof: both`; body = `/mb qa` sections, Steps/Expected taken from the bug's
  `- Steps:` / `- Expected:` lines, Preconditions/Cleanup "as in `<source case>`".
- stdout: `regression_case=<bank-relative path>` (`… exists` when already there) or
  `regression_case=none reason=no_scenario`; exit 0 in all three. medium/low and `open`/`wontfix`
  print nothing (today's behaviour).
- The id is known before the fix lands, so the §5c2 fix prompt can require the regression test to
  carry `mb:case reg-bug-<nnn>` (REQ-009).

### C4 — Work item locators (`scripts/mb-work-plan.sh` JSON Lines) — the seam

Additive keys, only on items that come from a spec (REQ-012, REQ-019):

| Key | When | Value |
|-----|------|-------|
| `spec_path` | `source == "spec"` (direct or through a wrapper) | absolute spec dir (`dirname(source_path)`) |
| `plan_path` | resolved through a wrapper, or exactly one plan in `<bank>/plans/*.md` (not `done/`) whose `linked_spec` resolves to this spec | absolute wrapper path; several matches → key omitted + one stderr notice |

- Plain plan items get neither key: the QA-off goldens in `tests/bats/fixtures/qa-golden/` stay
  byte-identical.
- The lookup lives in `scripts/mb_work_plan_wrapper.py` (one more tab field in its output); the shell
  adds at most three lines so `mb-work-plan.sh` stays ≤ 400 (zone contract
  `tests/pytest/test_s2_file_size_contract.py`).

### C5 — QA in `/mb work` from the plan declaration — owner: `commands/work.md`

- The run-level step is unchanged: `mb-workflow.sh` emits `qa` only when `enabled is True` or
  `--qa` (`scripts/mb-workflow.sh:404-407`), so the shipped `auto` never turns it on by itself
  (REQ-019). What turns it on for a plan is that plan's own `qa: on`, below.

- Step 1: a plan whose frontmatter says `qa: on` — for a spec target, the wrapper that links it
  (`grep -l '^linked_spec: *specs/<topic>' <bank>/plans/*.md`) — counts as `--qa` for both
  `mb-workflow.sh` and `mb-work-plan.sh`. No declaration → no flag → resolver output unchanged.
- §5c2 selection: `@<topic>` (the plan's `topic:`) when QA came from the declaration and the cadence
  is `stage` or `plan`; otherwise `qa.selector` as today (`run` keeps `all`, D-05).
- §5c2 fix prompt: a regression test for a blocking bug carries `mb:case reg-<bug id lowercased>`.
- `commands/work.md` stays ≤ 400 lines (zone file, 399 today): the additions are paid for by
  tightening prose in the touched sections, not by moving text into `references/work-reference.md`
  (already 400).

### C6 — Source bundle to verifier, reviewer and judge

| Agent | Delivery | Owner |
|-------|----------|-------|
| `plan-verifier` | prompt lines `Spec: <spec_path\|none>`, `Plan wrapper: <plan_path\|none>`, `QA cases: <bank>/qa/test_cases/<topic>/\|none`, `QA report: <path\|none>`; it reads the files itself (it already reads the spec triple) | `commands/work.md` §5c, `agents/plan-verifier.md` |
| reviewer | `mb-review.sh --emit-payload … --source <path>` (repeatable) appends `## Sources` after `## Quality DoD`: per source `### <path>` + content verbatim; a spec dir contributes its `requirements.md`; a missing path → exit 2. No `--source` → payload byte-identical | `scripts/mb-review.sh`, `agents/mb-reviewer.md` |
| judge | the payload's `## Sources` section verbatim — the same bytes the reviewer saw | `commands/work.md` §5e, `agents/mb-judge.md` |

Last QA report = newest `<bank>/qa/runs/<RUN_ID>-qa<n>/report.md` of this run; `none` before the
first QA run (with `qa.position: before_review` the first verify precedes QA — the verifier then
reports live proof as `pending`, the judge sees the report).

Verifier report additions (`agents/plan-verifier.md`):

- `### Plan DoD (<wrapper>)` and `### Spec REQ coverage (<spec>)` as separate sections when both
  exist (REQ-014); spec coverage = REQ → tasks whose `Covers:` name it.
- Plan↔spec divergence → CRITICAL `plan-spec divergence: …` (REQ-015): a REQ in the wrapper's scope
  that no task covers, or wrapper DoD/stage work no spec task or REQ asks for. Scope = all REQs for
  an unranged wrapper; for `tasks: A-B`, the `Covers:` union of that range (other REQs → INFO
  "outside this slice").
- `### QA coverage` (REQ-016): `| REQ | Case | Origin | Proof | Live | Test |`; Live = the case's
  Results status in the last QA report, `pending` without one, `n/a` for `proof: test`; Test =
  `file:line` of `mb:case <id>` under the test dirs, else `none`; `needs_spec` cases shown as such.
  Large/extra REQ with no case → WARNING; fixed regression case without an `mb:case` test → WARNING.
- Status `➖ NOTHING TO VERIFY` when the source has no REQ, no DoD item and no case (REQ-017);
  `commands/work.md` §5c halts the item on it.

## Contract

**Seams:**
- `/mb work` per-item JSON Line from `scripts/mb-work-plan.sh` (existing) — the single hand-off from planning artifacts to verifier, reviewer, judge and QA; it gains `spec_path`/`plan_path`, and the plan's `qa:` declaration is read through it.

The QA case frontmatter (C2) extends the existing `/mb qa` scenario format rather than opening a
second seam; the `qa:` declaration (C1) is plan frontmatter that `/mb work` already reads.

## Decisions

- **D1 — Authoring is a planning step, not a `/mb work` stage.** `mb-qa` is dispatched by
  `/mb plan`/`/mb sdd` right after the plan exists (D-05 "right after plan/sdd"; D-04 puts cases in
  drive's planning phase). A plan stage would be dropped by the wrapper redirect (`mb-work-plan.sh`
  executes the spec's tasks, not the wrapper's stages) and would need its own Eval. Cost: one
  dispatch (REQ-010). `commands/plan.md` gains `Task` in `allowed-tools`.
- **D2 — The plan file owns `qa:`; for a spec, the wrapper owns it.** One owner per fact. A spec run
  without a wrapper has no declaration → QA off → today's behaviour. `requirements.md` gets no `qa:`.
- **D3 — `qa.enabled` is `auto | true | false`; the shipped default is `auto` (user decision
  2026-10-15).** `auto` = the AGR-101 tier rule at plan time; `true` = QA on for every tier and, as
  today, the run-level QA step on every `/mb work` run; `false` = off. `auto` is not `True`, so the
  resolver (`scripts/mb-workflow.sh:406`) keeps the run-level step off and its JSON byte-identical.
  The validator (`scripts/mb_pipeline_validate_core.py` `validate_qa`, which also checks
  `hosts.<h>.qa`) accepts the string `auto` beside the booleans with no net line growth (zone file,
  400 lines); the PyYAML-less loader (`scripts/mb_pipeline_minimal_yaml.py` `parse_scalar`) already
  returns `"auto"` as a string — measured — so it only gets a test on the no-PyYAML path, and is
  edited only if that test shows otherwise. Banks whose `pipeline.yaml` copied the old
  `enabled: false` keep QA off until they change it to `auto` (CHANGELOG line).
- **D4 — Regression cases are written by the registry script, not an agent.** Deterministic, no extra
  dispatch, and the only writer besides the authoring step (Edge Cases: only the test-case stage
  edits cases).
- **D5 — Verifier reads files; reviewer and judge get content.** The reviewer never opens files
  (`agents/mb-reviewer.md` "Inputs"), so the bundle goes into its payload; the judge reuses those
  bytes; the verifier already reads the spec triple and gets the paths as mandatory inputs, which
  is not "agent chooses what to read" (rejected in D-06): each source is named and reported on.
- **D6 — `spec_path`/`plan_path` only on spec items.** For a plain plan `source_path` already is the
  plan; adding `plan_path` there would break the QA-off golden for no reader (REQ-019).

## Quality DoD

Rule sources (resolved by `scripts/mb-rules-resolve.sh`, referenced — never copied):
- [project] .memory-bank/RULES.md
- [profile] .memory-bank/rules-profile.json
- [project] AGENTS.md

Review rubric (from `pipeline.yaml:review_rubric`):
- logic: Every EARS requirement has at least one assertion in tests
- logic: Edge cases from requirements covered
- code_rules: SOLID: SRP — files <300 lines OR <=3 public methods
- code_rules: No placeholders (TODO/...)
- code_rules: Imports complete, functions copy-paste ready
- security: Input validation at boundaries
- security: No secrets in code
- security: No raw SQL string concat
- scalability: No N+1 queries introduced
- scalability: Async where IO-bound
- tests: Contract-first: Protocol/ABC defined before impl
- tests: Integration tests > unit tests (Testing Trophy)
- tests: No test.skip / describe.skip

Checker: `bash scripts/mb-rules-check.sh --files <touched-files-csv> --out json` — no violations
on this item's touched files.

## Eval declarations

Each task's red is observed after its bats file is materialised (D-05: the test is the first step of
the task). `bats <missing file>` exits 1 with `not ok 1 bats-gather-tests`, so every anchor names the
task's own test family prefix, which that line does not contain. Lines below are byte-identical to
the `**Eval:**` lines in `tasks.md`.

- **T1** — QA declaration, `qa.enabled: auto`, wrapper scaffold, authoring contract (family `planning_qa:`):
  **Eval:** bats tests/bats/test_planning_qa_default.bats — red: bats file materialised, mb-plan.sh has no --tier/--qa/--no-qa/--spec, the validator rejects qa.enabled auto and the plan, sdd, effort-tiers and mb-qa clauses are absent, so every named case planning_qa fails; exit: 1; output~: not ok [0-9]+ planning_qa:
- **T2** — live selection and regression cases (family `qa_catalog:`):
  **Eval:** bats tests/bats/test_qa_case_catalog.bats — red: bats file materialised, mb-qa-bug.sh set writes no regression case and the qa/runner clauses for needs_spec and proof test are absent, so every named case qa_catalog fails; exit: 1; output~: not ok [0-9]+ qa_catalog:
- **T3** — `## Sources` payload and verifier/judge contracts (family `review_sources:`):
  **Eval:** bats tests/bats/test_review_sources_contract.bats — red: bats file materialised, mb-review.sh rejects --source and the verifier, reviewer and judge clauses are absent, so every named case review_sources fails; exit: 1; output~: not ok [0-9]+ review_sources:
- **T4** — locators in JSON Lines and the `/mb work` wiring (family `source_bundle:`):
  **Eval:** bats tests/bats/test_work_source_bundle.bats — red: bats file materialised, mb-work-plan.sh emits no spec_path or plan_path and the work.md clauses for qa on, the bundle lines and NOTHING TO VERIFY are absent, so every named case source_bundle fails; exit: 1; output~: not ok [0-9]+ source_bundle:

## Risks & mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| `commands/work.md` (399/400) or `mb-work-plan.sh` (397/400) crosses the zone limit | H | M | C4/C5 line budgets; `tests/pytest/test_s2_file_size_contract.py` runs in the final suite |
| Projects with a copied `qa.enabled: false` never get the tier default | M | M | D3 CHANGELOG line (switch to `auto`); `/mb plan` prints the declaration so the user sees `off — disabled` |
| `auto` breaks a consumer that expects a boolean `qa.enabled` | L | M | the only runtime reader is `mb-workflow.sh` (`is True`); validator accepts `auto` on both loader paths, tested |
| A `needs_spec` or `proof: test` case reaches the runner and SKIPs, halting §5c2 | M | H | C2 selection filter in `commands/qa.md`; T2 test asserts the runner clause |
| Verifier coverage shows `pending` live proof under `before_review` | H | L | documented in C6; the judge gets the last report; drive's final QA (S3) closes it |
| Large requirements in the reviewer payload | M | L | only `requirements.md` of the spec, not design/tasks; the item body is already in `## Plan context` |
| Several wrappers slice one spec | L | L | `plan_path` omitted with a stderr notice (C4); running the wrapper directly still sets it |

## Edge cases

- `--qa` and `--no-qa` together → `--no-qa` wins (row 1), no error.
- `qa.enabled: true` in the project with a plan declaring `off — no QA target`: `/mb work` runs QA as
  today (AGR-098 behaviour) and the runner reports the missing target as BLOCKED; not changed here.
- A bug whose `- Scenario:` names no existing case, or no Scenario line → `regression_case=none`.
- A ranged wrapper (`tasks: 2-3`): REQs outside the range are INFO, never a divergence.
- `/mb work <topic>` on a spec with no wrapper: no `plan_path`, no QA declaration → QA off, verifier
  prints `Plan wrapper: none` and reports spec coverage only.
- A plain plan with no DoD bullet, no linked REQ and no case → `NOTHING TO VERIFY`, item halts.

## Open questions

- none — seam and D3 (`qa.enabled: auto`) confirmed by the user on 2026-10-15.
