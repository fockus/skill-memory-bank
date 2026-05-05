# claude-skill-memory-bank — Чеклист

> **Convention.** Этот файл — short list **активных** и недавно завершённых задач. Hard cap **≤120 строк**. Старые спринты живут в `progress.md` (per-day лог) и `roadmap.md "Recently completed"` (per-phase summary). Закрытые планы — в `plans/done/`. Если строки уползли за лимит — архивируй вниз по той же схеме.

## ⏳ In flight

_None._

## ⏭ Next planned

_Skill v2 shipped (v4.0.0). Next iteration TBD — open via `/mb idea` when triggered._

## ✅ Recently completed (last 3 sprints — full history → progress.md)

### v4.0.1 release/CI/docs drift ✅ (2026-05-05) — Plan: [2026-05-05_refactor_release-ci-docs-drift.md](plans/done/2026-05-05_refactor_release-ci-docs-drift.md). Version boundary, shell/Bats regressions, canonical lowercase schema docs, and security closeout matrix. Local verification: shellcheck, ruff, pytest coverage, Bats unit/e2e green. GitHub Actions remains post-push gate.

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
