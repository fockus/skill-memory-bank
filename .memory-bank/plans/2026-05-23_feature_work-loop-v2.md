---
type: feature
topic: work-loop-v2
status: planned
depends_on: ["2026-05-23_feature_reviewer-v2.md"]
parallel_safe: false
linked_specs: []
sprint: 1
phase_of: harness-upgrade
created: 2026-05-23
baseline_commit: bf4fceea6065bdf84fac9f2a18c3b4c346d88dd1
---

# Plan: feature — Work loop 2.0 (S2 of harness-upgrade)

**Baseline commit:** bf4fceea6065bdf84fac9f2a18c3b4c346d88dd1
**Linked spec:** [.memory-bank/specs/work-loop-v2/design.md](../specs/work-loop-v2/design.md)
**Sprint type:** single Sprint, 5 stages. Hard-depends on S1 (`reviewer-v2`) for trend signal reliability.

## Context

**Problem.** The current implement→review→fix loop has three weak points: (a) the generator can silently expand scope between plan and implementation (no contract artifact); (b) when scores stagnate, the loop keeps retrying the same approach until `max_cycles` exhausts; (c) the `on_max_cycles` default is `continue_with_warning`, so even after exhausting retries the loop quietly merges work that didn't pass review.

**Expected result.** A sprint contract becomes an explicit (opt-in) artifact reviewed before implementation. The reviewer emits `progress_trend` and the orchestrator pivots when stagnant. The fail-fast default flips to `stop_for_human` — projects that prefer the old behavior set it explicitly.

**Related files:**
- Spec: `.memory-bank/specs/work-loop-v2/design.md`
- Depends on S1 orchestrator: `scripts/mb-review.sh` (must already emit `progress_trend`)
- Existing review-loop entry: `commands/work.md` step 3
- Existing severity gate (untouched): `scripts/mb-work-severity-gate.sh`
- Default pipeline: `references/pipeline.default.yaml`

**Sprint boundaries.** Source files in scope: ~10. Bats tests new: ~14.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Trend calculator + previous-verdict cache

**What to do:**
- Create `scripts/mb-work-trend.sh` with API: `compute_trend <current.json> <previous.json>` → emits `improving | stagnant | regressing | null` on stdout. Weighted score formula per spec §5.
- Add `.memory-bank/tmp/last-verdict-<item-sha>.json` write to `scripts/mb-review.sh` (extend the S1 orchestrator's verdict emit step). Item-sha = sha256 of `(plan_path||stage_no||item_no)`.
- Extend reviewer payload schema to include `progress_trend` in the top-level JSON (the calculator runs server-side before the reviewer is dispatched; the reviewer is just informed).

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_mb_work_trend.bats` ≥5 cases: improving, stagnant (within ±1), regressing, first cycle (null), tied at zero (improving once neutralised).

**DoD (SMART):**
- [ ] `scripts/mb-work-trend.sh` exists, executable, `shellcheck` clean.
- [ ] `scripts/mb-review.sh` writes `last-verdict-<item-sha>.json` on every emission.
- [ ] Reviewer JSON output includes top-level `progress_trend`.
- [ ] `test_mb_work_trend.bats` PASS (≥5 cases).
- [ ] `mb-rules-check.sh` clean on new/changed files.

**Code rules:** SRP — trend calculator does ONE thing; cache write isolated to the orchestrator.

---

<!-- mb-stage:2 -->
### Stage 2: Contract phase script + reviewer contract-mode rubric

**What to do:**
- Create `scripts/mb-work-contract.sh` with subcommands: `draft <plan-path> <stage-N>` (dispatches the resolved role-agent to write the contract markdown), `review <contract-path>` (dispatches `mb-reviewer` in `review_mode: contract`).
- Create `templates/contract.md` matching spec §4 structure.
- Augment `agents/mb-reviewer.md`: document `review_mode` toggle in the payload preamble. Contract-mode rubric: `scope`, `dod`, `test_plan`, `out_of_scope` categories. Severity scale unchanged.
- Extend `scripts/mb-review.sh` (S1 orchestrator) to recognise `--mode contract` and route to a different payload assembler (no examples loader, no test cache — contract review is pure scope/dod/test-plan evaluation).

**Testing (TDD):**
- `tests/bats/test_mb_work_contract.bats` ≥4 cases: contract file written with all 5 sections; contract-mode review returns APPROVED on a complete contract; CHANGES_REQUESTED on a contract missing the `Out of scope` section; archive of superseded contract created on revision.
- Contract templates `templates/contract.md` validated against §4 format.

**DoD (SMART):**
- [ ] `scripts/mb-work-contract.sh draft|review|archive` all functional; `shellcheck` clean.
- [ ] `templates/contract.md` exists and matches spec §4.
- [ ] `agents/mb-reviewer.md` documents `review_mode: contract`.
- [ ] `mb-review.sh --mode contract` routes correctly.
- [ ] `test_mb_work_contract.bats` PASS (≥4 cases).

**Code rules:** ISP — `mb-work-contract.sh` exposes 3 subcommands max. DIP — contract storage abstracted from the agent, written by the script.

---

<!-- mb-stage:3 -->
### Stage 3: Pivot dispatch — `pivot_in_role` + `pivot_via_architect`

**What to do:**
- In `commands/work.md` step 3d, add the pivot decision tree (per spec §5). Logic: read `progress_trend` from current verdict, increment `consecutive_stagnant` if stagnant, reset on improving/regressing. When `consecutive_stagnant >= pivot_after_cycles`, set `pivot_mode` accordingly.
- New helper `scripts/mb-work-pivot.sh`:
  - `pivot-in-role <role> <issue-list>` → returns a prompt prefix instructing the agent to discard the current approach.
  - `pivot-via-architect <issue-list>` → dispatches `mb-architect` first, writes a note `.memory-bank/notes/<date>_pivot-<topic>.md`, then returns a prompt prefix combining issues + architect sketch path.
- Append per-pivot telemetry to `.memory-bank/tmp/pivot-log.jsonl`.

**Testing (TDD):**
- `tests/bats/test_mb_work_pivot.bats` ≥3 cases: 2 consecutive stagnant → `pivot_in_role` prompt assembled; cycle 4 stagnant → `pivot_via_architect` triggered, architect note created; improving trend in middle resets the counter.

**DoD (SMART):**
- [ ] `scripts/mb-work-pivot.sh` exists, executable, `shellcheck` clean.
- [ ] `commands/work.md` step 3d documents the decision tree with pseudo-code or table.
- [ ] Pivot prompts contain explicit "discard current approach" language (spec §5).
- [ ] `pivot-log.jsonl` written on every pivot.
- [ ] `test_mb_work_pivot.bats` PASS (≥3 cases).

**Code rules:** SOLID — pivot helper is a pure function from `(role, issue-list)` to prompt prefix. Clean Architecture — `commands/work.md` orchestrates, `mb-work-pivot.sh` mechanizes.

---

<!-- mb-stage:4 -->
### Stage 4: `on_max_cycles` default flip + new pipeline keys

**What to do:**
- Change `references/pipeline.default.yaml`:
  - `on_max_cycles: stop_for_human` (was `continue_with_warning`).
  - Add `require_contract: false`.
  - Add `pivot_after_cycles: 2`.
  - Add `pivot_escalate_to_architect_on: 4`.
- Ensure `commands/work.md` reads these via existing helper (`mb-pipeline-resolve.sh` or similar — whichever the project uses). The resolver must fall back to the new default when the key is absent (this is the behavioral flip).
- `install.sh` does NOT rewrite existing `pipeline.yaml` files. Documentation in CHANGELOG (stage 5) is the migration path.

**Testing (TDD):**
- `tests/bats/test_pipeline_default_max_cycles.bats` ≥2 cases: absent key → resolves to `stop_for_human`; explicit `continue_with_warning` honored.
- `tests/bats/test_pipeline_default_pivot_keys.bats` ≥3 cases: absent `pivot_after_cycles` → resolves to 2; absent `pivot_escalate_to_architect_on` → resolves to 4; absent `require_contract` → resolves to false.

**DoD (SMART):**
- [ ] `references/pipeline.default.yaml` updated as above.
- [ ] Both bats files PASS.
- [ ] No regression in existing pipeline-related tests (`bats tests/bats/test_pipeline*.bats`).

**Code rules:** KISS — single line change in defaults + new keys with sane defaults.

---

<!-- mb-stage:5 -->
### Stage 5: Wire into `/mb work` + docs + CHANGELOG

**What to do:**
- Update `commands/work.md`:
  - Add explicit step 3a (Contract phase) gated by `--contract` flag or `pipeline.yaml:require_contract: true`.
  - Step 3d updated with full decision tree (refine vs pivot_in_role vs pivot_via_architect vs stop_for_human).
  - Document `--contract` and `--pivot-after N` CLI flags inline.
- Author `docs/work-loop-2.0.md`:
  - Contract lifecycle (draft → review → approved → implement).
  - Trend signal and pivot semantics with worked example.
  - Fail-fast migration note (one-line restore).
  - Telemetry pointer (`pivot-log.jsonl`).
- Update `CHANGELOG.md` `[Unreleased]`:
  - Breaking: `on_max_cycles` default flipped to `stop_for_human`.
  - Added: contract phase + `--contract` flag + `require_contract` key.
  - Added: pivot logic + `pivot_after_cycles`/`pivot_escalate_to_architect_on` keys.
  - Added: `progress_trend` field in reviewer JSON.

**Testing (TDD):**
- Existing `tests/bats/test_mb_work_command_doc.bats` re-runs; extend to assert presence of new flag documentation.
- Integration: full happy-path bats `tests/bats/test_mb_work_with_contract_e2e.bats` ≥2 cases (stub Task dispatches): contract → implement → review → done; reaffirms no regression on the no-contract path.

**DoD (SMART):**
- [ ] `commands/work.md` documents step 3a and updated step 3d.
- [ ] `docs/work-loop-2.0.md` exists, ≥120 lines.
- [ ] `CHANGELOG.md` enumerates all S2 changes.
- [ ] All new bats files PASS.
- [ ] Existing bats suite PASS.
- [ ] `/mb verify` clean on branch.

**Code rules:** Clean Architecture preserved — commands orchestrate, scripts mechanize, agents judge.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Contract phase doubles cost on simple items | M | Opt-in by default; per-stage skip marker `<!-- mb-stage:N skip-contract -->` documented in `docs/work-loop-2.0.md`. |
| Pivot prompt confuses model into reverting valid prior work | M | Spec §5 explicit language; bats assertion that prompt contains "Pivot rationale:" instruction. Calibrated reviewer (S1) reduces false-positive pivots. |
| Fail-fast default surprises long-time users on next pull | M | CHANGELOG warning; one-line restore documented. |
| pivot-log.jsonl grows unbounded | L | Cleaned by `mb-compact.sh` (existing low-importance rotation policy); doc note. |
| Trend cache collisions when two `/mb work` runs target different items in parallel | L | Item-sha derived from `(plan||stage||item)` triplet → effectively unique. |
| pipeline.yaml resolution breaks on edge yaml (e.g., comments at top) | L | yq + awk fallback already in use by other resolver scripts; cover edge cases in bats. |

## Gate (plan success criterion)

`/mb work 2026-05-23_feature_work-loop-v2 --max-cycles 3 --auto` completes all 5 stages with `plan-verifier` PASS, **and**:

1. All new bats files PASS with 0 failures.
2. Existing bats suite has 0 regressions.
3. `shellcheck` clean on all new scripts.
4. `mb-rules-check.sh` clean.
5. `docs/work-loop-2.0.md` + `CHANGELOG.md` updated.
6. Manual smoke: a synthetic stage with `--contract` runs through contract draft → review APPROVED → implement → review → done.
7. Manual smoke: a synthetic stage with intentionally hard-to-fix issue triggers `pivot_in_role` after 2 stagnant cycles (verified via stderr log).
