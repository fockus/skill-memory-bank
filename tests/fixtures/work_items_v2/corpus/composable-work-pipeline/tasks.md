# Tasks: composable-work-pipeline

> Numbered, checkbox-tracked work items. Each task references the REQ-IDs it
> satisfies via the Covers field. TDD-first: tests before implementation.

<!-- mb-task:1 -->
## Task 1: Rewrite red contract tests to the default-no-review contract

**Covers:** REQ-002, REQ-011
**Role:** qa

**What to do:**
- Update `tests/pytest/test_pipeline_default_yaml.py`: assert default `stage_pipeline` == `[implement, verify, done]` (no review); repoint the gate/max_cycles assertion to the new top-level `review:` block (keys blocker/major/minor, max_cycles ≥ 1, on_max_cycles ∈ {stop_for_human, continue_with_warning}).
- Update `tests/pytest/test_mb_work_severity_gate.py`: keep the breach/pass cases (default `review.severity_gate` = {0,0,3}); add `test_no_review_configured_passes` (a pipeline.yaml with no review anywhere → exit 0).
- Update `tests/pytest/test_mb_pipeline_validate.py`: keep `_valid_minimal` valid; add `test_judge_without_review_fails` and `test_minimal_no_review_is_valid`.

**Testing (TDD — tests BEFORE implementation):**
- These ARE the tests; they go red first, then Tasks 2–5 turn them green.

**DoD:**
- [x] The 3 test files encode the new contract (default no review; review opt-in; gate no-op without review).
- [x] New tests added: no-review-passes, judge-without-review-fails, minimal-no-review-valid.
- [x] tests run (red is expected until Tasks 2–5).
<!-- /mb-task:1 -->

<!-- mb-task:2 -->
## Task 2: pipeline.default.yaml — `full` preset + per-stage enabled blocks

**Covers:** REQ-007, REQ-010
**Role:** backend

**What to do:**
- Add `workflows.full` with steps `[discuss, sdd, plan, implement, verify, review, judge, done]`, entrypoint `freeform_or_topic`, and alias (e.g. `everything → full`).
- Add per-stage opt-in blocks `judge.enabled: false`, `discuss.enabled: false`, `sdd.enabled: false`, `plan.enabled: false` (the `review:` block is already present this session).
- Keep default `stage_pipeline` = `[implement, verify, done]` (no review — already reverted this session).

**Testing (TDD — tests BEFORE implementation):**
- `test_pipeline_default_yaml`: `full` preset present with the 8-stage list; per-stage blocks present and boolean.

**DoD:**
- [x] `full` preset + `judge/discuss/sdd/plan.enabled` blocks in `references/pipeline.default.yaml`.
- [x] `test_pipeline_default_yaml` green.
- [x] `mb-pipeline-validate.sh` accepts the default yaml.
<!-- /mb-task:2 -->

<!-- mb-task:3 -->
## Task 3: severity-gate — read `review:` block, PASS no-op when no review

**Covers:** REQ-011, REQ-012, NFR-005
**Role:** backend

**What to do:**
- In `scripts/mb-work-severity-gate.sh::load_review_policy` (PyYAML path): read gate from `review.severity_gate` ▸ `stage_pipeline[step=review]` ▸ workflow `loop.severity_gate`; return a None/sentinel when none found.
- Mirror the same precedence in `parse_review_policy_without_yaml` (no-PyYAML path), parsing the top-level `review:` block.
- In `main`: when gate is the sentinel and there is no `--gate` override → print PASS and `exit 0` (remove the `exit 2 "no 'review' step"` hard failure).

**Testing (TDD — tests BEFORE implementation):**
- `test_mb_work_severity_gate`: existing breach/pass cases still hold against `review.severity_gate`; `test_no_review_configured_passes` exits 0; `test_default_gate_works_without_pyyaml` reads the `review:` block.

**DoD:**
- [x] Gate reads `review:` block (yaml + no-yaml) and no-ops PASS when no review configured.
- [x] All `test_mb_work_severity_gate` tests green.
<!-- /mb-task:3 -->

<!-- mb-task:4 -->
## Task 4: mb-workflow.sh — per-stage flags, --stages, enabled merge, precedence

**Covers:** REQ-001, REQ-003, REQ-004, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-016
**Role:** backend

**What to do:**
- Parse new flags: `--review/--no-review`, `--judge/--no-judge`, `--brainstorm/--no-brainstorm`, `--sdd/--no-sdd`, `--plan/--no-plan`, `--stages <csv>`.
- Implement the 5-step merge: preset → pipeline.yaml `<stage>.enabled` → launch flags (win) → canonical re-sort → `--stages` override.
- `--brainstorm` enables `discuss` (alias). Emit the composed list via `--steps`/`--json` (add a `source` field).

**Testing (TDD — tests BEFORE implementation):**
- New `tests/pytest/test_mb_workflow_compose.py`: matrix of (preset, yaml enabled, flags) → expected ordered list; `--stages` overrides; flags beat yaml; brainstorm⇒discuss; determinism (same input → same output).

**DoD:**
- [x] All new flags parsed; merge deterministic + canonical-ordered.
- [x] `test_mb_workflow_compose.py` green; existing `mb-workflow.sh` callers unaffected (legacy stage_pipeline order preserved verbatim).
<!-- /mb-task:4 -->

<!-- mb-task:5 -->
## Task 5: mb-pipeline-validate.sh — fail-fast on bad chains

**Covers:** REQ-013, REQ-014
**Role:** backend

**What to do:**
- Validate a composed stage list: if `judge` ∈ steps and `review` ∉ steps → error "judge requires review — add --review or enable review in pipeline.yaml".
- If `sdd` or `plan` ∈ steps with no resolvable upstream input (no topic / no spec) → error naming the missing input.
- Keep the existing top-level pipeline.yaml validation intact (no "verify before review" rule).

**Testing (TDD — tests BEFORE implementation):**
- `test_mb_pipeline_validate`: `test_judge_without_review_fails` (exit ≠ 0, message names review); `test_minimal_no_review_is_valid`; missing-upstream case.

**DoD:**
- [x] Fail-fast messages name the missing prerequisite/input.
- [x] `test_mb_pipeline_validate` green.
<!-- /mb-task:5 -->

<!-- mb-task:6 -->
## Task 6: Document flags + precedence in commands/work.md

**Covers:** REQ-001, NFR-004
**Role:** developer

**What to do:**
- Document the three-layer precedence, every per-stage flag, `--stages`, the `full` preset, and the default-no-review behaviour in `commands/work.md` (flags table + examples).
- Note `--review` = single reviewer (resolver + gate); ensemble stays `--workflow governed-execution`.

**Testing (TDD — tests BEFORE implementation):**
- Doc-contract test (extend `test_doc_counts`/work.md grep) asserting the flags + `full` preset are documented.

**DoD:**
- [x] `commands/work.md` documents flags, precedence, `full`, default-no-review.
- [x] Doc test green (`test_work_md_documents_composition`).
<!-- /mb-task:6 -->

<!-- mb-task:7 -->
## Task 7: Full verification — green build

**Covers:** REQ-015, NFR-001, NFR-003
**Role:** qa

**What to do:**
- Run full `pytest tests/pytest/`, `bats tests/bats/ tests/e2e/`, `ruff check .`, the two CI shellcheck commands → all green.
- Run `bash scripts/mb-spec-validate.sh composable-work-pipeline`.
- Confirm legacy `stage_pipeline`-only projects still resolve (back-compat smoke).

**Testing (TDD — tests BEFORE implementation):**
- N/A (verification task) — relies on Tasks 1–6 tests.

**DoD:**
- [x] pytest (1190 passed) + bats (779, exit 0) + ruff (clean) + shellcheck (clean) all green.
- [x] `mb-spec-validate.sh composable-work-pipeline` passes.
- [x] No backward-compat regression (legacy stage_pipeline order preserved verbatim).
<!-- /mb-task:7 -->
