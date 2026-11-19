
# claude-skill-memory-bank — Чеклист

> **Convention.** Short active list only; hard cap ≤100 lines. Detailed history lives in `progress.md`, `roadmap.md`, and `plans/done/`. Commit hashes, test counts and closeouts belong in `progress.md`, not here.

## 🔄 Active — long-running autonomous sessions (SEQUENCE)

Plan: [plans/2026-07-05_SEQUENCE_long-running-sessions.md](plans/2026-07-05_SEQUENCE_long-running-sessions.md).

- ✅ Phases 0–3 — doc-drift cleanup · reviewer-2.0 6/6 · work-loop-v2 5/5 · `/mb drive` (`drive-autopilot` 7/7, drive-loop superseded) — details in `progress.md`
- ⬜ Phase 4 — parallel execution (`parallel-pipeline` + `parallel-team-execution`, on `mb-fanout.sh`)
- ⬜ Phase 5 — cost-multi-model + dynamic-flow Phase 3 (T13–T14 → master-completion Stages 14–15)
- ⬜ Phase 6 — documentation: "how to use all of this"

## 🔄 In progress — I-086 config-validation-docs (codex remediation Wave 2)

- ✅ Stages 1–2 — validator runtime-block schema, dup-key loader, judge fix
- ⬜ Stage 3–6 — runtime parsers, budget/profile, config split, docs regen

## ⏭ Queued waves

- ⬜ **mb-work-cost-diet** — `graph-semantic-adoption` ✅ (2026-11-19) → [Sprint 2](plans/2026-09-05_fix_mb-work-cost-diet-sprint2.md) → [Sprint 3](plans/2026-09-05_fix_mb-work-cost-diet-sprint3.md)
- ⏸ **Group `sdd-vision-pipeline`** (G-001, paused): S7/S8/S4/S5 → master-completion Track F; S1/S2/S3/S6/S9 + umbrella stay in [unfinished-work-completion](plans/2026-11-05_feature_unfinished-work-completion.md); live counters — `roadmap.md` § Group
- ⬜ I-084 — [dispatcher-wiring-transports](plans/2026-06-23_feature_dispatcher-wiring-transports.md) (after I-086) · W1 docs — [skill-improvements-anthropic-audit](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md)

Open backlog SSOT: [backlog.md](backlog.md) (hot: cross-agent parity I-045…I-061, harness chain I-095…I-102). See also `roadmap.md`, `status.md`, `traceability.md`, `progress.md`.

<!-- mb-plan:2026-10-05_feature_pi-native-integration.md -->
## Pi native Memory Bank integration — Implementation Plan — 4/5
- ✅ Stage 1 — Native commands and governed pi-subagents bridge
- ✅ Stage 2 — Project-isolated capture, restore and compaction
- ✅ Stage 3 — Native GraphRAG, vector cache and graph lifecycle
- ✅ Stage 4 — Native guard hooks and synchronization
- ⬜ Stage 5 — Safe installation and real Pi acceptance

<!-- mb-plan:2026-10-07_fix_proportional-effortsprint2-execution-economy.md -->
## proportional-effort · Sprint 2 «экономия исполнения: целевые тесты, тон по модели, замер» — 3/4
- ✅ Stage 1 — Целевой прогон тестов
- ✅ Stage 2 — Пропорциональная проверка в агентах и `/mb work`
- ✅ Stage 3 — Тон по силе модели
- ⬜ Stage 4 — Замер на боевых задачах

<!-- mb-plan:2026-10-09_feature_codex-memory-parity.md -->
## Codex memory and lifecycle completion — 1/4
- ⬜ Stage 1 — Durable model-free Codex session memory
- ✅ Stage 2 — Preserve graph file identity
- ⬜ Stage 3 — Native child context and bounded lifecycle wiring
- ⬜ Stage 4 — Native proof, review and documentation

<!-- mb-plan:2026-11-18_feature_master-completion.md -->
## master-completion — 21/22
- ✅ Stage 1 — Bookkeeping close-out of already-shipped work
- ✅ Stage 2 — Graph nudge that suggests useful queries, per-subagent budget
- ✅ Stage 3 — Graph share in the cost report
- ✅ Stage 4 — Make room in `commands/work.md`
- ✅ Stage 5 — Graph context pushed into every `/mb work` dispatch
- ✅ Stage 6 — Graph status on ad-hoc dispatch; Pi graph test fixture
- ✅ Stage 7 — Graph adoption demo and measurement
- ✅ Stage 8 — OpenSpec contract decisions; import keeps what export needs
- ✅ Stage 9 — OpenSpec export and three-way sync
- ✅ Stage 10 — `/mb work` over an OpenSpec change; docs
- ✅ Stage 11 — mb-team review until clean
- ✅ Stage 12 — Split `commands/mb.md` for Opus 5.5 / Fable
- ✅ Stage 13 — Opus 5.5 / Fable acceptance run
- ✅ Stage 14 — dynamic-flow T13 — Pi and OpenCode sub-invoke
- ✅ Stage 15 — dynamic-flow T14 — critique, risk-find, final-report skills
- ✅ Stage 16 — Close S7 svp-brief and S8 svp-contract-test-loop (shipped, unticked)
- ✅ Stage 17 — S4 svp-roadmap-backlog-db remainder
- ✅ Stage 18 — S5 svp-adapt-escalation — rebaseline on ADaPT-lite and remainder
- ⬜ Stage 19 — Final verification and bank sync
- ✅ Stage 20 — Pi keeps working until the task is done (settle-resume gate)
- ✅ Stage 21 — pi-dynamic-workflows — borrow now, spike as an optional Pi accelerator
- ✅ Stage 22 — Graph sees tests through shell entry points and argparse dispatch (I-297)

<!-- mb-plan:tasks.md -->
## svp-adapt-escalation — 5/5
- ✅ Stage 1 — ADaPT-lite baseline (delivered, waiver with commit link)
- ✅ Stage 2 — Remaining guards and thresholds in adapt-check
- ✅ Stage 3 — Escalation journal, cascade stop and run summary
- ✅ Stage 4 — Stub gate in verify (verify-stub)
- ✅ Stage 5 — Autonomous stub path and backlog chain

