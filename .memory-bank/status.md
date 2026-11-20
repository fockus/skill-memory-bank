# claude-skill-memory-bank: Статус проекта

**Current phase:** экономия усилий закрыта 2026-10-07 (5 уровней задачи + роутинг, тон по модели, пресеты simple/medium/complex/governed + cost tiers, настройки качества проекта, ADaPT-lite, Key rules onboarding, диета always-loaded, `anthropic-skill-guide-compliance` Sprint 2); открыт только `proportional-effort` Sprint 2 Stage 4 (замер «после», AGR-072). `graph-semantic-adoption` 9/11; Pi native integration 0/5 accepted. `/mb drive` закрыт (`drive-autopilot` 7/7, `drive-loop` superseded, 2026-11-18). Живые треки: I-086 `config-validation-docs` (Stages 3–6), `sdd-vision-pipeline` G-001 (пауза с 2026-07-27).
**Focus:** master-completion closed 2026-11-19 ([plan](plans/done/2026-11-18_feature_master-completion.md), AGR-101…108): 22/22 stages; deferred — I-293, I-299, I-303 (graph re-measure 2026-11-26), I-304, I-305. Next: the rest of `sdd-vision-pipeline` (S1/S2/S3/S6/S9 + umbrella) in unfinished-work-completion; G-001 parked (AGR-106). Local main is behind origin by 10 commits (CI fixes from another session) — merge pending.
**Blockers:** нет для текущей работы; действует репо-wide FREEZE на деструктивные git-операции (rebase / `reset --hard` / `checkout .` / whole-tree stash) — см. `COORDINATION.md`.

## Pi native integration — 2026-10-05

**Latest parent observation:** preparation workflow `12d789f4-bed8-4330-9445-a94346a1f8d1` and writer `d73331ef-c8fe-479b-aad8-0f7c6dedfa6f` completed PROBE_PREPARED. Main parent reviewed frozen sources, observed two pre-launch negative refusals, diagnosed/preserved its venv realpath invocation error (no leaf), then reran the SAME finite product SDK test preserving the existing venv path: **exit 0, controlled Tintin leaf runtime PASS**. Actual child `6b4e3eff-2854-488`, distinct real SDK leaf/producer sessions, inherited `openai/gpt-6.1-sol`/`openai-responses` metadata, configured/callable/active/request tools `[read]`, loaded leaf extensions `[]`, 1 simulated loopback request, 0 actual tool calls/results, terminal consumed, SDK/service/scratch cleanup confirmed. No guard clear/private observer/model/provider fallback/production edits. [Parent runtime assessment](reports/pi-native-integration/leaf-probe-scope/parent-runtime-assessment.md) and exact receipts/logs/hashes retained. **Nico public complete actual child tool/resource observation remains unestablished/BLOCKED**; root Nico loading is not a Nico leaf. Full both-engine matrix/preservation, actual failure-cleanup cases and independent verify/Codex/judge/parent/Eval gates remain pending. This is not live-provider/TUI acceptance; **0/5 accepted**, original source/slot/cycles unchanged.

Historical execution checkpoints → `progress.md` § [status archive] Pi native integration (2026-10-06).

## Metrics

- VERSION: **5.4.1**; scripts: 42 sh / 9 py; hooks: 10; agents: 17 dispatchable + partials; commands: 24
- Tests (baseline 2026-06-10): pytest 1190 / bats 779, 0 failed — свежие числа по сессиям в `progress.md`
- Audit fixes 2026-09-14: R01–R15 закрыты; полный pytest **2614 passed, 1 skipped**, связанные Bats/linters/wheel smoke прошли; независимая проверка 6/6 этапов ([отчёт](reports/2026-09-14_skill-audit-remediation.md)).
- Site: https://fockus.github.io/skill-memory-bank/ · remote: `fockus/skill-memory-bank`
- Last compact: 2026-09-10 (`actualize --strict`, AGR-043 — 10 секций архивировано в `progress.md`)

## Active plans

<!-- mb-active-plans -->
- [2026-05-23] `queued` [2026-05-23_feature_cost-multi-model.md](plans/2026-05-23_feature_cost-multi-model.md) — feature — Cost (multi-model role assignment, S4 of harness-upgrade)
- [2026-05-23] `queued` [2026-05-23_feature_skill-improvements-anthropic-audit.md](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md) — feature — skill-improvements-anthropic-audit
- [2026-05-24] `queued` [2026-05-24_fix_pi-compatibility-remediation.md](plans/2026-05-24_fix_pi-compatibility-remediation.md) — fix — Pi Compatibility Remediation
- [2026-06-23] `in_progress` [2026-06-23_SEQUENCE_codex-remediation.md](plans/2026-06-23_SEQUENCE_codex-remediation.md) — sequence — Execution Sequence — codex/GPT-5.5 remediation (I-082..I-086)
- [2026-06-23] `queued` [2026-06-23_feature_dispatcher-wiring-transports.md](plans/2026-06-23_feature_dispatcher-wiring-transports.md) — feature — Capability Dispatcher Wiring + Transports
- [2026-06-23] `in_progress` [2026-06-23_fix_config-validation-docs.md](plans/2026-06-23_fix_config-validation-docs.md) — fix — Config Validation & Doc Consistency
- [2026-07-05] `in_progress` [2026-07-05_SEQUENCE_long-running-sessions.md](plans/2026-07-05_SEQUENCE_long-running-sessions.md) — sequence-plan — SEQUENCE — Long-running autonomous sessions
- [2026-07-15] `queued` [2026-07-15_feature_mb-donor-evolution-v5-4-baseline.md](plans/2026-07-15_feature_mb-donor-evolution-v5-4-baseline.md) — feature — mb-donor-evolution — v5.4.0 Trustworthy Baseline
- [2026-09-05] `queued` [2026-09-05_fix_mb-work-cost-diet-sprint2.md](plans/2026-09-05_fix_mb-work-cost-diet-sprint2.md) — fix — mb-work-cost-diet · Sprint 2 «work-loop-diet»
- [2026-09-05] `queued` [2026-09-05_fix_mb-work-cost-diet-sprint3.md](plans/2026-09-05_fix_mb-work-cost-diet-sprint3.md) — fix — mb-work-cost-diet · Sprint 3 «instruction-diet + гигиена»
- [2026-10-05] [plans/2026-10-05_feature_pi-native-integration.md](plans/2026-10-05_feature_pi-native-integration.md) — Pi native Memory Bank integration — Implementation Plan
- [2026-10-07] [plans/2026-10-07_fix_proportional-effortsprint2-execution-economy.md](plans/2026-10-07_fix_proportional-effortsprint2-execution-economy.md) — fix — proportional-effort · Sprint 2 «экономия исполнения: целевые тесты, тон по модели, замер»
- [2026-10-09] [plans/2026-10-09_feature_codex-memory-parity.md](plans/2026-10-09_feature_codex-memory-parity.md) — Codex memory and lifecycle completion
<!-- /mb-active-plans -->

## Recently done (last 10)

<!-- mb-recent-done -->
- 2026-11-19 — [plans/done/2026-11-18_feature_master-completion.md](plans/done/2026-11-18_feature_master-completion.md) — feature — master-completion
- 2026-11-19 — [plans/done/2026-09-24_fix_opus55-prompt-fit.md](plans/done/2026-09-24_fix_opus55-prompt-fit.md) — fix — opus55-prompt-fit · скил под Opus 5.5 / Fable 5.1 и любые агенты
- 2026-11-19 — [plans/done/2026-07-28_fix_graph-semantic-adoption.md](plans/done/2026-07-28_fix_graph-semantic-adoption.md) — fix — graph-semantic-adoption
- 2026-11-18 — [plans/done/2026-10-10_feature_mb-team.md](plans/done/2026-10-10_feature_mb-team.md) — `/mb team` — orchestrator-led parallel tracks
- 2026-11-18 — [plans/done/2026-10-09_fix_codex-global-native-hooks.md](plans/done/2026-10-09_fix_codex-global-native-hooks.md) — fix — codex-global-native-hooks
- 2026-11-18 — [plans/done/2026-05-24_fix_cursor-compatibility-remediation.md](plans/done/2026-05-24_fix_cursor-compatibility-remediation.md) — Cursor Compatibility Remediation
- 2026-11-18 — [plans/done/2026-09-24_fix_command-skill-root-paths.md](plans/done/2026-09-24_fix_command-skill-root-paths.md) — fix — command-skill-root-paths
- 2026-11-17 — [plans/done/2026-11-17_feature_team-shared-gates.md](plans/done/2026-11-17_feature_team-shared-gates.md) — feature — team-shared-gates
- 2026-10-08 — [plans/done/2026-10-08_fix_ordinary-pi-mb-dispatch.md](plans/done/2026-10-08_fix_ordinary-pi-mb-dispatch.md) — Ordinary Pi Memory Bank dispatch
- 2026-10-08 — [plans/done/2026-10-07_fix_upgrade-safe-install.md](plans/done/2026-10-07_fix_upgrade-safe-install.md) — fix — установка поверх старой версии + хвосты I-249…I-254
<!-- /mb-recent-done -->

## Roadmap (high level)

См. [roadmap.md](roadmap.md) (порядок волн, ICE-приоритизация) и [backlog.md](backlog.md) (реестр идей + ADR).
