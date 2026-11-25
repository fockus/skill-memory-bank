
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

<!-- mb-plan:2026-11-24_feature_project-code-rag.md -->
## project-code-rag — 1/1
- ✅ Stage 1 — Ship both providers and the project setup/search lifecycle

<!-- mb-plan:2026-11-25_feature_agent-retrieval-routing.md -->
## agent-retrieval-routing — 2/2
- ✅ Stage 1 — Wire retrieval options through real agent entry points and verify their use
- ✅ Stage 2 — Project onboarding and actionable release notices (AGR-113)

<!-- mb-plan:2026-11-25_feature_bounded-rag-refresh.md -->
## bounded-rag-refresh — 1/1
- ✅ Stage 1 — Bounded incremental refresh for an enrolled worktree
