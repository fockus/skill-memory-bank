# claude-skill-memory-bank — Чеклист

> **Convention.** Этот файл — short list **активных** и недавно завершённых задач. Hard cap **≤120 строк**. Старые спринты живут в `progress.md` (per-day лог) и `roadmap.md "Recently completed"` (per-phase summary). Закрытые планы — в `plans/done/`. Если строки уползли за лимит — архивируй вниз по той же схеме.

## ⏳ In flight

_None._

## ⏭ Next planned

- **Phase 4 Sprint 3 (financial)** — `superpowers:requesting-code-review` skill detection в installer; auto-register всех 5 hooks через `install.sh`; SemVer release. См. spec §13 + roadmap.

## ✅ Recently completed (last 3 sprints — full history → progress.md)

### Phase 4 Sprint 2 ✅ (2026-04-25) — Plan: [2026-04-25_feature_phase4-sprint2-slim-and-context-guard.md](plans/done/2026-04-25_feature_phase4-sprint2-slim-and-context-guard.md)

### Phase 4 Sprint 1 ✅ (2026-04-25) — Plan: [2026-04-25_feature_phase4-sprint1-critical-hooks.md](plans/done/2026-04-25_feature_phase4-sprint1-critical-hooks.md)

### Phase 3 Sprint 3 ✅ (2026-04-25) — Plan: [2026-04-25_feature_phase3-sprint3-review-loop.md](plans/done/2026-04-25_feature_phase3-sprint3-review-loop.md)

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
