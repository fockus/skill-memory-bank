# claude-skill-memory-bank: Статус проекта

**Current phase:** учёт банка вычищен `/mb doctor` 2026-09-13 (9 готовых планов → `plans/done/`, `parallel-pipeline` → `plans/superseded/`, статусы канонизированы). `mb-work-cost-diet` Sprint 1 закрыт 7/7 (2026-09-13), но cross-model ревью после закрытия дало **NO_GO** судьи: 3 блокирующих I-194/I-195/I-196 + I-208 ([отчёт](reports/2026-09-13_sprint1-review.md)). Живые треки: SEQUENCE `long-running-sessions` Phase 3 `drive-loop` (T3, T5), I-086 `config-validation-docs` (Stages 3–6), группа `sdd-vision-pipeline` G-001 (пауза с 2026-07-27), `graph-semantic-adoption` (0/7).
**Focus:** `graph-semantic-adoption` (пререквизит Sprint 2 по AGR-044, порядок стадий 6→2→3→1→5→4→7) → Sprint 2 `mb-work-cost-diet` → Sprint 3 → `drive-loop` Task 3 (trend/pivot wiring) → `sdd-vision-pipeline` по DAG T1→S1→S7→S4→S2→S8→S9→S6→S3→S5 (AGR-029). Параллельно HIGH: fix-слайс по ревью Sprint 1 (I-194/I-195/I-196, I-208) — плана ещё нет.
**Blockers:** нет для текущей работы; действует репо-wide FREEZE на деструктивные git-операции (rebase / `reset --hard` / `checkout .` / whole-tree stash) — см. `COORDINATION.md`.

## Metrics

- VERSION: **5.3.1**; scripts: 42 sh / 9 py; hooks: 10; agents: 17 dispatchable + partials; commands: 24
- Tests (baseline 2026-06-10): pytest 1190 / bats 779, 0 failed — свежие числа по сессиям в `progress.md`
- Audit fixes 2026-09-14: R01–R15 закрыты; полный pytest **2614 passed, 1 skipped**, связанные Bats/linters/wheel smoke прошли; независимая проверка 6/6 этапов ([отчёт](reports/2026-09-14_skill-audit-remediation.md)).
- Site: https://fockus.github.io/skill-memory-bank/ · remote: `fockus/skill-memory-bank`
- Last compact: 2026-09-10 (`actualize --strict`, AGR-043 — 10 секций архивировано в `progress.md`)

## Active plans

<!-- mb-active-plans -->
- [2026-05-23] `queued` [2026-05-23_feature_cost-multi-model.md](plans/2026-05-23_feature_cost-multi-model.md) — feature — Cost (multi-model role assignment, S4 of harness-upgrade)
- [2026-05-23] `queued` [2026-05-23_feature_skill-improvements-anthropic-audit.md](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md) — feature — skill-improvements-anthropic-audit
- [2026-05-24] `in_progress` [2026-05-24_fix_cursor-compatibility-remediation.md](plans/2026-05-24_fix_cursor-compatibility-remediation.md) — fix — Cursor Compatibility Remediation
- [2026-05-24] `queued` [2026-05-24_fix_pi-compatibility-remediation.md](plans/2026-05-24_fix_pi-compatibility-remediation.md) — fix — Pi Compatibility Remediation
- [2026-06-23] `in_progress` [2026-06-23_SEQUENCE_codex-remediation.md](plans/2026-06-23_SEQUENCE_codex-remediation.md) — sequence — Execution Sequence — codex/GPT-5.5 remediation (I-082..I-086)
- [2026-06-23] `queued` [2026-06-23_feature_dispatcher-wiring-transports.md](plans/2026-06-23_feature_dispatcher-wiring-transports.md) — feature — Capability Dispatcher Wiring + Transports
- [2026-06-23] `in_progress` [2026-06-23_fix_config-validation-docs.md](plans/2026-06-23_fix_config-validation-docs.md) — fix — Config Validation & Doc Consistency
- [2026-07-05] `in_progress` [2026-07-05_SEQUENCE_long-running-sessions.md](plans/2026-07-05_SEQUENCE_long-running-sessions.md) — sequence-plan — SEQUENCE — Long-running autonomous sessions
- [2026-07-15] `queued` [2026-07-15_feature_mb-donor-evolution-v5-4-baseline.md](plans/2026-07-15_feature_mb-donor-evolution-v5-4-baseline.md) — feature — mb-donor-evolution — v5.4.0 Trustworthy Baseline
- [2026-07-28] `in_progress` [2026-07-28_fix_graph-semantic-adoption.md](plans/2026-07-28_fix_graph-semantic-adoption.md) — fix — graph-semantic-adoption
- [2026-09-05] `queued` [2026-09-05_fix_mb-work-cost-diet-sprint2.md](plans/2026-09-05_fix_mb-work-cost-diet-sprint2.md) — fix — mb-work-cost-diet · Sprint 2 «work-loop-diet»
- [2026-09-05] `queued` [2026-09-05_fix_mb-work-cost-diet-sprint3.md](plans/2026-09-05_fix_mb-work-cost-diet-sprint3.md) — fix — mb-work-cost-diet · Sprint 3 «instruction-diet + гигиена»
<!-- /mb-active-plans -->

## Recently done (last 10)

<!-- mb-recent-done -->
- 2026-09-14 — [plans/done/2026-09-13_fix_skill-audit-runtime.md](plans/done/2026-09-13_fix_skill-audit-runtime.md) — runtime and command contracts
- 2026-09-14 — [plans/done/2026-09-13_fix_skill-audit-data-safety.md](plans/done/2026-09-13_fix_skill-audit-data-safety.md) — data safety
- 2026-09-13 — [plans/done/2026-07-04_feature_code-graph-activation.md](plans/done/2026-07-04_feature_code-graph-activation.md) — Code-Graph Activation (Path A — all four steps)
- 2026-09-13 — [plans/done/2026-07-04_fix_install-and-cross-agent-parity.md](plans/done/2026-07-04_fix_install-and-cross-agent-parity.md) — fix — Install reliability + cross-agent parity
- 2026-09-13 — [plans/done/2026-07-04_fix_session-capture-and-mb-hygiene.md](plans/done/2026-07-04_fix_session-capture-and-mb-hygiene.md) — fix — Session-capture correctness + Memory-Bank drift hygiene
- 2026-09-13 — [plans/done/2026-07-13_feature_update-notify.md](plans/done/2026-07-13_feature_update-notify.md) — feature — Update notification + cross-install upgrade
- 2026-09-13 — [plans/done/2026-07-15_feature_docs-site-and-landing-refresh.md](plans/done/2026-07-15_feature_docs-site-and-landing-refresh.md) — feature — Docs site (MkDocs Material) + landing refresh
- 2026-09-13 — [plans/done/2026-07-18_fix_spec-group-round3-remediation.md](plans/done/2026-07-18_fix_spec-group-round3-remediation.md) — fix — spec-group-round3-remediation
- 2026-09-13 — [plans/done/2026-05-23_feature_work-loop-v2.md](plans/done/2026-05-23_feature_work-loop-v2.md) — feature — Work loop 2.0 (S2 of harness-upgrade)
- 2026-09-13 — [plans/done/2026-05-23_feature_reviewer-v2.md](plans/done/2026-05-23_feature_reviewer-v2.md) — feature — Reviewer 2.0 (S1 of harness-upgrade)
<!-- /mb-recent-done -->

## Roadmap (high level)

См. [roadmap.md](roadmap.md) (порядок волн, ICE-приоритизация) и [backlog.md](backlog.md) (реестр идей + ADR).
