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

<!-- mb-plan:2026-05-21_feature_global-storage.md -->
## global-storage Sprint 1 — ✅ DONE
- ✅ Stages 1-6: resolver contract tests + 6 `_lib.sh` helpers + `mb-init-bank.sh` global flags + `/mb init` UX + runtime docs/rules-only mode + full verification (735 pytest, 119 focused bats, 3 doc-regressions fixed, checklist 181→68 lines). Detail → `plans/2026-05-21_feature_global-storage.md`.

<!-- mb-plan:2026-05-21_feature_global-storage-agent-support.md -->
## global-storage-agent-support Sprint 2 — ✅ DONE
- ✅ Stages 1-6: RED contract test (`test_global_storage_contract.py`, 11 cases) + resolver-aware hooks (3 hooks + git-hooks-fallback honour `MB_PATH`) + adapter matrix (opencode JS plugin, cursor/codex/pi/windsurf/cline/kilo runtime + docs) + Codex global AGENTS embeds TDD/SOLID/Clean Architecture/DRY/KISS/YAGNI/`[MEMORY BANK: ABSENT]` via sed-merge + storage modes docs (SKILL.md/README.md/docs/install.md/docs/cross-agent-setup.md) + E2E suite (`tests/e2e/test_global_storage.bats`, 4 cases). Detail → `plans/2026-05-21_feature_global-storage-agent-support.md`.

<!-- mb-plan:2026-05-21_feature_rule-profiles-and-stack-presets.md -->
## rule-profiles Sprint 3 — ✅ DONE
- ✅ Stages 1-6: profile schema doc + 7 fixtures + RED pytest (26 cases) → `memory_bank_skill/rules_profile.py` + `scripts/mb-profile.sh` CLI (10 bats) → 22 built-in preset JSONs (roles/stacks/architecture/delivery, 12 composition tests) → `mb-rules-check.sh` profile integration (strictness-aware exit, rule_id/profile_source fields, stack-aware checks for go/python/typescript/javascript/java, fsd architecture hint, 8 bats) → `/mb profile` command + `commands/profile.md` + `docs/rule-profiles.md` + README/SKILL.md updates (7 new runtime tests) → CHANGELOG + verification (798 pytest, full bats, ruff clean). Detail → `plans/2026-05-21_feature_rule-profiles-and-stack-presets.md`.

<!-- mb-plan:2026-05-21_refactor_sdd-task-model.md -->
## sdd-task-model Sprint 1 — DONE ✅
- ✅ Stages 1-3: RED tests + `mb_work_items.py` parser (stdlib, JSON Lines CLI) + `mb-sdd.sh` emits new `<!-- mb-task:N -->` format (27/27 sdd+parser tests green, smoke OK). Detail → `plans/2026-05-21_refactor_sdd-task-model.md`.
- ✅ Stages 4-5: `scripts/mb-spec-validate.sh` (12 pytest cases GREEN, shellcheck clean) + Sprint 1 closeout. Sprint 2 (`sdd-work-engine`) unblocked.

<!-- mb-plan:2026-05-21_refactor_sdd-work-engine.md -->
## sdd-work-engine Sprint 2 — DONE ✅
- ✅ Stages 1-6: RED tests + `mb-work-resolve.sh` (Form 3 markers/Form 4 specs candidates) + `mb-work-range.sh` (mb-stage/mb-task auto-detect, mixed-format reject) + `mb-work-plan.sh` refactor (inline parser deleted, uses `mb_work_items.py`, +source/kind/covers/item_no, plan-as-wrapper via linked_spec) + `commands/work.md` Sprint 2 docs + bats. 46/46 work-stack tests GREEN. Sprint 3 (`sdd-traceability-docs`) unblocked.

<!-- mb-plan:2026-05-21_refactor_sdd-traceability-docs.md -->
## sdd-traceability-docs Sprint 3 — queued
- ⬜ Stages 1-5: traceability spec-tasks scan + `mb-spec-tasks-migrate.sh` + docs update + Phase gate. Detail → `plans/2026-05-21_refactor_sdd-traceability-docs.md`.
