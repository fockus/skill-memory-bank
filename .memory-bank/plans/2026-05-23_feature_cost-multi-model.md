---
type: feature
topic: cost-multi-model
status: queued
depends_on: ["2026-05-23_feature_reviewer-v2.md", "2026-05-23_feature_work-loop-v2.md"]
parallel_safe: false
linked_specs: ["specs/cost-multi-model/design.md"]
sprint: 1
phase_of: harness-upgrade
created: 2026-05-23
baseline_commit: bf4fceea6065bdf84fac9f2a18c3b4c346d88dd1
---

# Plan: feature — Cost (multi-model role assignment, S4 of harness-upgrade)

**Baseline commit:** bf4fceea6065bdf84fac9f2a18c3b4c346d88dd1
**Linked spec:** [.memory-bank/specs/cost-multi-model/design.md](../specs/cost-multi-model/design.md)
**Sprint type:** single Sprint, 4 stages. Hard-depends on S1 (calibrated reviewer) + S2 (stable loop) before downshifting model tiers.

## Context

**Problem.** All roles currently dispatch through a single default model. Evaluator roles (reviewer / rules-enforcer / test-runner) carry premium compute they don't need, while architect-class work and final gates would benefit from more capability. There's also no central place to track the model frontier as Anthropic ships newer versions.

**Expected result.** A small resolver (`scripts/mb-model-resolve.sh`) returns a model ID per role-key. Sensible defaults in `references/pipeline.default.yaml` apply out of the box: fast for evaluators/utilities, balanced for generators/gates, powerful for architect. An aliases file (`references/model-aliases.yaml`) decouples role defaults from concrete model IDs, so frontier shifts are a one-file change.

**Related files:**
- Spec: `.memory-bank/specs/cost-multi-model/design.md`
- Depends on S1 (calibrated reviewer): `scripts/mb-review.sh`, `agents/mb-reviewer.md`
- Depends on S2 (stable loop): `commands/work.md` dispatch sites finalised
- Existing reviewer resolver: `scripts/mb-reviewer-resolve.sh`
- Default pipeline: `references/pipeline.default.yaml`
- All role-agent files: `agents/*.md`

**Sprint boundaries.** Source files in scope: ~5 scripts/configs + ~16 agent frontmatter touches. Bats tests new: ~10.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Aliases table + resolver script

**What to do:**
- Create `references/model-aliases.yaml`:
  ```yaml
  schema_version: 1
  aliases:
    fast:     claude-haiku-4-5-20251001
    balanced: claude-sonnet-4-6
    powerful: claude-opus-4-7
  ```
- Create `scripts/mb-model-resolve.sh <role-key>`:
  - Resolution precedence: `.memory-bank/pipeline.yaml:roles.<role>.model` → `references/pipeline.default.yaml:roles.<role>.model` → `agents/<role>.md` frontmatter `model_class` → fallback `balanced`.
  - At each step, alias values resolved via `model-aliases.yaml`; verbatim model IDs passed through.
  - awk-first parsing (yq optional); existing skill scripts use this pattern (`mb-reviewer-resolve.sh`).
  - Exit codes: 0 success, 1 unknown role, 2 alias resolution failure.

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_mb_model_resolve.bats` ≥8 cases:
  - alias `fast` → expected haiku id
  - verbatim model ID passed through
  - project pipeline override wins over defaults
  - missing project file → falls back to defaults
  - missing role in pipeline → falls back to agent frontmatter `model_class`
  - missing everywhere → returns `balanced` resolved id
  - unknown role-key → exit 1
  - aliases file missing required entry → exit 2

**DoD (SMART):**
- [ ] `references/model-aliases.yaml` exists with the §5-spec mapping.
- [ ] `scripts/mb-model-resolve.sh` exists, executable, `shellcheck` clean.
- [ ] `test_mb_model_resolve.bats` PASS (≥8 cases).
- [ ] `mb-rules-check.sh` clean on new files.

**Code rules:** SRP — resolver does ONE job. KISS — single bash file ≤150 lines.

---

<!-- mb-stage:2 -->
### Stage 2: Default model matrix in pipeline.yaml + agent frontmatter

**What to do:**
- Update `references/pipeline.default.yaml`: add `roles.<role>.model` for every role from spec §4 default matrix. Use aliases (`fast` / `balanced` / `powerful`), not verbatim IDs.
- Update every agent file in `agents/`: add `model_class: <fast|balanced|powerful>` to frontmatter consistent with §4. Roles to touch: `mb-developer`, `mb-backend`, `mb-frontend`, `mb-ios`, `mb-android`, `mb-devops`, `mb-qa`, `mb-analyst`, `mb-architect`, `mb-reviewer`, `mb-test-runner`, `mb-rules-enforcer`, `plan-verifier`, `mb-codebase-mapper`, `mb-doctor`, `mb-manager`.

**Testing (TDD):**
- `tests/bats/test_pipeline_default_models.bats` ≥3 cases:
  - every role in §4 matrix has an entry in `pipeline.default.yaml`;
  - every alias used in the matrix exists in `model-aliases.yaml`;
  - every agent file has `model_class` matching the matrix.
- `tests/pytest/test_agent_frontmatter_model_class.py` ≥1 case enumerating agents and asserting the field exists with a valid alias name.

**DoD (SMART):**
- [ ] `references/pipeline.default.yaml` carries the full default matrix.
- [ ] All 16 agent files have `model_class` frontmatter consistent with §4.
- [ ] Both test files PASS.

**Code rules:** DRY — agent frontmatter mirrors the defaults exactly; if the two disagree, defaults win at runtime (verified in stage 1 bats).

---

<!-- mb-stage:3 -->
### Stage 3: Wire dispatch sites in commands/* + reviewer-resolve augmentation

**What to do:**
- Update `commands/work.md`:
  - At every `Task(subagent_type=<role>, ...)` dispatch site (steps 3a contract, 3b implement, 3c review, 3e refine/pivot, 3f verify), prepend a resolver call: `MODEL=$(bash scripts/mb-model-resolve.sh <role-key>)` and pass `model="$MODEL"` to `Task`.
  - Document the change inline.
- Same for `commands/done.md`, `commands/verify.md`, `commands/review.md` wherever a Task dispatch exists.
- Augment `scripts/mb-reviewer-resolve.sh`: in addition to emitting the agent name, also emit the resolved model on a second line (or as JSON). The orchestrator (`mb-review.sh` from S1) reads both. Maintain backward compat: existing callers reading only the first line continue to work.
- Update `scripts/mb-review.sh` (from S1) to consume the model and pass it via `Task(model=...)`.
- `install.sh`: distribute `references/model-aliases.yaml` to the installed skill location.

**Testing (TDD):**
- `tests/bats/test_commands_dispatch_with_model.bats` ≥3 cases: parsing of each `commands/<cmd>.md` confirms presence of model-resolve incantation at dispatch sites; stub dispatch verifies model arg arrives.
- `tests/bats/test_mb_reviewer_resolve_model.bats` ≥2 cases: emits agent name on line 1 and model on line 2; backward-compat read of line 1 only.

**DoD (SMART):**
- [ ] `commands/{work,done,verify,review}.md` all updated with resolver calls at dispatch sites.
- [ ] `scripts/mb-reviewer-resolve.sh` augmented; backward-compat preserved.
- [ ] `scripts/mb-review.sh` (S1) consumes the model.
- [ ] `install.sh` distributes the aliases file.
- [ ] Both bats files PASS.
- [ ] Existing bats around dispatch (e.g., `test_mb_work_command_doc.bats`) PASS with 0 regressions.

**Code rules:** DIP — commands depend on the resolver abstraction, not on model IDs directly. Backward compat is a feature, not a workaround.

---

<!-- mb-stage:4 -->
### Stage 4: Docs + CHANGELOG + calibration validation

**What to do:**
- Author `docs/cost-multi-model.md`:
  - Default matrix from §4 (printed verbatim).
  - How to override per project (project pipeline.yaml example).
  - How aliases work and how to override them per project.
  - Frontier-shift workflow: bump aliases file in skill release; projects benefit automatically.
- Update `CHANGELOG.md` `[Unreleased]`:
  - Added: per-role model assignment.
  - Added: `references/model-aliases.yaml` (skill-level) and `.memory-bank/model-aliases.yaml` (project override path).
  - Added: `agents/*.md` frontmatter `model_class`.
  - Added: default matrix in `pipeline.default.yaml`.
- **Calibration validation step**: re-run `bash tests/calibration/run.sh` (from S1) with the new default (reviewer at `fast`). Compare results against baseline (reviewer at `balanced`). PASS criterion: same or better PASS count on the calibration suite. If degradation observed, downgrade the reviewer default to `balanced` for now and document in CHANGELOG + spec §11 follow-up.

**Testing (TDD):**
- `tests/bats/test_calibration_with_fast_reviewer.bats` ≥1 case: end-to-end calibration smoke (`--emit-payload` mode) confirms the orchestrator now passes `model="fast"` (resolved id) to mb-reviewer.

**DoD (SMART):**
- [ ] `docs/cost-multi-model.md` exists, ≥120 lines.
- [ ] `CHANGELOG.md` enumerates all S4 changes.
- [ ] Calibration suite re-run with `fast` reviewer; PASS count not worse than baseline; results recorded in `tests/calibration/results/`.
- [ ] If calibration degraded → reviewer default downgraded to `balanced` AND documented in CHANGELOG + spec follow-up.
- [ ] New bats file PASS.
- [ ] `/mb verify` clean on branch.

**Code rules:** Empirical validation — defaults are tuned to actual measured behaviour, not assumption.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| `fast` reviewer misclassifies subtle issues that calibrated rubric was tuned at `balanced` | M | Stage 4 calibration validation; downgrade reviewer to `balanced` if regression observed. |
| Aliases file drift between skill releases and installed projects | M | `install.sh` always overwrites `references/model-aliases.yaml`; project override is separate; documented. |
| Frontmatter `model_class` contradicts defaults matrix | L | Resolver precedence makes defaults win; bats covers the case. |
| Task tool rejects unknown model IDs after frontier shift | M | Resolver doesn't validate; Task error is the canonical surface; document trouble-shooting in `docs/cost-multi-model.md`. |
| Stack-specific role-agents need different defaults per stack | L | Out-of-scope follow-up; spec §11 documents. |
| Backward compat break in `mb-reviewer-resolve.sh` consumers | M | Stage 3 explicit backward-compat (line 1 unchanged); bats test confirms. |

## Gate (plan success criterion)

`/mb work 2026-05-23_feature_cost-multi-model --max-cycles 3 --auto` completes all 4 stages with `plan-verifier` PASS, **and**:

1. All new bats + pytest files PASS with 0 failures.
2. Existing bats + pytest suites have 0 regressions.
3. `shellcheck` clean on `scripts/mb-model-resolve.sh` and augmented resolver.
4. `mb-rules-check.sh` clean.
5. `docs/cost-multi-model.md` + `CHANGELOG.md` updated.
6. Calibration suite re-run with new default reviewer model passes at parity or better; result recorded in `tests/calibration/results/`.
7. Manual smoke: one full `/mb work` cycle on a tiny stage dispatches to `mb-reviewer` with `model=claude-haiku-4-5-20251001` (or whichever the fast alias resolves to), `mb-developer` with the balanced model, and `mb-architect` (if invoked via pivot) with the powerful model. Verified via dispatch logs.
