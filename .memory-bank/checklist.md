# claude-skill-memory-bank — Чеклист

> **Convention.** Этот файл — short list **активных** и недавно завершённых задач. Hard cap **≤120 строк**. Старые спринты живут в `progress.md` (per-day лог) и `roadmap.md "Recently completed"` (per-phase summary). Закрытые планы — в `plans/done/`. Если строки уползли за лимит — архивируй вниз по той же схеме.

## ⏳ In flight

- ⬜ Sprint 1 — [feature global-storage-core](plans/2026-05-21_feature_global-storage.md): resolver, global init UX, command/rules active-state semantics.

## ⏭ Next planned

- ⬜ Sprint 2 — [feature global-storage-agent-support](plans/2026-05-21_feature_global-storage-agent-support.md): hooks, adapters, docs and E2E support for all supported code agents.
- ⬜ Sprint 3 — [feature rule-profiles-and-stack-presets](plans/2026-05-21_feature_rule-profiles-and-stack-presets.md): configurable architecture/delivery/role/stack profiles for rules-only and Memory Bank modes.

## ✅ Recently completed (last 3 sprints — full history → progress.md)

### GraphRAG-lite code context ✅ (2026-05-21) — portable graph query CLI + `code_context` evidence pack + Pi/OpenCode/Codex/generic wrapper guidance. `/mb verify` PASS: rules-check 0 violations, focused pytest 40 passed, bats 17+9 ok, full `mb-test-run` 708 passed.

### Cursor adapter remediation ✅ (2026-05-21) — 10 Cursor hooks (sessionStart + tool matchers), VERSION single-source, User Rules paste UX + markers. pytest + bats green.

### I-004 ✅ (2026-04-25) — Plan: [2026-04-25_feature_i004-auto-commit.md](plans/done/2026-04-25_feature_i004-auto-commit.md). Opt-in `mb-auto-commit.sh` (`MB_AUTO_COMMIT=1`) для `/mb done` step 7. 4 safety gates + 10 pytest tests. Tests 615 → 628 (+13).

### Phase 4 Sprint 3 ✅ (2026-04-25) — Plan: [2026-04-25_feature_phase4-sprint3-installer-and-release.md](plans/done/2026-04-25_feature_phase4-sprint3-installer-and-release.md). Installer auto-registers 5 v2 hooks; `mb-reviewer-resolve.sh` honours `pipeline.yaml` superpowers override; **VERSION 4.0.0** + CHANGELOG `[4.0.0]` cut. Tests 596 → 615 (+19).

### I-033 ✅ (2026-04-25) — Plan: [2026-04-25_refactor_checklist-prune-i033.md](plans/done/2026-04-25_refactor_checklist-prune-i033.md). `mb-checklist-prune.sh` + ≤120-line CI cap-test + wire-ins.

## 📜 Pre-Phase 3 history (compact pointer)

Phase 1 Foundation, Phase 2 (discuss + sdd + plan-lite), Phase 3 Sprint 1 (`/mb config` + `pipeline.yaml`), Phase 3 Sprint 2 (`/mb work` + 9 role-agents) — все закрыты до 2026-04-25. Полный детальный лог — `progress.md` (за 2026-04-19 → 2026-04-25) + `roadmap.md "Recently completed"` + `plans/done/`. v2.0/2.1/2.2/3.0/3.1.x release gates — `progress.md` за 2026-04-20/21.

## 🔓 Open backlog hot list (HIGH/MED — full list → backlog.md)

- I-023 (MED) — grep→find в `start.md`/`mb-doctor` (cleanup, low risk)
- All HIGH items resolved as of Phase 4 Sprint 2 end-of-day. Reopen via `/mb idea` if regression spotted.

## 🧭 See also

- `progress.md` — append-only daily log + per-sprint deep dive + lessons
- `roadmap.md` — phase/sprint roadmap + "Recently completed" pull-quotes + `## Now / Next / Parallel-safe` auto-blocks
- `backlog.md` — full ideas + ADR ledger
- `plans/done/` — full per-sprint plan files (DoD, stages, retrospective)
- `lessons.md` — recurring antipatterns + design lessons

- ✅ Stages 1-6: resolver contract tests + 6 `_lib.sh` helpers + `mb-init-bank.sh` global flags + `/mb init` UX + runtime docs/rules-only mode + full verification (735 pytest, 119 focused bats, 3 doc-regressions fixed, checklist 181→68 lines). Detail → `plans/2026-05-21_feature_global-storage.md`.

- ✅ Stages 1-6: RED contract test (`test_global_storage_contract.py`, 11 cases) + resolver-aware hooks (3 hooks + git-hooks-fallback honour `MB_PATH`) + adapter matrix (opencode JS plugin, cursor/codex/pi/windsurf/cline/kilo runtime + docs) + Codex global AGENTS embeds TDD/SOLID/Clean Architecture/DRY/KISS/YAGNI/`[MEMORY BANK: ABSENT]` via sed-merge + storage modes docs (SKILL.md/README.md/docs/install.md/docs/cross-agent-setup.md) + E2E suite (`tests/e2e/test_global_storage.bats`, 4 cases). Detail → `plans/2026-05-21_feature_global-storage-agent-support.md`.

- ✅ Stages 1-6: profile schema doc + 7 fixtures + RED pytest (26 cases) → `memory_bank_skill/rules_profile.py` + `scripts/mb-profile.sh` CLI (10 bats) → 22 built-in preset JSONs (roles/stacks/architecture/delivery, 12 composition tests) → `mb-rules-check.sh` profile integration (strictness-aware exit, rule_id/profile_source fields, stack-aware checks for go/python/typescript/javascript/java, fsd architecture hint, 8 bats) → `/mb profile` command + `commands/profile.md` + `docs/rule-profiles.md` + README/SKILL.md updates (7 new runtime tests) → CHANGELOG + verification (798 pytest, full bats, ruff clean). Detail → `plans/2026-05-21_feature_rule-profiles-and-stack-presets.md`.

<!-- mb-plan:done/2026-05-21_refactor_sdd-task-model.md -->
## sdd-task-model Sprint 1 — DONE ✅
- ✅ Stages 1-3: RED tests + `mb_work_items.py` parser (stdlib, JSON Lines CLI) + `mb-sdd.sh` emits new `<!-- mb-task:N -->` format (27/27 sdd+parser tests green, smoke OK). Detail → `plans/done/2026-05-21_refactor_sdd-task-model.md`.
- ✅ Stages 4-5: `scripts/mb-spec-validate.sh` (12 pytest cases GREEN, shellcheck clean) + Sprint 1 closeout. Sprint 2 (`sdd-work-engine`) unblocked.

<!-- mb-plan:done/2026-05-21_refactor_sdd-work-engine.md -->
## sdd-work-engine Sprint 2 — DONE ✅
- ✅ Stages 1-6: RED tests + `mb-work-resolve.sh` (Form 3 markers/Form 4 specs candidates) + `mb-work-range.sh` (mb-stage/mb-task auto-detect, mixed-format reject) + `mb-work-plan.sh` refactor (inline parser deleted, uses `mb_work_items.py`, +source/kind/covers/item_no, plan-as-wrapper via linked_spec) + `commands/work.md` Sprint 2 docs + bats. 46/46 work-stack tests GREEN. Sprint 3 (`sdd-traceability-docs`) unblocked. Detail → `plans/done/2026-05-21_refactor_sdd-work-engine.md`.

<!-- mb-plan:done/2026-05-21_refactor_sdd-traceability-docs.md -->
## sdd-traceability-docs Sprint 3 — DONE ✅
- ✅ Stages 1-5: traceability scans specs/*/tasks.md (Spec Task column + Tasks-covered summary) + `scripts/mb-spec-tasks-migrate.sh` (9 pytest cases, idempotent, dry-run default) + SKILL.md/sdd.md/plan.md/templates.md unified SDD docs (7 pytest + 4 bats GREEN) + Phase E2E gate PASS. Phase `sdd-unification` closed.

<!-- mb-plan:2026-05-23_feature_reviewer-v2.md -->
## Stage 1: Orchestrator skeleton + sha/TTL cache helper
- ⬜ Orchestrator skeleton + sha/TTL cache helper

<!-- mb-plan:2026-05-23_feature_reviewer-v2.md -->
## Stage 2: Examples loader + layered resolver + baseline examples (common / python / go)
- ⬜ Examples loader + layered resolver + baseline examples (common / python / go)

<!-- mb-plan:2026-05-23_feature_reviewer-v2.md -->
## Stage 3: Remaining stack baseline examples (typescript / frontend / mobile / backend)
- ⬜ Remaining stack baseline examples (typescript / frontend / mobile / backend)

<!-- mb-plan:2026-05-23_feature_reviewer-v2.md -->
## Stage 4: Test-cache resolver + payload assembly + auto-finding pre-injection
- ⬜ Test-cache resolver + payload assembly + auto-finding pre-injection

<!-- mb-plan:2026-05-23_feature_reviewer-v2.md -->
## Stage 5: Reviewer agent rewrite + wire `/mb work` + pipeline defaults + install.sh
- ⬜ Reviewer agent rewrite + wire `/mb work` + pipeline defaults + install.sh

<!-- mb-plan:2026-05-23_feature_reviewer-v2.md -->
## Stage 6: Golden calibration suite + CI workflow + docs + CHANGELOG
- ⬜ Golden calibration suite + CI workflow + docs + CHANGELOG

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-phase.md -->
## Stage 1: Sprint 1 — Prompt overlay + addons
- ⬜ Sprint 1 — Prompt overlay + addons

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-phase.md -->
## Stage 2: Sprint 2 — mb-debugger + `/mb debug`
- ⬜ Sprint 2 — mb-debugger + `/mb debug`

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-phase.md -->
## Stage 3: Sprint 3 — Worktree isolation
- ⬜ Sprint 3 — Worktree isolation

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-phase.md -->
## Stage 4: Sprint 4 — Atomic commit per stage
- ⬜ Sprint 4 — Atomic commit per stage

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-phase.md -->
## Stage 5: Sprint 5 — Parallel waves (DAG)
- ⬜ Sprint 5 — Parallel waves (DAG)

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-phase.md -->
## Stage 6: Sprint 6 — Goal layer + `/goal`
- ⬜ Sprint 6 — Goal layer + `/goal`

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-phase.md -->
## Stage 7: Sprint 7 — Autopilot loop
- ⬜ Sprint 7 — Autopilot loop

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-1-prompt-overlay.md -->
## Stage 1: Build `scripts/mb-agent-resolve.sh`
- ⬜ Build `scripts/mb-agent-resolve.sh`

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-1-prompt-overlay.md -->
## Stage 2: Create initial addon set under `agents/addons/`
- ⬜ Create initial addon set under `agents/addons/`

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-1-prompt-overlay.md -->
## Stage 3: Extend `pipeline.yaml` schema for `agents.preamble_addons`
- ⬜ Extend `pipeline.yaml` schema for `agents.preamble_addons`

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-1-prompt-overlay.md -->
## Stage 4: Wire `/mb work` dispatch through resolver + addons
- ⬜ Wire `/mb work` dispatch through resolver + addons

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-1-prompt-overlay.md -->
## Stage 5: Documentation — `docs/concepts/overlay-system.md`
- ⬜ Documentation — `docs/concepts/overlay-system.md`

<!-- mb-plan:2026-05-23_feature_work-loop-v2.md -->
## Stage 1: Trend calculator + previous-verdict cache
- ⬜ Trend calculator + previous-verdict cache

<!-- mb-plan:2026-05-23_feature_work-loop-v2.md -->
## Stage 2: Contract phase script + reviewer contract-mode rubric
- ⬜ Contract phase script + reviewer contract-mode rubric

<!-- mb-plan:2026-05-23_feature_work-loop-v2.md -->
## Stage 3: Pivot dispatch — `pivot_in_role` + `pivot_via_architect`
- ⬜ Pivot dispatch — `pivot_in_role` + `pivot_via_architect`

<!-- mb-plan:2026-05-23_feature_work-loop-v2.md -->
## Stage 4: `on_max_cycles` default flip + new pipeline keys
- ⬜ `on_max_cycles` default flip + new pipeline keys

<!-- mb-plan:2026-05-23_feature_work-loop-v2.md -->
## Stage 5: Wire into `/mb work` + docs + CHANGELOG
- ⬜ Wire into `/mb work` + docs + CHANGELOG

<!-- mb-plan:2026-05-23_feature_handoff-v2.md -->
## Stage 1: Handoff capsule script + template
- ⬜ Handoff capsule script + template

<!-- mb-plan:2026-05-23_feature_handoff-v2.md -->
## Stage 2: PreCompact hook rewrite + SessionStart capsule injection
- ⬜ PreCompact hook rewrite + SessionStart capsule injection

<!-- mb-plan:2026-05-23_feature_handoff-v2.md -->
## Stage 3: Mandatory done-gates + commands/done.md update
- ⬜ Mandatory done-gates + commands/done.md update

<!-- mb-plan:2026-05-23_feature_handoff-v2.md -->
## Stage 4: Progress hash chain + drift integration
- ⬜ Progress hash chain + drift integration

<!-- mb-plan:2026-05-23_feature_handoff-v2.md -->
## Stage 5: Docs + CHANGELOG + integration verify
- ⬜ Docs + CHANGELOG + integration verify

<!-- mb-plan:2026-05-23_feature_cost-multi-model.md -->
## Stage 1: Aliases table + resolver script
- ⬜ Aliases table + resolver script

<!-- mb-plan:2026-05-23_feature_cost-multi-model.md -->
## Stage 2: Default model matrix in pipeline.yaml + agent frontmatter
- ⬜ Default model matrix in pipeline.yaml + agent frontmatter

<!-- mb-plan:2026-05-23_feature_cost-multi-model.md -->
## Stage 3: Wire dispatch sites in commands/* + reviewer-resolve augmentation
- ⬜ Wire dispatch sites in commands/* + reviewer-resolve augmentation

<!-- mb-plan:2026-05-23_feature_cost-multi-model.md -->
## Stage 4: Docs + CHANGELOG + calibration validation
- ⬜ Docs + CHANGELOG + calibration validation

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-2-mb-debugger.md -->
## Stage 1: Spec Task 6 — `agents/mb-debugger.md` prompt
- ⬜ Spec Task 6 — `agents/mb-debugger.md` prompt

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-2-mb-debugger.md -->
## Stage 2: Spec Task 7 — `mb-debugger-parse.sh` validator
- ⬜ Spec Task 7 — `mb-debugger-parse.sh` validator

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-2-mb-debugger.md -->
## Stage 3: Spec Task 8 — `commands/debug.md`
- ⬜ Spec Task 8 — `commands/debug.md`

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-2-mb-debugger.md -->
## Stage 4: Spec Task 9 — `pipeline.yaml: agents.debugger.*` schema
- ⬜ Spec Task 9 — `pipeline.yaml: agents.debugger.*` schema

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-2-mb-debugger.md -->
## Stage 5: Spec Task 10 — `/mb work` auto-trigger on FAIL
- ⬜ Spec Task 10 — `/mb work` auto-trigger on FAIL

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-2-mb-debugger.md -->
## Stage 6: Spec Task 11 — Documentation (debugging.md + commands/debug.md)
- ⬜ Spec Task 11 — Documentation (debugging.md + commands/debug.md)

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-3-worktree.md -->
## Stage 1: Spec Task 12 — `scripts/mb-work-worktree.sh`
- ⬜ Spec Task 12 — `scripts/mb-work-worktree.sh`

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-3-worktree.md -->
## Stage 2: Spec Task 13 — `pipeline.yaml: execution.use_worktree` schema
- ⬜ Spec Task 13 — `pipeline.yaml: execution.use_worktree` schema

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-3-worktree.md -->
## Stage 3: Spec Task 14 — `/mb work` CWD wiring + cleanup
- ⬜ Spec Task 14 — `/mb work` CWD wiring + cleanup

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-3-worktree.md -->
## Stage 4: Spec Task 15 — Documentation (worktree-isolation.md)
- ⬜ Spec Task 15 — Documentation (worktree-isolation.md)

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-4-atomic-commit.md -->
## Stage 1: Spec Task 16 — Template renderer + stage SHA snapshot
- ⬜ Spec Task 16 — Template renderer + stage SHA snapshot

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-4-atomic-commit.md -->
## Stage 2: Spec Task 17 — Safety gates shared library
- ⬜ Spec Task 17 — Safety gates shared library

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-4-atomic-commit.md -->
## Stage 3: Spec Task 18 — `/mb work` step 3g integration
- ⬜ Spec Task 18 — `/mb work` step 3g integration

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-4-atomic-commit.md -->
## Stage 4: Spec Task 19 — `pipeline.yaml: execution.auto_commit_code` schema
- ⬜ Spec Task 19 — `pipeline.yaml: execution.auto_commit_code` schema

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-4-atomic-commit.md -->
## Stage 5: Spec Task 20 — Documentation (atomic-commit.md)
- ⬜ Spec Task 20 — Documentation (atomic-commit.md)

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-5-parallel-waves.md -->
## Stage 1: Spec Task 21 — Extend marker parser with `depends_on`
- ⬜ Spec Task 21 — Extend marker parser with `depends_on`

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-5-parallel-waves.md -->
## Stage 2: Spec Task 22 — `scripts/mb-work-dag.sh`
- ⬜ Spec Task 22 — `scripts/mb-work-dag.sh`

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-5-parallel-waves.md -->
## Stage 3: Spec Task 23 — `mb-work-plan.sh` wave assignment
- ⬜ Spec Task 23 — `mb-work-plan.sh` wave assignment

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-5-parallel-waves.md -->
## Stage 4: Spec Task 24 — `--parallel` dispatch + file-conflict guard
- ⬜ Spec Task 24 — `--parallel` dispatch + file-conflict guard

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-5-parallel-waves.md -->
## Stage 5: Spec Task 25 — Budget-aware sequential fallback
- ⬜ Spec Task 25 — Budget-aware sequential fallback

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-5-parallel-waves.md -->
## Stage 6: Spec Task 26 — `pipeline.yaml: execution.parallel_waves` schema
- ⬜ Spec Task 26 — `pipeline.yaml: execution.parallel_waves` schema

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-5-parallel-waves.md -->
## Stage 7: Spec Task 27 — Documentation (parallel-waves.md)
- ⬜ Spec Task 27 — Documentation (parallel-waves.md)

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-6-goal-layer.md -->
## Stage 1: Spec Task 28 — `scripts/mb-goal.sh`
- ⬜ Spec Task 28 — `scripts/mb-goal.sh`

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-6-goal-layer.md -->
## Stage 2: Spec Task 29 — `commands/goal.md` dispatcher
- ⬜ Spec Task 29 — `commands/goal.md` dispatcher

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-6-goal-layer.md -->
## Stage 3: Spec Task 30 — `/goal init` interactive flow (5-6 questions)
- ⬜ Spec Task 30 — `/goal init` interactive flow (5-6 questions)

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-6-goal-layer.md -->
## Stage 4: Spec Task 31 — `pipeline.yaml: goals.*` schema
- ⬜ Spec Task 31 — `pipeline.yaml: goals.*` schema

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-6-goal-layer.md -->
## Stage 5: Spec Task 32 — `/mb start` integration
- ⬜ Spec Task 32 — `/mb start` integration

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-6-goal-layer.md -->
## Stage 6: Spec Task 33 — Documentation (workflows/goal-driven.md + commands/goal.md)
- ⬜ Spec Task 33 — Documentation (workflows/goal-driven.md + commands/goal.md)

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-7-autopilot.md -->
## Stage 1: Spec Task 34 — Autopilot driver with startup checks
- ⬜ Spec Task 34 — Autopilot driver with startup checks

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-7-autopilot.md -->
## Stage 2: Spec Task 35 — Goal-aware loop + iteration counters
- ⬜ Spec Task 35 — Goal-aware loop + iteration counters

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-7-autopilot.md -->
## Stage 3: Spec Task 36 — Hard-stop integration
- ⬜ Spec Task 36 — Hard-stop integration

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-7-autopilot.md -->
## Stage 4: Spec Task 37 — Auto-recovery via mb-debugger inside loop
- ⬜ Spec Task 37 — Auto-recovery via mb-debugger inside loop

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-7-autopilot.md -->
## Stage 5: Spec Task 38 — `pipeline.yaml: execution.autopilot.*` schema
- ⬜ Spec Task 38 — `pipeline.yaml: execution.autopilot.*` schema

<!-- mb-plan:2026-05-23_feature_goal-driven-autopilot-sprint-7-autopilot.md -->
## Stage 6: Spec Task 39 — Documentation (workflows/autopilot.md)
- ⬜ Spec Task 39 — Documentation (workflows/autopilot.md)

<!-- mb-plan:2026-05-23_feature_skill-improvements-anthropic-audit.md -->
## Stage 1: DESIGN-DECISIONS.md — обоснование намеренных отклонений
- ⬜ DESIGN-DECISIONS.md — обоснование намеренных отклонений

<!-- mb-plan:2026-05-23_feature_skill-improvements-anthropic-audit.md -->
## Stage 2: CONTRIBUTING.md — skill testing matrix
- ⬜ CONTRIBUTING.md — skill testing matrix

<!-- mb-plan:2026-05-23_feature_skill-improvements-anthropic-audit.md -->
## Stage 3: evaluations/skill-discovery — JSON eval suite
- ⬜ evaluations/skill-discovery — JSON eval suite

<!-- mb-plan:2026-05-23_feature_skill-improvements-anthropic-audit.md -->
## Stage 4: README — Quick-start с 5 базовыми командами
- ⬜ README — Quick-start с 5 базовыми командами

<!-- mb-plan:2026-05-23_feature_skill-improvements-anthropic-audit.md -->
## Stage 5: README — раздел "Vibe coding mode"
- ⬜ README — раздел "Vibe coding mode"

<!-- mb-plan:2026-05-23_feature_skill-improvements-anthropic-audit.md -->
## Stage 6: install.sh — interactive minimal/full profile prompt
- ⬜ install.sh — interactive minimal/full profile prompt

<!-- mb-plan:2026-05-24_feature_parallel-pipeline.md -->
## Stage 1: Pipeline schema + Python planner + DAG validation
- ⬜ Pipeline schema + Python planner + DAG validation

<!-- mb-plan:2026-05-24_feature_parallel-pipeline.md -->
## Stage 2: Bash executor + worktree lifecycle + state cache
- ⬜ Bash executor + worktree lifecycle + state cache

<!-- mb-plan:2026-05-24_feature_parallel-pipeline.md -->
## Stage 3: Wave control flow + gates + loops + pivot_on_stagnant
- ⬜ Wave control flow + gates + loops + pivot_on_stagnant

<!-- mb-plan:2026-05-24_feature_parallel-pipeline.md -->
## Stage 4: Cross-agent dispatch + per-phase model routing — adapter layer
- ⬜ Cross-agent dispatch + per-phase model routing — adapter layer

<!-- mb-plan:2026-05-24_feature_parallel-pipeline.md -->
## Stage 5: Multi-plan orchestration + `mb-doctor` orphan check + `/mb run` entry point
- ⬜ Multi-plan orchestration + `mb-doctor` orphan check + `/mb run` entry point

<!-- mb-plan:2026-05-24_feature_parallel-pipeline.md -->
## Stage 6: Install / docs / CHANGELOG / e2e smoke
- ⬜ Install / docs / CHANGELOG / e2e smoke
