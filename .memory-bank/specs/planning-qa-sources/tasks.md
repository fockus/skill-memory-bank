# Tasks: planning-qa-sources

> Slice S1 of `[SPEC:autopilot]`. Four coarse implementation tasks plus the rendered integration
> layer (NFR-001, AGR-078): a boundary only where the owner or a dependency changes. Tasks 1–3 own
> disjoint files and run as one wave; Task 4 wires `/mb work` to what 1 and 3 ship.
> Red conditions describe the state after the task's bats file is materialised. Prompt clauses are
> asserted only through `tests/bats/lib/discuss_contract.bash` (`assert_clause` +
> `assert_clause_load_bearing`), never by a bare `grep -q`. Roles are bare.
> Budgets: Stage 1 = 230000, Stage 2 = 80000, Stage 4 = 100000; total 410000.

<!-- mb-task:1 -->
## Task 1: Plan-time QA declaration, qa.enabled auto, test-case authoring and the spec wrapper

**Stage:** 1
**Covers:** REQ-001, REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-007, REQ-008, REQ-010, REQ-011, REQ-020, REQ-021
**Role:** developer
**Blocked-by:** none
**Scope:** scripts/mb-plan.sh, scripts/mb_pipeline_validate_core.py, scripts/mb_pipeline_minimal_yaml.py, commands/plan.md, commands/sdd.md, agents/mb-qa.md, references/effort-tiers.md, references/templates.md, references/pipeline.default.yaml, docs/pipeline-yaml.md, CHANGELOG.md, tests/bats/test_planning_qa_default.bats
**Budget:** 100000
**Eval:** bats tests/bats/test_planning_qa_default.bats — red: bats file materialised, mb-plan.sh has no --tier/--qa/--no-qa/--spec, the validator rejects qa.enabled auto and the plan, sdd, effort-tiers and mb-qa clauses are absent, so every named case planning_qa fails; exit: 1; output~: not ok [0-9]+ planning_qa:

**What to do:**
- `scripts/mb-plan.sh`: add `--tier small|standard|large|extra`, `--qa`, `--no-qa`, `--spec <topic>` per design C1 — the five-row declaration table (first match wins), the QA DoD item on `on`, the `linked_spec` wrapper with one `Execute specs/<topic>` stage; no `--tier` keeps today's output byte-identical; stays ≤ 300 lines.
- `references/effort-tiers.md`: one `**QA:**` line per tier and a short "QA declaration" paragraph (values, opt-outs, `qa/README.md` rule) — the single source the prompts reference.
- `commands/plan.md`: pass `--tier` (and `--no-qa` for a user request to skip QA) to the scaffold; new step "QA test cases": when the plan says `qa: on`, dispatch `mb-qa` once in authoring mode (host adapter table as in `commands/qa.md` § run) with plan path, topic, tier and the requirements source; add `Task` to `allowed-tools`; the next-step report names the declaration.
- `commands/sdd.md`: after Step 10, offer the wrapper (`mb-plan.sh <type> <topic> --spec <topic> --tier <tier>`), create it without asking under `--auto` or when QA would be on, then run the plan's QA step on it; keep the zone file ≤ 400 lines.
- `agents/mb-qa.md`: "Test-case authoring mode" section per design C2 — inputs, output dir only, case frontmatter (`id`, `tags: [<topic>]`, `covers`, `origin`, `proof`, `status: needs_spec`), count rule by tier, `specified` vs `derived`, never tests or code.
- `references/templates.md` § Plan as execution wrapper: the `qa:` key and `mb-plan.sh --spec`.
- `references/pipeline.default.yaml`: `qa.enabled: auto`; `scripts/mb_pipeline_validate_core.py` `validate_qa` accepts `auto` beside booleans for `qa` and `hosts.<h>.qa` (no net line growth, zone 400); `scripts/mb_pipeline_minimal_yaml.py` only if the no-PyYAML test fails; `docs/pipeline-yaml.md` documents `auto` / `true` / `false`; one CHANGELOG line incl. "change a copied `false` to `auto`" (design D3).

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_planning_qa_default.bats`, every case named `planning_qa: …`: the five declaration rows in a temp bank (README present/absent, project `qa.enabled: false`, `--qa`/`--no-qa`, both flags), QA DoD item present only for `on`, no `--tier` byte-identical to the pre-change scaffold, `--spec` frontmatter + refusal without `tasks.md` + `mb-work-plan.sh` resolves the spec tasks through the wrapper + `mb-plan-sync.sh` exits 0 on it, unknown tier exit 1.
- Prompt clauses through the harness: plan.md dispatches `mb-qa` once on `qa: on`; sdd.md offers/creates the wrapper; effort-tiers QA lines; mb-qa authoring mode names the output dir, the five frontmatter fields, `needs_spec` and the tier count rule.
- `qa.enabled: true` → `on` for `--tier small`; `--no-qa` still wins.
- `mb-pipeline-validate.sh` exit 0 on the bundled default and on `auto`/`true`/`false` in `qa` and `hosts.<h>.qa`, exit 1 on `maybe` — with PyYAML and with a `yaml.py` shim on `PYTHONPATH` that raises `ModuleNotFoundError` (pattern of `tests/bats/test_mb_pipeline_host.bats`).
- `mb-workflow.sh --json` with the bundled `auto` emits no `qa` key and equals `tests/bats/fixtures/qa-golden/workflow.json`.

**DoD:**
- [x] the five declaration rows and the wrapper scaffold behave as in design C1, proven by named bats cases
- [x] plan/sdd/mb-qa/effort-tiers clauses pass `assert_clause_load_bearing`
- [x] `qa.enabled: auto` is the shipped default, validated on both loader paths, and leaves the workflow JSON byte-identical
- [x] `mb-plan.sh` ≤ 300 lines; `commands/sdd.md`, `scripts/mb_pipeline_validate_core.py`, `scripts/mb_pipeline_minimal_yaml.py` ≤ 400 lines
- [x] tests pass (were red)
- [x] lint clean (shellcheck on mb-plan.sh, ruff on the touched Python)
<!-- /mb-task:1 -->

<!-- mb-task:2 -->
## Task 2: QA case catalog at run time — live selection and regression cases

**Stage:** 1
**Covers:** REQ-007, REQ-008, REQ-009
**Role:** developer
**Blocked-by:** none
**Scope:** scripts/mb-qa-bug.sh, commands/qa.md, agents/mb-qa-runner.md, tests/bats/test_qa_case_catalog.bats
**Budget:** 50000
**Eval:** bats tests/bats/test_qa_case_catalog.bats — red: bats file materialised, mb-qa-bug.sh set writes no regression case and the qa/runner clauses for needs_spec and proof test are absent, so every named case qa_catalog fails; exit: 1; output~: not ok [0-9]+ qa_catalog:

**What to do:**
- `scripts/mb-qa-bug.sh set <id> fixed`: for critical/major bugs write the regression case per design C3 (path from `- Scenario:`, no overwrite, copied `tags`/`driver`/`covers`, `origin: regression`, `proof: both`, `regression_case=` line on stdout); medium/low and other statuses unchanged.
- `commands/qa.md` § new: the catalog frontmatter (design C2) in the template; § run: cases with `status: needs_spec` or `proof: test` are dropped from the live list and passed as `not_run`.
- `agents/mb-qa-runner.md`: list `not_run` cases under `## Not verified` as `<case> — not run: needs_spec` / `not run: proof test`; they are not Results rows.

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_qa_case_catalog.bats`, every case named `qa_catalog: …`: major and critical fixed → case written with the copied fields; existing case not overwritten (`exists`); medium fixed → no case, no stdout; no Scenario line → `regression_case=none reason=no_scenario`; the existing `tests/bats/test_mb_qa_bug.bats` still passes untouched.
- Prompt clauses through the harness: qa.md selection filter and template fields; runner `Not verified` rule.

**DoD:**
- [x] regression case written exactly for fixed critical/major bugs with a resolvable scenario, never overwritten
- [x] needs_spec / proof test cases never reach a live run and never produce a SKIP row
- [x] tests pass (were red)
- [x] lint clean (shellcheck on mb-qa-bug.sh)
<!-- /mb-task:2 -->

<!-- mb-task:3 -->
## Task 3: Review payload sources and the verifier, reviewer and judge contracts

**Stage:** 1
**Covers:** REQ-013, REQ-014, REQ-015, REQ-016, REQ-017
**Role:** developer
**Blocked-by:** none
**Scope:** scripts/mb-review.sh, agents/plan-verifier.md, agents/mb-reviewer.md, agents/mb-judge.md, tests/bats/test_review_sources_contract.bats
**Budget:** 80000
**Eval:** bats tests/bats/test_review_sources_contract.bats — red: bats file materialised, mb-review.sh rejects --source and the verifier, reviewer and judge clauses are absent, so every named case review_sources fails; exit: 1; output~: not ok [0-9]+ review_sources:

**What to do:**
- `scripts/mb-review.sh`: repeatable `--source <path>` per design C6 — `## Sources` after `## Quality DoD`, `### <path>` + verbatim content, a spec dir contributes `requirements.md`, a missing path exits 2; no `--source` → payload byte-identical.
- `agents/plan-verifier.md`: the four invocation lines, separate `### Plan DoD` and `### Spec REQ coverage` sections, the CRITICAL plan-spec divergence rule with the ranged-wrapper scope, `### QA coverage` table, `➖ NOTHING TO VERIFY` status (design C6); keep additions compact.
- `agents/mb-reviewer.md`: `## Sources` as the payload's optional last section; findings judged against its REQs and wrapper DoD.
- `agents/mb-judge.md`: input "the payload's `## Sources` section, the same bytes"; a verifier CRITICAL plan-spec divergence is an unmet acceptance criterion (`NO_GO`).

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_review_sources_contract.bats`, every case named `review_sources: …`: payload with spec dir + wrapper + QA report sources ends with `## Sources` holding all three; payload without `--source` equals the pre-change payload for the same input; missing source exits 2.
- Prompt clauses through the harness: verifier sections, divergence = CRITICAL, coverage table columns, NOTHING TO VERIFY; reviewer Sources section; judge Sources input.

**DoD:**
- [x] `--source` renders `## Sources` and leaves the payload byte-identical without it
- [x] verifier, reviewer and judge clauses pass `assert_clause_load_bearing`
- [x] tests pass (were red)
- [x] lint clean (shellcheck on mb-review.sh)
<!-- /mb-task:3 -->

<!-- mb-task:4 -->
## Task 4: Work items carry the bundle and /mb work wires it

**Stage:** 2
**Covers:** REQ-009, REQ-012, REQ-013, REQ-017, REQ-018, REQ-019
**Role:** developer
**Blocked-by:** 1, 3
**Scope:** scripts/mb-work-plan.sh, scripts/mb_work_plan_wrapper.py, commands/work.md, tests/bats/test_work_source_bundle.bats
**Budget:** 80000
**Eval:** bats tests/bats/test_work_source_bundle.bats — red: bats file materialised, mb-work-plan.sh emits no spec_path or plan_path and the work.md clauses for qa on, the bundle lines and NOTHING TO VERIFY are absent, so every named case source_bundle fails; exit: 1; output~: not ok [0-9]+ source_bundle:

**What to do:**
- `scripts/mb_work_plan_wrapper.py` + `scripts/mb-work-plan.sh`: `spec_path` / `plan_path` per design C4, including the reverse wrapper lookup for a direct spec target; at most three new shell lines (zone ≤ 400).
- `commands/work.md` per design C5/C6: step 1 `qa: on` ⇒ `--qa`; §5c verifier lines `Spec:` / `Plan wrapper:` / `QA cases:` / `QA report:` and the `NOTHING TO VERIFY` halt; §5c2 `@<topic>` selection and the `mb:case reg-<bug id>` fix-prompt rule; §5d `--source` for each present source; §5e judge gets the `## Sources` bytes; file stays ≤ 400 lines by tightening the touched sections.

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_work_source_bundle.bats`, every case named `source_bundle: …`: wrapper target and direct topic target both emit `spec_path` and `plan_path`; two wrappers → no `plan_path` + one stderr notice; plain plan emits neither and equals `tests/bats/fixtures/qa-golden/plan.jsonl`; workflow JSON for a plan without `qa: on` equals `tests/bats/fixtures/qa-golden/workflow.json`.
- Prompt clauses through the harness: qa on ⇒ --qa, `@<topic>` selection, the four verifier lines, NOTHING TO VERIFY halts, `--source` in §5d, judge Sources, `mb:case` rule.

**DoD:**
- [x] spec items carry `spec_path`/`plan_path`, plain plans stay byte-identical to the QA-off goldens
- [x] work.md clauses pass `assert_clause_load_bearing`; `commands/work.md` and `scripts/mb-work-plan.sh` ≤ 400 lines (`tests/pytest/test_s2_file_size_contract.py` green)
- [x] tests pass (were red)
- [x] lint clean (shellcheck on mb-work-plan.sh, ruff on mb_work_plan_wrapper.py)
<!-- /mb-task:4 -->

<!-- mb-task:5 -->
## Task 5: Integration tests

**Stage:** 4
**Layer:** integration
**Covers:** REQ-001, REQ-002, REQ-003, REQ-004, REQ-020, REQ-021, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010, REQ-011, REQ-012, REQ-013, REQ-014, REQ-015, REQ-016, REQ-017, REQ-018, REQ-019
**Role:** qa
**Scope:** tests/**
**Budget:** 100000

**What to do:**
- Integration tests over the real wiring; mock only external boundaries.
- Test function names follow the C4 mapping rule: `test_` + the scenario's `test_id` with `-` replaced by `_`.

**Testing (TDD — tests BEFORE implementation):**
- The success scenario plus the spec's main edge scenarios.

**DoD:**
- [x] Covers scenario test ids: `test_REQ_001__qa_declaration_follows_tier_opt_outs_and_target`, `test_REQ_005__test_case_authoring_contract`, `test_REQ_008__fixed_major_bug_yields_a_regression_case`, `test_REQ_011__spec_gets_a_plan_wrapper`, `test_REQ_012__work_items_carry_spec_and_plan_paths`, `test_REQ_013__agents_receive_the_source_bundle`, `test_REQ_016__verifier_coverage_table_and_nothing_to_verify`, `test_REQ_018__plan_qa_declaration_turns_qa_on_in_work`, `test_REQ_021__pipeline_qa_enabled_auto_is_accepted_and_inert`; green (were red)
- [x] External mocks ≤5 (Testing Trophy)
<!-- /mb-task:5 -->
