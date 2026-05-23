---
type: feature
topic: reviewer-v2
status: planned
depends_on: []
parallel_safe: false
linked_specs: []
sprint: 1
phase_of: harness-upgrade
created: 2026-05-23
baseline_commit: bf4fceea6065bdf84fac9f2a18c3b4c346d88dd1
---

# Plan: feature — Reviewer 2.0 (S1 of harness-upgrade)

**Baseline commit:** bf4fceea6065bdf84fac9f2a18c3b4c346d88dd1
**Linked spec:** [.memory-bank/specs/reviewer-2.0/design.md](../specs/reviewer-2.0/design.md)
**Sprint type:** single Sprint (6 stages). Sibling Sprints S2/S3/S4 deferred — see spec §11.

## Context

**Problem.** `mb-reviewer` currently judges code from a prose rubric without calibration examples and without knowing whether tests pass. This produces verdict drift across iterations (GAP-1, Anthropic harness article), lets the loop pass code with red tests if the reviewer overlooks them (GAP-5), and we have no way to detect rubric drift when models or examples evolve (GAP-7).

**Expected result.** Reviewer step in `/mb work` is split into a deterministic **payload orchestrator** (new `scripts/mb-review.sh`) and a "pure judge" `mb-reviewer`. The orchestrator loads layered few-shot examples, resolves the test cache (sha-keyed, TTL-bounded), pre-injects auto-findings on red tests, and assembles a 5-section payload. A runnable golden calibration suite (`tests/calibration/`) lets us detect rubric drift on demand and weekly via non-blocking CI.

**Related files:**
- Spec: `.memory-bank/specs/reviewer-2.0/design.md`
- Existing review entry: `commands/work.md` step 3c
- Existing reviewer agent: `agents/mb-reviewer.md`
- Existing severity gate (untouched): `scripts/mb-work-severity-gate.sh`
- Existing test runner agent: `agents/mb-test-runner.md`
- Existing pipeline defaults: `references/pipeline.default.yaml`
- Rules profile (drives `stack` for examples): `.memory-bank/rules-profile.json`

**Sprint boundaries.** Source files in scope: ~17. Rubric example markdown and calibration case fixtures (≈25 files) are data/content templates, not behavior changes — counted, but treated as a single batch in stages 2/3/6.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Orchestrator skeleton + sha/TTL cache helper

**What to do:**
- Create `scripts/mb-review.sh` with arg parsing: `--input <case-dir>` (for golden suite), `--emit-payload` (dump to stdout, no LLM dispatch), `--refresh-tests` (force cache miss), default mode (live review for `/mb work`).
- Create `scripts/mb-review-cache.sh` exposing helpers: `compute_touched_sha <files...>`, `cache_is_fresh <ttl>`, `cache_write <json>`, `cache_path` (returns `.memory-bank/tmp/last-tests.json`).
- Wire `mb-review.sh` to source the cache helper. No payload assembly yet — just skeleton + cache plumbing.
- Make scripts executable; add shebang `#!/usr/bin/env bash` and `set -euo pipefail`.

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_mb_review_sha.bats` — unit tests for `compute_touched_sha`: deterministic across re-runs with identical inputs; sort-stable (different orderings produce same sha); missing-file marker prepended (`DELETED:`); empty input handled.
- Bats helper: stub `.memory-bank/tmp/` under a temp dir per test.

**DoD (SMART):**
- [ ] `scripts/mb-review.sh` exists, executable, `shellcheck` clean.
- [ ] `scripts/mb-review-cache.sh` exists, executable, `shellcheck` clean.
- [ ] `bash scripts/mb-review.sh --help` prints flag reference and exits 0.
- [ ] `tests/bats/test_mb_review_sha.bats` has ≥4 test cases, all PASS via `bats tests/bats/test_mb_review_sha.bats`.
- [ ] `mb-rules-check.sh` reports 0 violations on the two new scripts.

**Code rules:** SOLID (SRP — orchestrator ≠ judgment), KISS, no premature abstraction. Scripts ≤300 lines combined.

---

<!-- mb-stage:2 -->
### Stage 2: Examples loader + layered resolver + baseline examples (common / python / go)

**What to do:**
- In `mb-review.sh`, add `load_examples` function: walks the 4-layer precedence list (project-stack → project-common → skill-stack → skill-common), parses each markdown file by `---`-delimited blocks with YAML front-matter, deduplicates by `example_id` (higher precedence wins).
- Selection logic: respect `review_examples.max_count` (default 8) and `review_examples.rotation` (default `hash_run_id`). When rotating, seed selection with SHA(run_id) and aim for ≥1 example per category present in the pool.
- Read `stack` from `.memory-bank/rules-profile.json`. Fallback to `common` only when profile absent.
- Author baseline files:
  - `references/rubric-examples/common.md` — 3 stack-agnostic examples (one logic, one security, one tests-missing).
  - `references/rubric-examples/python.md` — 3 Python examples covering `code_rules` (SRP-violation), `tests` (missing contract test), and one extra.
  - `references/rubric-examples/go.md` — 3 Go examples covering `code_rules` (error-wrap missing), `logic`, and one extra.
- Each example follows the spec §4 format: front-matter (`example_id`, `stack`, `category`, `severity`), `### Bad` snippet, `### Expected verdict fragment` JSON.

**Testing (TDD):**
- `tests/bats/test_mb_review_examples_loader.bats` — integration tests:
  - layered precedence: project override beats skill baseline on `example_id` collision
  - missing stack falls back to `common` only
  - missing-everything degrades to empty `examples` section (no crash)
  - `max_count=8` truncates a 12-example pool, retaining category coverage
  - rotation deterministic for the same `run_id`
- ≥5 test cases total.

**DoD (SMART):**
- [ ] `load_examples` implemented in `mb-review.sh`, ≤120 lines.
- [ ] `references/rubric-examples/common.md` exists with ≥3 example blocks; covers ≥2 categories.
- [ ] `references/rubric-examples/python.md` exists with ≥3 example blocks; covers `code_rules` + `tests` at minimum.
- [ ] `references/rubric-examples/go.md` exists with ≥3 example blocks; covers `code_rules` + `logic` at minimum.
- [ ] `tests/bats/test_mb_review_examples_loader.bats` ≥5 tests, all PASS.
- [ ] Manual: `bash scripts/mb-review.sh --emit-payload --stack=python --input=...` shows the `## Calibration examples` section populated.

**Code rules:** ISP — examples loader exposes ≤3 public functions. DRY — front-matter parsing reused, not duplicated per layer.

---

<!-- mb-stage:3 -->
### Stage 3: Remaining stack baseline examples (typescript / frontend / mobile / backend)

**What to do:**
- Author `references/rubric-examples/typescript.md` — 3 examples covering `code_rules` (any-leak), `security` (XSS via dangerouslySetInnerHTML or similar), and one extra.
- Author `references/rubric-examples/frontend.md` — 3 examples covering FSD layer violations, accessibility miss, and one extra.
- Author `references/rubric-examples/mobile.md` — 3 examples covering UDF violation, threading misuse, and one extra.
- Author `references/rubric-examples/backend.md` — 3 examples covering Clean Architecture direction violation, N+1 query, and one extra.
- Cross-suite audit: across all 7 example files, every category (`logic`, `code_rules`, `security`, `scalability`, `tests`) has ≥3 examples in total.

**Testing (TDD):**
- Extend `test_mb_review_examples_loader.bats` with one assertion per new stack: loading `<stack>` produces ≥3 examples.
- New test: cross-pool category coverage — running loader over the full reference set yields all 5 categories with ≥3 examples each.

**DoD (SMART):**
- [ ] 4 new `rubric-examples/*.md` files exist, each with ≥3 example blocks.
- [ ] Cross-pool: every category has ≥3 examples across the suite.
- [ ] `test_mb_review_examples_loader.bats` extended; all tests PASS.
- [ ] No regression in stages 1-2 bats files.

**Code rules:** Examples are content, not abstractions — keep `### Bad` snippets minimal and realistic.

---

<!-- mb-stage:4 -->
### Stage 4: Test-cache resolver + payload assembly + auto-finding pre-injection

**What to do:**
- In `mb-review.sh`, implement `resolve_test_cache`:
  - compute `touched_sha` for `git diff --name-only <baseline>..HEAD` (baseline from active plan frontmatter, else `HEAD~1`)
  - compare with `.memory-bank/tmp/last-tests.json:touched_files_sha` and `run_id` age vs `test_cache_ttl_sec` (read from `pipeline.yaml`, default 600)
  - HIT → use as `prior_evidence`
  - MISS → dispatch `Task(mb-test-runner)` with hint `scope=touched`, then re-read
- Implement `build_payload`: emits markdown with 5 sections in fixed order: `## Plan context`, `## Diff`, `## Calibration examples`, `## Prior evidence`, `## Auto-generated findings (MUST INCLUDE)` (omitted when tests pass).
- Implement `inject_auto_finding`: when `prior_evidence.tests_pass == false`, build the auto-finding JSON object and include it both in the payload preamble and in a post-validation list (to verify reviewer output later).
- Add `pipeline.yaml` key resolution in the orchestrator (read with `yq` if installed, else awk-based fallback).

**Testing (TDD):**
- `tests/bats/test_mb_review_cache.bats` — sha stability across re-runs with identical inputs; TTL expiry path (file timestamp manipulation); `--refresh-tests` invalidates cache; `schema_version` mismatch triggers MISS.
- `tests/bats/test_mb_review_payload_assembly.bats` — all 5 sections present in order on green-tests case; section 5 absent on green tests; example truncation respects `max_count`; rotation deterministic for fixed `run_id`.
- `tests/bats/test_mb_review_auto_finding_red.bats` — when stubbed `prior-tests.json` has `tests_pass=false`, the payload contains `## Auto-generated findings (MUST INCLUDE)` with at least one blocker/`tests` entry; the auto-finding carries `auto_generated: true` and top-5 failures.

**DoD (SMART):**
- [ ] `resolve_test_cache`, `build_payload`, `inject_auto_finding` implemented; total `mb-review.sh` ≤350 lines (or split into a helper module if exceeded).
- [ ] `test_mb_review_cache.bats` ≥4 tests, all PASS.
- [ ] `test_mb_review_payload_assembly.bats` ≥4 tests, all PASS.
- [ ] `test_mb_review_auto_finding_red.bats` ≥3 tests, all PASS.
- [ ] `bash scripts/mb-review.sh --emit-payload --input tests/calibration/cases/PY-001` (placeholder case) prints all 5 sections (or 4 when green) and exits 0.
- [ ] `shellcheck` clean on `mb-review.sh`.

**Code rules:** SRP — each new function ≤60 lines and one concern. DIP — `mb-test-runner` invoked via Task abstraction, not a hardcoded command.

---

<!-- mb-stage:5 -->
### Stage 5: Reviewer agent rewrite + wire `/mb work` + pipeline defaults + install.sh

**What to do:**
- Rewrite `agents/mb-reviewer.md` per spec §7:
  - Inputs: single pre-assembled payload with 5 sections
  - Hard rules: no file reads, MUST include `## Auto-generated findings` verbatim as first issue(s), MUST emit `referenced_example_id` when applicable, JSON-only output
  - Output JSON schema: add optional `referenced_example_id` field to each issue
  - Remove existing prompt sections that load rubric or pipeline.yaml — orchestrator owns this now
- Update `commands/work.md` step 3c: invoke `bash scripts/mb-review.sh` instead of dispatching directly to `Task → mb-reviewer`. The orchestrator internally performs the dispatch when needed (or returns the JSON it received).
- Implement post-validation in `mb-review.sh`: if `prior_evidence.tests_pass=false` and the returned reviewer JSON lacks at least one `category=="tests" && severity=="blocker"` issue, prepend the missing auto-finding and rewrite `verdict` to `CHANGES_REQUESTED`. Log a `WARN` to stderr.
- Update `references/pipeline.default.yaml`: add `test_cache_ttl_sec: 600`, `review_examples.max_count: 8`, `review_examples.rotation: hash_run_id` (each with inline comment). Confirm defaults so older `pipeline.yaml` files without these keys still resolve correctly.
- Update `install.sh`: append `.memory-bank/tmp/` to project `.gitignore` (idempotent); copy new `references/rubric-examples/*.md` into installed skill location.

**Testing (TDD):**
- Extend `test_mb_review_auto_finding_red.bats` (or new bats) with a "reviewer drops the finding" simulation: stub reviewer JSON missing the blocker, run orchestrator post-validation, assert it prepends the finding and forces verdict to `CHANGES_REQUESTED` with a `WARN` log.
- Existing bats `tests/bats/test_mb_work_command_doc.bats` re-runs and stays green (no regression in `commands/work.md`).
- Integration: stub a `Task → mb-reviewer` dispatch via env override or harness shim; assert payload arrives with the 5 sections.

**DoD (SMART):**
- [ ] `agents/mb-reviewer.md` rewritten — no rubric/pipeline loading logic remains; JSON schema documents `referenced_example_id`.
- [ ] `commands/work.md` step 3c calls `scripts/mb-review.sh`; the call signature is documented inline.
- [ ] `references/pipeline.default.yaml` carries the 3 new keys with comments and sane defaults.
- [ ] `install.sh` patches `.gitignore` idempotently; running twice produces identical file state.
- [ ] New post-validation bats test PASSes.
- [ ] Existing bats suite (`bats tests/bats/`) PASS with no regression.
- [ ] `/mb verify` on the branch reports no DoD drift against this stage.

**Code rules:** Clean Architecture direction preserved (`commands → scripts → agents`). DIP — `commands/work.md` knows about a script entrypoint, not the agent name.

---

<!-- mb-stage:6 -->
### Stage 6: Golden calibration suite + CI workflow + docs + CHANGELOG

**What to do:**
- Build `tests/calibration/` directory:
  - `tests/calibration/README.md` — how to add a case, how the match metric works, when to run live vs `--emit-payload` mode.
  - `tests/calibration/run.sh` — runner: iterates cases, calls `scripts/mb-review.sh --input <case-dir>` in `--emit-payload` mode by default, in live mode with `--live` flag, compares against `case.json:expected`, writes results to `tests/calibration/results/<timestamp>_run.json` (gitignored), prints PASS/WARN/FAIL table, exits 0/1/2.
  - Author ≥5 cases — one per category. Suggested IDs:
    - `cases/PY-001-srp-violation/` (code_rules)
    - `cases/PY-002-missing-tests/` (tests)
    - `cases/GO-001-error-wrap/` (logic)
    - `cases/TS-001-any-leak/` (code_rules — alternate stack)
    - `cases/BE-001-clean-arch-violation/` (security or scalability — pick one to cover the missing category)
  - Each case directory has: `case.json` (per spec §6 schema), `diff.patch`, `files-touched.txt`, `prior-tests.json`.
- Add `.gitignore` entry for `tests/calibration/results/`.
- Add `.github/workflows/calibration.yml`:
  - Trigger: `workflow_dispatch` (manual) and `schedule: cron: '0 6 * * 1'` (Monday 06:00 UTC).
  - Job: checkout, install bats, run `bash tests/calibration/run.sh` in `--emit-payload` mode (no LLM cost on schedule).
  - Upload `tests/calibration/results/*.json` as artifact.
  - **Non-blocking**: `continue-on-error: true` on the calibration step; no PR gating.
- Author `docs/reviewer-2.0.md` covering:
  - What changed and why (link to article + spec)
  - How layered examples are loaded; how to add a project override
  - How the test cache works and how to force-refresh
  - How to run the calibration suite locally and what PASS/WARN/FAIL mean
  - What `referenced_example_id` is for
- Update `CHANGELOG.md` under `[Unreleased]`:
  - Breaking: `mb-reviewer.md` simplified; agents that wrap it via `pipeline.yaml:roles.reviewer.agent` need to consume pre-assembled payload.
  - Added: layered rubric examples, test-aware reviewer payload, golden calibration suite.
  - Added: optional `test_cache_ttl_sec`, `review_examples.{max_count,rotation}` in `pipeline.yaml`.
  - Added: `referenced_example_id` field in reviewer issue JSON (optional).

**Testing (TDD):**
- Smoke run: `bash tests/calibration/run.sh --emit-payload` exits 0 across all ≥5 cases (no LLM call, only payload-shape check).
- Optional live run (manual, gated by `MB_CALIBRATION_LIVE=1`): dispatches the real reviewer; expect PASS ≥4/5, no FAIL, WARNs allowed.
- New bats: `tests/bats/test_calibration_run_smoke.bats` — runs `tests/calibration/run.sh --emit-payload` over a fixture case, asserts exit 0 and result JSON shape.

**DoD (SMART):**
- [ ] `tests/calibration/run.sh` exists, executable, `shellcheck` clean.
- [ ] `tests/calibration/README.md` covers spec §6 surfaces.
- [ ] ≥5 cases live under `tests/calibration/cases/`, one per category covered.
- [ ] `tests/calibration/run.sh --emit-payload` exits 0 on all cases (smoke).
- [ ] `.github/workflows/calibration.yml` exists, validates via `gh workflow view` or YAML lint.
- [ ] `.gitignore` updated with `tests/calibration/results/`.
- [ ] `docs/reviewer-2.0.md` exists, ≥100 lines, all spec §10 risks addressed at least once.
- [ ] `CHANGELOG.md` `[Unreleased]` entry enumerates all breaking + added items.
- [ ] `bats tests/bats/test_calibration_run_smoke.bats` PASS.

**Code rules:** Tests-first for `run.sh` helpers. KISS — runner is bash; no Python unless a helper exceeds ~50 lines bash with structural complexity.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Reviewer paraphrases or drops auto-injected `MUST INCLUDE` block | M | Post-validation in `mb-review.sh` (Stage 5) detects the omission and rewrites verdict; covered by bats test. |
| Layered resolver behaves surprisingly on collision | M | `test_mb_review_examples_loader.bats` codifies precedence; documented in `docs/reviewer-2.0.md`. |
| `pipeline.yaml` parsing differs between projects that ship `yq` vs not | L | Implement awk-based fallback in Stage 4; covered by bats running both code paths. |
| Stale test cache surface (e.g., dependency change without touched-file change) | L | TTL bounds staleness to 600s; `--refresh-tests` is the manual escape hatch; documented. |
| Sprint hits the ≤15-files Sprint sanity limit | M | Rubric examples and calibration fixtures are content/data, not behavioral source. The behavioral surface is ~12 files; data is batched into stages 2/3/6. |
| Bash grows past 300 lines in `mb-review.sh` | M | If exceeded in Stage 4, extract helpers into a separate `scripts/mb_review_helpers.py` (pytest-tested); declared as fallback in spec §10. |
| LLM non-determinism makes calibration suite flaky if CI-blocking | M | `.github/workflows/calibration.yml` is non-blocking by design (Stage 6 DoD); weekly cron uses `--emit-payload` mode (no LLM call). |
| `install.sh` `.gitignore` patch corrupts existing entries | L | Use idempotent append-if-missing pattern; bats test asserts double-run produces identical state (Stage 5 DoD). |

## Gate (plan success criterion)

`/mb work 2026-05-23_feature_reviewer-v2 --max-cycles 3 --auto` runs to completion across all 6 stages with `plan-verifier` PASS on each stage, **and**:

1. `bash tests/calibration/run.sh --emit-payload` exits 0 on ≥5 cases (smoke).
2. `bats tests/bats/test_mb_review_*.bats tests/bats/test_calibration_run_smoke.bats` PASS with 0 failures.
3. Existing bats suite (`bats tests/bats/`) shows no regressions.
4. `shellcheck scripts/mb-review.sh scripts/mb-review-cache.sh tests/calibration/run.sh` clean.
5. `mb-rules-check.sh` reports 0 violations on changed files.
6. `docs/reviewer-2.0.md` and `CHANGELOG.md` updated.
7. Manual smoke: a real `/mb work` cycle on a tiny diff dispatches through the new orchestrator and produces a valid JSON verdict (one live observation is enough; full calibration suite live-mode is optional).
