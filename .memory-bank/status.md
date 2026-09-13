# claude-skill-memory-bank: Статус проекта

**Current phase:** `mb-work-cost-diet` Sprint 1 закрыт 7/7 (2026-09-13, `/mb verify` PASS 44/44, `plans/done/2026-09-05_fix_mb-work-cost-diet-sprint1.md`; done-гейты форсированы через pre-existing неродственные тестовые провалы — NOTE в `progress.md`). Живые треки: `long-running-sessions` SEQUENCE Phase 3 `drive-loop` (Task 3 + Task 5 открыты), `sdd-vision-pipeline` group G-001 (детали — `checklist.md`/`COORDINATION.md`), `graph-semantic-adoption` (план создан AGR-038, 0/7).
**Focus:** `graph-semantic-adoption` (пререквизит Sprint 2 по AGR-044, порядок стадий 6→2→3→1→5→4→7) → Sprint 2 `mb-work-cost-diet` → Sprint 3 → `drive-loop` Task 3 (trend/pivot wiring) → `sdd-vision-pipeline` по DAG T1→S1→S7→S4→S2→S8→S9→S6→S3→S5 (AGR-029).
**Blockers:** нет для текущей работы; действует репо-wide FREEZE на деструктивные git-операции (rebase / `reset --hard` / `checkout .` / whole-tree stash) — см. `COORDINATION.md`.

## Metrics

- VERSION: **5.3.1**; scripts: 42 sh / 9 py; hooks: 10; agents: 17 dispatchable + partials; commands: 24
- Tests (baseline 2026-06-10): pytest 1190 / bats 779, 0 failed — свежие числа по сессиям в `progress.md`
- Site: https://fockus.github.io/skill-memory-bank/ · remote: `fockus/skill-memory-bank`
- Last compact: 2026-09-10 (`actualize --strict`, AGR-043 — 10 секций архивировано в `progress.md`)

## Active plans

<!-- mb-active-plans -->
- [2026-05-24] `in_progress` [2026-05-24_fix_cursor-compatibility-remediation.md](plans/2026-05-24_fix_cursor-compatibility-remediation.md) — fix — Cursor hook parity + adapter bundle paths (spec: cursor-extension)
- [2026-05-24] `queued` [2026-05-24_feature_opencode-first-adaptation.md](plans/2026-05-24_feature_opencode-first-adaptation.md) — feature — Plan: feature — OpenCode-first adaptation (native plugin, dispatch abstraction, hook parity; cross-cutting infrastructure for W1–W12)
- [2026-05-24] `queued` [2026-05-24_fix_pi-compatibility-remediation.md](plans/2026-05-24_fix_pi-compatibility-remediation.md) — fix — Plan: fix — Pi extension (subagents + hooks + commands + model providers)
- [2026-05-23] `queued` [2026-05-23_feature_cost-multi-model.md](plans/2026-05-23_feature_cost-multi-model.md) — feature — Plan: feature — Cost (multi-model role assignment, S4 of harness-upgrade)
- [2026-05-23] `queued` [2026-05-23_feature_goal-driven-autopilot-sprint-1-prompt-overlay.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-1-prompt-overlay.md) — feature — Plan: feature — goal-driven-autopilot — Sprint 1: Prompt overlay + addons
- [2026-05-23] `queued` [2026-05-23_feature_goal-driven-autopilot-sprint-2-mb-debugger.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-2-mb-debugger.md) — feature — Plan: feature — goal-driven-autopilot — Sprint 2: mb-debugger + `/mb debug`
- [2026-05-23] `queued` [2026-05-23_feature_goal-driven-autopilot-sprint-3-worktree.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-3-worktree.md) — feature — Plan: feature — goal-driven-autopilot — Sprint 3: Worktree isolation
- [2026-05-23] `queued` [2026-05-23_feature_goal-driven-autopilot-sprint-4-atomic-commit.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-4-atomic-commit.md) — feature — Plan: feature — goal-driven-autopilot — Sprint 4: Atomic commit per stage
- [2026-05-23] `queued` [2026-05-23_feature_goal-driven-autopilot-sprint-5-parallel-waves.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-5-parallel-waves.md) — feature — Plan: feature — goal-driven-autopilot — Sprint 5: Parallel waves (DAG)
- [2026-05-23] `queued` [2026-05-23_feature_goal-driven-autopilot-sprint-6-goal-layer.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-6-goal-layer.md) — feature — Plan: feature — goal-driven-autopilot — Sprint 6: Goal layer + `/goal`
- [2026-05-23] `queued` [2026-05-23_feature_goal-driven-autopilot-sprint-7-autopilot.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-7-autopilot.md) — feature — Plan: feature — goal-driven-autopilot — Sprint 7: Autopilot loop
- [2026-05-23] `queued` [2026-05-23_feature_reviewer-v2.md](plans/2026-05-23_feature_reviewer-v2.md) — feature — Plan: feature — Reviewer 2.0 (S1 of harness-upgrade)
- [2026-05-23] `queued` [2026-05-23_feature_skill-improvements-anthropic-audit.md](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md) — feature — Plan: feature — skill-improvements-anthropic-audit
- [2026-05-23] `queued` [2026-05-23_feature_work-loop-v2.md](plans/2026-05-23_feature_work-loop-v2.md) — feature — Plan: feature — Work loop 2.0 (S2 of harness-upgrade)
- [2026-05-24] `queued` [2026-05-24_feature_parallel-pipeline.md](plans/2026-05-24_feature_parallel-pipeline.md) — feature — Plan: feature — Parallel pipeline (S5 of harness-upgrade)
- [2026-05-23] `paused` [2026-05-23_feature_goal-driven-autopilot-phase.md](plans/2026-05-23_feature_goal-driven-autopilot-phase.md) — feature — Plan: feature — goal-driven-autopilot (Phase roadmap)
- [2026-07-18] [plans/2026-07-18_fix_spec-group-round3-remediation.md](plans/2026-07-18_fix_spec-group-round3-remediation.md) — fix — spec-group-round3-remediation
- [2026-07-28] [plans/2026-07-28_fix_graph-semantic-adoption.md](plans/2026-07-28_fix_graph-semantic-adoption.md) — fix — graph-semantic-adoption
- [2026-09-13] [plans/2026-09-13_fix_sprint1-review-blockers.md](plans/2026-09-13_fix_sprint1-review-blockers.md) — fix — sprint1-review-blockers · три воспроизведённых блокера судьи Sprint 1
<!-- /mb-active-plans -->

## Recently done (last 10)

<!-- mb-recent-done -->
- 2026-09-13 — [plans/done/2026-09-05_fix_mb-work-cost-diet-sprint1.md](plans/done/2026-09-05_fix_mb-work-cost-diet-sprint1.md) — fix — mb-work-cost-diet · Sprint 1 «context-diet + измерение»
- 2026-06-15 — [specs/handoff-v2/](specs/handoff-v2/) — feature — Handoff 2.0 (5/5): handoff capsule + PreCompact/SessionStart hooks + mandatory `/mb done` gates + append-only sha256 progress chain + docs; governed dual-review (Codex + lead) + judge, fix-cycle per task
- 2026-06-14 — [specs/tier1-graph-memory/](specs/tier1-graph-memory/) — feature — Tier-1 graph + session memory (17/17): RRF/import-aware/PageRank graph, progressive-disclosure recall, `/mb recap`+`/mb conflicts`+`/mb consolidate`, `--sessions` graph layer, wiki staleness+decisions; + 5.1.0 release prep
- 2026-06-10 — [specs/composable-work-pipeline/](specs/composable-work-pipeline/) — feature — composable `/mb work` pipeline (review off by default) + v5.0.0 release prep
- 2026-06-09 — [plans/done/2026-06-09_feature_mb-research-tooling-core.md](plans/done/2026-06-09_feature_mb-research-tooling-core.md) — feature — mb-research-tooling-core
- 2026-06-07 — [plans/done/2026-06-07_refactor_rules-context-economy.md](plans/done/2026-06-07_refactor_rules-context-economy.md) — refactor — rules-context-economy
- 2026-05-27 — [plans/done/2026-05-24_fix_ci-baseline-wave-0.md](plans/done/2026-05-24_fix_ci-baseline-wave-0.md) — fix — CI baseline (Wave 0 before Wave 1; latest green `26528106396`)
- 2026-05-24 — [plans/done/2026-05-21_feature_rule-profiles-and-stack-presets.md](plans/done/2026-05-21_feature_rule-profiles-and-stack-presets.md) — feature — rule-profiles-and-stack-presets
- 2026-05-24 — [plans/done/2026-05-21_feature_global-storage-agent-support.md](plans/done/2026-05-21_feature_global-storage-agent-support.md) — feature — global-storage-agent-support
- 2026-05-24 — [plans/done/2026-05-21_feature_global-storage.md](plans/done/2026-05-21_feature_global-storage.md) — feature — global-storage-core
<!-- /mb-recent-done -->

## Roadmap (high level)

См. [roadmap.md](roadmap.md) (порядок волн, ICE-приоритизация) и [backlog.md](backlog.md) (реестр идей + ADR).
