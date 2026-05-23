# claude-skill-memory-bank: Статус проекта

## Current phase

**Phase 5 — Autonomous agent harness (v5.0.0 target).** Roadmap зафиксирован 2026-05-24 как последовательность из 12 wave'ов, объединяющая `harness-upgrade` (reviewer-v2 → work-loop-v2 → handoff-v2 → cost-multi-model → parallel-pipeline) с `goal-driven-autopilot` (overlay+addons → mb-debugger → atomic-commit → goal-layer → worktree-MVP → parallel-waves-MVP → autopilot-loop). Параллельно с W1+W2 идёт standalone `skill-improvements-anthropic-audit` (docs/evals track).

Все промежуточные landings = v4.x bumps. v5.0.0 cut только после закрытия W12. Полная таблица последовательности + ordering rationale + gate criteria → `roadmap.md` секция `## Phase: harness-upgrade + goal-driven-autopilot`.

**Predecessor phases ✅:** sdd-unification (3 sprints), global-storage core + agent-support, rule-profiles-and-stack-presets, GraphRAG-lite code intelligence.

## ⏭ Следующий шаг

**Wave 1 — harness-upgrade S1 [reviewer-v2](plans/2026-05-23_feature_reviewer-v2.md)** (code track) **+** standalone [skill-improvements-anthropic-audit](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md) (docs track, parallel-safe).

Pre-flight: при старте reviewer-v2 поставить `status: in_progress` во frontmatter и прогнать `mb-roadmap-sync.sh` чтобы автосинк-блок начал отражать состояние. Закрытие каждого wave: `/mb verify` → `/mb done` → plan moves to `plans/done/`.

## Open backlog

- I-023 (MED) — `grep → find` cleanup в `start.md` / `mb-doctor` (low risk, дешёвый когда дойдут руки)
- I-034 (MED) — plugin-namespaced skill detection в reviewer-resolve

Все HIGH-приоритетные items закрыты на момент v4.0.0 ship + audit-remediation. Восстановить через `/mb idea` если регрессия обнаружится.

## Ключевые метрики

- VERSION: **4.0.0** (PyPI `memory-bank-skill==4.0.0` план; Homebrew tap bump план)
- Shell-скрипты в `scripts/`: **42**, Python-скрипты в `scripts/`: **9**, Hooks: **10**
- Агенты: **16** (3 utility: manager/doctor/codebase-mapper + 3 verifiers: plan-verifier/rules-enforcer/test-runner + 10 role-agents для `/mb work`: developer/architect/backend/frontend/ios/android/devops/qa/analyst/reviewer)
- Commands: **24** top-level (`/mb` hub + 23 dispatchers)
- Tests: **708** via `PATH="$PWD/.venv/bin:$PATH" bash scripts/mb-test-run.sh --dir . --out json` (`tests_pass=true`); GraphRAG focused pytest 40 passed; bats GraphRAG/rules 17 ok; Pi/OpenCode/Codex install filter 9 ok; scoped shellcheck/ruff clean
- Public website: **https://fockus.github.io/skill-memory-bank/**
- Текущий remote: `origin=https://github.com/fockus/skill-memory-bank.git`

## Active plans

<!-- mb-active-plans -->
- [2026-05-23] [plans/2026-05-23_feature_reviewer-v2.md](plans/2026-05-23_feature_reviewer-v2.md) — feature — Reviewer 2.0 (S1 of harness-upgrade)
- [2026-05-23] [plans/2026-05-23_feature_goal-driven-autopilot-phase.md](plans/2026-05-23_feature_goal-driven-autopilot-phase.md) — feature — goal-driven-autopilot (Phase roadmap)
- [2026-05-23] [plans/2026-05-23_feature_goal-driven-autopilot-sprint-1-prompt-overlay.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-1-prompt-overlay.md) — feature — goal-driven-autopilot — Sprint 1: Prompt overlay + addons
- [2026-05-23] [plans/2026-05-23_feature_work-loop-v2.md](plans/2026-05-23_feature_work-loop-v2.md) — feature — Work loop 2.0 (S2 of harness-upgrade)
- [2026-05-23] [plans/2026-05-23_feature_handoff-v2.md](plans/2026-05-23_feature_handoff-v2.md) — feature — Handoff 2.0 (S3 of harness-upgrade)
- [2026-05-23] [plans/2026-05-23_feature_cost-multi-model.md](plans/2026-05-23_feature_cost-multi-model.md) — feature — Cost (multi-model role assignment, S4 of harness-upgrade)
- [2026-05-23] [plans/2026-05-23_feature_goal-driven-autopilot-sprint-2-mb-debugger.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-2-mb-debugger.md) — feature — goal-driven-autopilot — Sprint 2: mb-debugger + `/mb debug`
- [2026-05-23] [plans/2026-05-23_feature_goal-driven-autopilot-sprint-3-worktree.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-3-worktree.md) — feature — goal-driven-autopilot — Sprint 3: Worktree isolation
- [2026-05-23] [plans/2026-05-23_feature_goal-driven-autopilot-sprint-4-atomic-commit.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-4-atomic-commit.md) — feature — goal-driven-autopilot — Sprint 4: Atomic commit per stage
- [2026-05-23] [plans/2026-05-23_feature_goal-driven-autopilot-sprint-5-parallel-waves.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-5-parallel-waves.md) — feature — goal-driven-autopilot — Sprint 5: Parallel waves (DAG)
- [2026-05-23] [plans/2026-05-23_feature_goal-driven-autopilot-sprint-6-goal-layer.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-6-goal-layer.md) — feature — goal-driven-autopilot — Sprint 6: Goal layer + `/goal`
- [2026-05-23] [plans/2026-05-23_feature_goal-driven-autopilot-sprint-7-autopilot.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-7-autopilot.md) — feature — goal-driven-autopilot — Sprint 7: Autopilot loop
- [2026-05-23] [plans/2026-05-23_feature_skill-improvements-anthropic-audit.md](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md) — feature — skill-improvements-anthropic-audit
- [2026-05-24] [plans/2026-05-24_feature_parallel-pipeline.md](plans/2026-05-24_feature_parallel-pipeline.md) — feature — Parallel pipeline (S5 of harness-upgrade)
<!-- /mb-active-plans -->

## Recently done

<!-- mb-recent-done -->
- 2026-05-24 — [plans/done/2026-05-21_feature_rule-profiles-and-stack-presets.md](plans/done/2026-05-21_feature_rule-profiles-and-stack-presets.md) — feature — rule-profiles-and-stack-presets
- 2026-05-24 — [plans/done/2026-05-21_feature_global-storage-agent-support.md](plans/done/2026-05-21_feature_global-storage-agent-support.md) — feature — global-storage-agent-support
- 2026-05-24 — [plans/done/2026-05-21_feature_global-storage.md](plans/done/2026-05-21_feature_global-storage.md) — feature — global-storage-core
- 2026-05-23 — [plans/done/2026-05-21_refactor_sdd-traceability-docs.md](plans/done/2026-05-21_refactor_sdd-traceability-docs.md) — refactor — sdd-traceability-docs
- 2026-05-23 — [plans/done/2026-05-21_refactor_sdd-work-engine.md](plans/done/2026-05-21_refactor_sdd-work-engine.md) — refactor — sdd-work-engine
- 2026-05-23 — [plans/done/2026-05-21_refactor_sdd-task-model.md](plans/done/2026-05-21_refactor_sdd-task-model.md) — refactor — sdd-task-model
- 2026-05-21 — [plans/done/2026-05-21_architecture_graph-rag-lite-code-context.md](plans/done/2026-05-21_architecture_graph-rag-lite-code-context.md) — architecture — graph-rag-lite-code-context
- 2026-04-27 — [plans/done/2026-04-25_refactor_v4-audit-remediation.md](plans/done/2026-04-25_refactor_v4-audit-remediation.md) — refactor — v4-audit-remediation
<!-- /mb-recent-done -->

---

## Архив — Released gates (passed ✅)

| Release | Date | Highlights |
|---------|------|------------|
| **v4.0.0** | 2026-04-25 | Skill v2 refactor: pipeline.yaml + `/mb work` + 10 role-agents + review-loop + 5 hooks + checklist hard-cap. Tests 335 → 596+ → 638. |
| **v3.1.2** | 2026-04-21 | Review-hardening + installer-boundaries + core-files-v3-1 + agents-quality. PyPI/Homebrew sync. |
| **v3.1.0/1** | 2026-04-21 | `/mb compact`, `/mb tags`, `/mb import`, GitHub Pages landing |
| **v3.0.0** | 2026-04-20 | 7 cross-agent adapters (Cursor/Windsurf/Cline/Kilo/OpenCode/Pi/Codex), pipx/PyPI distribution, Homebrew tap |
| **v2.1.0** | 2026 | Auto-capture, drift checkers без AI, `<private>` PII redaction, compaction decay |
| **v2.0.0** | 2026 | Language-agnostic stack detection, CI integration, TDD-based workflow |

Полные details — `plans/done/`, `progress.md` (per-day), `lessons.md` (recurring patterns).

## Архив — Решённые вопросы (исторически)

- ✅ Pi Code остаётся adapter'ом Stage 8; Codex добавлен как 7-й adapter (ADR-010)
- ✅ Distribution strategy: pipx/PyPI primary, Homebrew secondary, Anthropic plugin tertiary
- ✅ Benchmarks (LongMemEval) перенесены в backlog
- ✅ Merge `v2.2.0` absorbed в `3.0.0-rc1` (formal cut пропущен)
- ✅ Старый repo `claude-skill-memory-bank` оставлен как archive remote; canonical = `skill-memory-bank`

## Backlog (next iteration ideas)

- Benchmarks (LongMemEval + custom scenarios)
- sqlite-vec semantic search
- i18n error-сообщений
- Native memory bridge (программная синхронизация с Claude Code auto memory)
- Viewer dashboard (если adoption потребует)
