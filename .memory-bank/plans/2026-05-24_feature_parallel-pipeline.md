---
type: feature
topic: parallel-pipeline
status: planned
depends_on: ["2026-05-23_feature_reviewer-v2.md", "2026-05-23_feature_work-loop-v2.md"]
soft_depends_on: ["2026-05-23_feature_handoff-v2.md", "2026-05-23_feature_cost-multi-model.md"]
parallel_safe: false
linked_specs: []
sprint: 1
phase_of: harness-upgrade
created: 2026-05-24
baseline_commit: 6fc6a504a6dfdb3ead9f98e0be569098fe6235a7
---

# Plan: feature — Parallel pipeline (S5 of harness-upgrade)

**Baseline commit:** 6fc6a504a6dfdb3ead9f98e0be569098fe6235a7
**Linked spec:** [.memory-bank/specs/parallel-pipeline/design.md](../specs/parallel-pipeline/design.md)
**Sprint type:** single Sprint, 6 stages. Hard-depends on S1 (reviewer-v2) + S2 (work-loop-v2). Soft-depends on S3 (handoff-v2) + S4 (cost-multi-model).

## Context

**Problem.** `/mb work` runs everything sequentially in the main agent (или с минимальной делегацией). Long plans take wall-clock hours even when items are independent. The skill has no configurable pipeline — fixed implement→review→fix→verify, no way to add test/security/architect-review phases declaratively. No worktree isolation when running multiple plans in parallel.

**Expected result.** Two operating modes side-by-side: existing `/mb work` (economic, sequential — unchanged) and new `/mb run` (parallel, wave-based, pipeline-driven). Pipeline configurable via `pipeline.yaml`. Worktree-per-plan. Cross-agent dispatch via adapter layer (Claude Code native parallel, Pi native parallel, Codex/OpenCode sequential fallback).

**Related files:**
- Spec: `.memory-bank/specs/parallel-pipeline/design.md`
- Hard deps: `scripts/mb-review.sh` (S1), `progress_trend` field in reviewer JSON (S2), `pivot_via_architect` mechanics (S2).
- Soft deps: `scripts/mb-done-gates.sh` (S3), `scripts/mb-model-resolve.sh` (S4).
- Existing primitives (reused as-is): `mb-work-severity-gate.sh`, `mb-work-budget.sh`, `mb-work-protected-check.sh`.
- Existing command (untouched): `commands/work.md`.

**Sprint boundaries.** Source files in scope: ~13 (1 command + 6 scripts + 4 adapters + 2 modifications). Bats: ~9. Pytest: ~4. The new yaml section is sizeable but data, not code.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Pipeline schema + Python planner + DAG validation

**What to do:**
- Add `pipeline:` top-level section to `references/pipeline.default.yaml` per spec §4 with 3 presets (`fast` / `standard` / `strict`) and `execution` block.
- Create `scripts/mb_pipeline_plan.py`:
  - Argparse: `--plans <p1> [<p2>...] --preset <name> --out <path>`
  - Parse `pipeline.yaml` (project + skill defaults, layered merge)
  - Parse each plan/spec, extract items via existing `mb_work_items.py`
  - Validate DAG: phase name uniqueness, `on_failure.to` references real phases, cycles require `max_loops` on every edge
  - Resolve `baseline_commit` from plan frontmatter (fallback `HEAD~1`)
  - Emit `exec_graph.json` per spec §6 schema
- Resolve `merge_order` from plan `depends_on` frontmatter (topological sort).

**Testing (TDD — tests BEFORE implementation):**
- `tests/pytest/test_pipeline_plan_schema_validation.py` ≥6 cases: missing field → exit ≠ 0; cycle without max_loops → reject; unknown role → reject; valid yaml → exit 0; preset not found → reject; layered merge correct.
- `tests/pytest/test_pipeline_plan_preset_resolution.py` ≥4 cases: full preset replace; partial phase override; project pipeline.yaml wins; preset = fast minimal works.
- `tests/pytest/test_pipeline_plan_emit_exec_graph.py` ≥3 cases: exec_graph.json shape matches schema_version=1; dispatches list correct cardinality; baseline_commit resolves; missing → HEAD~1.
- `tests/pytest/test_pipeline_plan_merge_order.py` ≥2 cases: 2-plan dependency → correct order; cycle in plan deps → reject.

**DoD (SMART):**
- [ ] `references/pipeline.default.yaml` carries new `pipeline:` block with 3 presets.
- [ ] `scripts/mb_pipeline_plan.py` exists, executable; ruff + mypy clean.
- [ ] All 4 pytest files PASS (≥15 tests total).
- [ ] `python scripts/mb_pipeline_plan.py --plans <fixture> --preset standard --out /tmp/g.json` produces valid JSON parseable by `jq`.
- [ ] `mb-rules-check.sh` clean on new files.

**Code rules:** SOLID — planner is a pure function. DRY — reuse `mb_work_items.py`. KISS — bash-shaped data shapes (no nested dataclass).

---

<!-- mb-stage:2 -->
### Stage 2: Bash executor + worktree lifecycle + state cache

**What to do:**
- Create `scripts/mb-pipeline-run.sh`:
  - Args: `--graph <path>`, `--dry-run`, `--continue-on-failed-plan`, `--restart`
  - For each plan in `plans[]`:
    - Resume from state cache if `state-<plan>.json` exists and not `--restart`
    - `git worktree add .git/mb-worktrees/<plan-topic> <baseline_commit>`
    - Symlink `.memory-bank` into worktree (read-write linking)
    - Iterate phases, emit `wave-<plan>-<phase>-dispatches.json` per spec §10
    - Block on `wait_for_artifacts` (loop on file presence with timeout)
    - Evaluate gate / on_failure (logic from §8)
    - On phase pass: save state to `state-<plan>.json`
  - On all phases done: squash commits and exit ready-to-merge state
- Create `scripts/mb-pipeline-state.sh`:
  - Read/write `state-<plan>.json` { last_phase, loop_counters, cycle, started_at }
- Create `scripts/mb-pipeline-merge.sh`:
  - For each plan in `merge_order`: `git cherry-pick` squashed commit
  - On conflict: `git cherry-pick --abort`, halt, preserve worktrees, structured stderr
  - On success: `git worktree remove`
- Create `scripts/mb-work-budget-wave.sh`:
  - Wraps existing `mb-work-budget.sh check`
  - Adds per-wave reserve check (reserve = `wave_estimate × 1.3`, where wave_estimate = sum of `avg_tokens_per_dispatch` from agent frontmatter, default 8000)

**Testing (TDD):**
- `tests/bats/test_mb_pipeline_run_single_plan.bats` ≥4 cases: worktree created + symlink + waves dispatched (mocked) + squash → cherry-pick → cleanup; gate FAIL → halt + worktree preserved.
- `tests/bats/test_mb_pipeline_cherry_pick_conflict.bats` ≥2 cases: conflict → abort + halt; structured stderr.
- `tests/bats/test_mb_pipeline_budget_reserve.bats` ≥3 cases: insufficient budget → wave halts before launch; global hard stop halts mid-run; wave reserve includes all dispatches.
- `tests/bats/test_mb_pipeline_resume_after_halt.bats` ≥3 cases: resume from cached state; `--restart` invalidates state; corrupted state → re-init with WARN.

**DoD (SMART):**
- [ ] All 4 new bash scripts exist; shellcheck clean.
- [ ] All 4 bats files PASS (≥12 tests total).
- [ ] Worktree create + symlink + remove works end-to-end on test fixture.
- [ ] Cherry-pick conflict produces structured error to stderr.
- [ ] State cache lifecycle covered.

**Code rules:** SRP — each script does ONE job (executor / merge / state / budget). Clean Architecture — executor depends on existing primitives, not the other way around.

---

<!-- mb-stage:3 -->
### Stage 3: Wave control flow + gates + loops + pivot_on_stagnant

**What to do:**
- In `mb-pipeline-run.sh`, implement:
  - `evaluate_phase_gate` — reads phase result JSONs, runs `mb-work-severity-gate.sh`, classifies as PASS/FAIL.
  - `evaluate_on_failure` — switch on kind:
    - `retry` — re-emit dispatches; counter `retry_<phase>`.
    - `loop_back` — set next_phase = on_failure.to; counter `<phase>_to_<target>_loops`.
    - `halt` — exit 2 with structured error.
    - `escalate` — dispatch escalation role, then continue with original next_phase.
    - `pivot_on_stagnant` — read `progress_trend` from latest reviewer artifact (requires S2). If `stagnant` for `stagnant_threshold` consecutive cycles, invoke `mb-architect` (writes pivot note), then re-emit implement dispatches. Otherwise fallback to `retry`.
  - `evaluate_gate_on_entry` — if phase has `gate_on_entry` and signal not present, mark skipped.
- Phase result aggregation: per-dispatch artifacts → wave-level result with `pass | fail` flag.

**Testing (TDD):**
- `tests/bats/test_mb_pipeline_loops.bats` ≥4 cases: loop_back increments counter; max_loops reached → halt; counters scoped per (source, target); improving trend resets counter.
- `tests/bats/test_mb_pipeline_gate_on_entry.bats` ≥2 cases: signal present → phase runs; signal absent → phase skipped (no dispatches).
- `tests/bats/test_mb_pipeline_pivot_on_stagnant.bats` ≥3 cases: 2 stagnant cycles → pivot_via_architect dispatched; improving trend → retry instead; trend null (first cycle) → retry.

**DoD (SMART):**
- [ ] `evaluate_phase_gate`, `evaluate_on_failure`, `evaluate_gate_on_entry` implemented and shellcheck-clean.
- [ ] All 3 bats files PASS (≥9 tests).
- [ ] `pivot_on_stagnant` reads `progress_trend` from artifact path; verified via stub artifact in bats.

**Code rules:** Fail-fast on missing context (e.g., `progress_trend` field absent → log + treat as null + WARN to stderr).

---

<!-- mb-stage:4 -->
### Stage 4: Cross-agent dispatch — adapter layer

**What to do:**
- Create `adapters/claude-code/dispatch.md` documenting the protocol: executor writes `dispatches.json`, control returns to main agent (`commands/run.md` step), main agent reads JSON and issues N `Task()` calls in a single response.
- Create `adapters/pi/dispatch.ts` — TypeScript adapter for Pi:
  - Reads `dispatches.json` from path passed via argv.
  - For each dispatch, spawns Pi native subagent in parallel (Pi API).
  - Awaits all, writes `result-<dispatch_id>.json` per spec.
  - Existing `adapters/pi_graph_rag_extension.ts` is the integration pattern reference.
- Create `adapters/codex/dispatch.sh` — bash sequential CLI loop:
  - For each dispatch in `dispatches[]`: `codex run` with assembled prompt, capture to `result-<id>.json`.
  - stderr WARN: "Codex does not natively support parallel subagents — running sequentially. Wall-clock time will be ~N× longer."
- Create `adapters/opencode/dispatch.sh` — analogous to codex.
- In `mb-pipeline-run.sh`, route `hand_off_to_adapter` based on `execution.active_adapter` from yaml:
  - `claude-code` → emit dispatches.json + return; main agent picks it up.
  - `pi` → exec `adapters/pi/dispatch.ts` with dispatches.json path; wait for completion.
  - `codex` / `opencode` → exec corresponding sh script.

**Testing (TDD):**
- `tests/bats/test_mb_pipeline_dispatch_specs_format.bats` ≥3 cases: dispatches.json shape matches contract; expected_artifact paths valid; max_concurrent respected.
- `tests/bats/test_mb_pipeline_adapter_routing.bats` ≥4 cases (with stubbed adapters): claude-code returns to main agent (no exec); pi adapter invoked; codex sequential loop runs; unknown adapter → exit ≠ 0.
- `tests/pytest/test_pi_dispatch_unit.py` ≥2 cases for TypeScript dispatch logic — actually skip if Node not in CI; mark as manual-only.

**DoD (SMART):**
- [ ] `adapters/{claude-code/dispatch.md, pi/dispatch.ts, codex/dispatch.sh, opencode/dispatch.sh}` exist.
- [ ] `mb-pipeline-run.sh` routes correctly based on `execution.active_adapter`.
- [ ] Both bats files PASS (≥7 tests).
- [ ] Manual smoke for Pi adapter — invoke on a fixture dispatches.json, verify parallel execution.
- [ ] Codex/OpenCode adapters emit WARN about sequential mode.

**Code rules:** DIP — executor depends on the adapter abstraction (a directory contract), not concrete agents. Open/Closed — adding a new agent = adding a new `adapters/<name>/dispatch.*` without touching the executor.

---

<!-- mb-stage:5 -->
### Stage 5: Multi-plan orchestration + `mb-doctor` orphan check + `/mb run` entry point

**What to do:**
- In `mb-pipeline-run.sh`, multi-plan logic:
  - For each plan, dispatch its waves in a sub-process (or main agent loop) — they run in parallel.
  - Lead loop synchronously awaits all plans to reach "ready to merge" state.
  - Then invokes `mb-pipeline-merge.sh` for sequential cherry-pick.
- Create `commands/run.md`:
  - Documents `/mb run <plan>` and `/mb run <plan1> <plan2> ...` and flags.
  - For Claude Code adapter: documents the main-agent dispatch step (after planner+executor produce dispatches.json, main agent reads it and calls Task() N times in one response).
  - Documents `--preset`, `--restart`, `--continue-on-failed-plan`, `--dry-run`.
- Extend `scripts/mb-doctor.sh` (or wherever doctor lives) with `check_orphan_worktrees`:
  - Walks `.git/mb-worktrees/` (if exists).
  - For each subdir older than `cleanup_orphan_worktrees_days` (default 7) — emit WARN with cleanup hint.
  - Never auto-deletes.

**Testing (TDD):**
- `tests/bats/test_mb_pipeline_run_multi_plan.bats` ≥4 cases: 3 plans → 3 worktrees → all complete → sequential merge → all worktrees removed; one plan fails + `--continue-on-failed-plan` → other 2 merged + failed plan worktree preserved.
- `tests/bats/test_mb_doctor_orphan_worktrees.bats` ≥3 cases: no worktrees → silent; young worktree → silent; >7d worktree → WARN with hint.
- `tests/bats/test_run_command_doc.bats` ≥2 cases: `commands/run.md` documents all 4 flags; documents adapter routing.

**DoD (SMART):**
- [ ] Multi-plan orchestration works on fixture (3 plans).
- [ ] `commands/run.md` exists with full documentation.
- [ ] `mb-doctor` has `check_orphan_worktrees`; bats covers all 3 branches.
- [ ] All 3 bats files PASS (≥9 tests).

**Code rules:** Defensive coding — multi-plan loop tolerates one plan's failure when `--continue-on-failed-plan` is set; never silently drops a successful plan's commits.

---

<!-- mb-stage:6 -->
### Stage 6: Install / docs / CHANGELOG / e2e smoke

**What to do:**
- Update `install.sh`:
  - Distributes new scripts + adapter files to skill installation path.
  - Idempotent re-distribution (skip if hash matches).
  - Verifies `.git/mb-worktrees/` is gitignored (under `.git/` always is — note for users with custom git config).
- Author `docs/parallel-pipeline.md`:
  - Operating modes comparison (economic vs parallel) — verbatim from spec §1.5.
  - Pipeline.yaml schema reference + 3 presets.
  - Adapter capability matrix.
  - Worktree lifecycle diagram.
  - Failure handling: loops, gates, pivot_on_stagnant.
  - Budget control.
  - How to extend (add a custom adapter, add a new preset).
- Update `CHANGELOG.md` `[Unreleased]`:
  - Added: `/mb run` command (parallel pipeline mode).
  - Added: `pipeline:` top-level section in pipeline.yaml with `fast/standard/strict` presets.
  - Added: adapter layer for cross-agent dispatch (Claude Code, Pi, Codex, OpenCode).
  - Added: worktree-per-plan isolation; `mb-doctor` orphan check.
  - Added: `pivot_on_stagnant` on_failure kind (requires S2 deployed).
  - Note: `/mb work` semantics unchanged.
- Manual e2e smoke:
  - Create a 2-stage synthetic plan in a scratch git repo.
  - Run `/mb run <plan> --preset=fast` with Claude Code.
  - Verify: worktree created, both stages dispatched in parallel (single main-agent response with 2 Task calls), squashed commit on root branch, worktree removed.

**Testing (TDD):**
- `tests/bats/test_install_distributes_pipeline_files.bats` ≥2 cases: install ships new scripts; idempotent re-install.
- `tests/bats/test_pipeline_e2e_synthetic.bats` ≥1 case: end-to-end on tmp git repo with mocked Task dispatches (file-write stubs).

**DoD (SMART):**
- [ ] `install.sh` updated; idempotent re-run verified.
- [ ] `docs/parallel-pipeline.md` ≥300 lines, covers spec sections §1.5, §4, §5, §8, §10.
- [ ] `CHANGELOG.md` enumerates all S5 additions.
- [ ] Both bats files PASS.
- [ ] Manual smoke completed; commit hash recorded in `progress.md` (via `/mb done`).
- [ ] `/mb verify` clean on branch — no regression in existing bats + pytest suites.

**Code rules:** Documentation reflects implementation, not aspiration. CHANGELOG entries reference the spec for full design rationale.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Symlink `.memory-bank` breaks on non-POSIX (Windows) | M | Document; fallback (mirror+merge) is backlog. Mark as known issue in docs. |
| Cherry-pick conflicts block multi-plan progress | M | Fail-fast policy (spec §5); `--continue-on-failed-plan` for parallel completion of non-conflicting plans; auto-resolve is I-040. |
| Parallel Task dispatch exhausts global budget mid-wave | M | Per-wave reserve check halts BEFORE launch (Stage 2 DoD); conservative `budget_per_wave_pct=30%`. |
| Codex / OpenCode adapters confuse users expecting parallelism | L | Clear stderr WARN at every wave; `docs/parallel-pipeline.md` explicit capability matrix. |
| Pi adapter complexity blocks ship | M | Pi marked hard requirement. If blocked: escalate to user before shipping; fallback strategy is sequential (downgrade). |
| Loop counters allow infinite churn under noisy reviewer | M | S1 calibration suite verifies trend stability; `max_loops` mandatory on every cycle (validation enforced by planner). |
| State cache (`state-<plan>.json`) stale on git operations | L | `--restart` always invalidates; `mb-doctor` detects mismatch (worktree HEAD vs state). |
| Worktrees accumulate from interrupted runs | L | `mb-doctor` orphan check (Stage 5 DoD); user-driven cleanup. |
| `/mb work` semantics drift via shared code edits | L | Hard guarantee documented in spec §1.5; no edits to `commands/work.md` beyond a one-line note pointing to `commands/run.md`. |

## Gate (plan success criterion)

`/mb work 2026-05-24_feature_parallel-pipeline --max-cycles 3 --auto` completes all 6 stages with `plan-verifier` PASS on each, **and**:

1. All new bats files PASS with 0 failures (~9 files, ~30+ tests).
2. All new pytest files PASS with 0 failures (~4 files, ~15+ tests).
3. Existing bats + pytest suites have 0 regressions.
4. `shellcheck` clean on all new bash scripts.
5. `ruff` + `mypy` clean on `mb_pipeline_plan.py`.
6. `mb-rules-check.sh` clean.
7. `docs/parallel-pipeline.md` + `CHANGELOG.md` updated.
8. Manual smoke: `/mb run <synthetic-plan>` in Claude Code shows parallel Task dispatch in a single main-agent response; squashed commit appears on root branch; worktree removed cleanly.
9. Manual smoke: orphan worktree (touch a fake dir under `.git/mb-worktrees/` with old mtime) → `/mb doctor` surfaces WARN.
10. `/mb work` semantics confirmed unchanged: existing bats around `commands/work.md` PASS without modification.
