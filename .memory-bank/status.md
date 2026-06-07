
# claude-skill-memory-bank: Статус проекта

## Current phase

**Phase 5 — Autonomous agent harness (v5.0.0 target).** Обязательный **Wave 0 — CI baseline** закрыт: `test.yml` на `main` зелёный (`26528106396`, после closeout commit; предыдущий full green `26527319286`) для Ubuntu/macOS × Python 3.11/3.12. Основной roadmap — 12 wave'ов: `harness-upgrade` (reviewer-v2 → work-loop-v2 → handoff-v2 → cost-multi-model → parallel-pipeline) + `goal-driven-autopilot` (overlay+addons → mb-debugger → atomic-commit → goal-layer → worktree-MVP → parallel-waves-MVP → autopilot-loop). Standalone `skill-improvements-anthropic-audit` — docs/evals track после Wave 0, параллельно с W1.

Все промежуточные landings = v4.x bumps. v5.0.0 cut только после закрытия W12. Полная таблица последовательности + ordering rationale + gate criteria → `roadmap.md` секция `## Phase: harness-upgrade + goal-driven-autopilot`.

**Predecessor phases ✅:** sdd-unification (3 sprints), global-storage core + agent-support, rule-profiles-and-stack-presets, GraphRAG-lite code intelligence.

## ⏭ Следующий шаг

**Wave 0 — [CI baseline](plans/done/2026-05-24_fix_ci-baseline-wave-0.md)** закрыт. Следующий operational focus: завершить активный **Cursor compatibility remediation** или стартовать **W0.5 — [OpenCode-first adaptation](plans/2026-05-24_feature_opencode-first-adaptation.md)** как инфраструктурный unlock для W1–W12.

После инфраструктурного unlock: стартовать **W1 code — [reviewer-v2](plans/2026-05-23_feature_reviewer-v2.md)** и **W1 docs — [skill-improvements-anthropic-audit](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md)**. Закрытие каждого wave: `/mb verify` → `/mb done` → plan moves to `plans/done/`.

## Open backlog

- I-062 (MED) — ужесточить EARS-валидатор и spec-checking (per-pattern regex, atomicity, REQ-ID uniqueness, ранний REQ→task lint, traceability drift). Замечено на реальном `/mb discuss` во внешнем проекте. См. `notes/2026-05-29_ears-validator-hardening.md`.
- I-023 (MED) — `grep → find` cleanup в `start.md` / `mb-doctor` (low risk, дешёвый когда дойдут руки)
- I-034 (MED) — plugin-namespaced skill detection в reviewer-resolve
- I-061 (HIGH) — Cursor compatibility remediation: stages 1–6 implemented; bats 38/38 green on cursor suites; pytest pending local env. See `reports/2026-05-24_cursor-compatibility-audit.md`, spec `cursor-extension`.
- I-045 (HIGH) — Pi compatibility remediation: fix docs, sequential fallback in S5 spec, GraphRAG extension decision. See `reports/2026-05-24_pi-compatibility-audit.md`
- I-046 (MED) — `test_pi_adapter.bats` expansion: prompt install, skill content, hook body, MB_PATH propagation tests
- I-047 (MED) — Pi `agents/*.md` global install path (currently only Claude gets agents globally)
- I-048 (HIGH) — OpenCode global skill alias in `install.sh`
- I-049 (HIGH) — Commands frontmatter OpenCode compatibility (`agent`/`subtask` fields)
- I-050 (MED) — OpenCode plugin hooks parity (map bash hooks to TS plugin)
- I-053 (MED) — Cross-agent research note Pi native hooks disclaimer
- I-054 (HIGH) — `scripts/mb-dispatch.sh`: host-agnostic dispatch abstraction. Blocks W1–W12 on OpenCode. See `reports/2026-05-24_plans-specs-opencode-gap-analysis.md` §5.1.
- I-055 (HIGH) — `references/opencode-hooks-mapping.md` + plugin guards (`onBeforeToolExecute`, `experimental.session.compacting`, `onReady`). Blocks W3 handoff-v2 on OpenCode.
- I-056 (HIGH) — OpenCode plugin-first architecture: replace `adapters/opencode/dispatch.sh` bash loop with JS plugin. Blocks W12 parallel-pipeline on OpenCode.
- I-057 (MED) — Model resolver OpenCode probe: `mb-pipeline-model-resolve.sh` should check `.opencode/skills/` and `~/.config/opencode/skills/`. Blocks W4.
- I-058 (MED) — Provider-neutral model aliases: per-host resolution instead of hardcoded Anthropic IDs. Blocks W4 on OpenCode (Kimi defaults).
- I-059 (MED) — OpenCode test fixtures: `test_opencode_*.bats` for dispatch/guards/hooks per wave.
- I-060 (LOW) — Commands `*.md` OpenCode frontmatter for all 24+ command files.

Все HIGH-приоритетные items на момент v4.0.0 ship + audit-remediation: I-045 (Pi), I-048/I-049 (OpenCode inline fixes), I-054/I-055/I-056 (OpenCode structural gaps).

## Ключевые метрики

- VERSION: **4.0.0** (PyPI `memory-bank-skill==4.0.0` план; Homebrew tap bump план)
- Shell-скрипты в `scripts/`: **42**, Python-скрипты в `scripts/`: **9**, Hooks: **10**
- Агенты: **16** (3 utility: manager/doctor/codebase-mapper + 3 verifiers: plan-verifier/rules-enforcer/test-runner + 10 role-agents для `/mb work`: developer/architect/backend/frontend/ios/android/devops/qa/analyst/reviewer)
- Commands: **24** top-level (`/mb` hub + 23 dispatchers)
- Tests: **868** via `PATH="$PWD/.venv/bin:$PATH" bash scripts/mb-test-run.sh --dir . --out json` (`tests_pass=true`); GitHub `test.yml` run `26528106396` passed on Ubuntu/macOS × Python matrix after closeout commit (`26527319286` was the first full green).
- Public website: **https://fockus.github.io/skill-memory-bank/**
- Текущий remote: `origin=https://github.com/fockus/skill-memory-bank.git`

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
- [2026-05-23] `queued` [2026-05-23_feature_handoff-v2.md](plans/2026-05-23_feature_handoff-v2.md) — feature — Plan: feature — Handoff 2.0 (S3 of harness-upgrade)
- [2026-05-23] `queued` [2026-05-23_feature_reviewer-v2.md](plans/2026-05-23_feature_reviewer-v2.md) — feature — Plan: feature — Reviewer 2.0 (S1 of harness-upgrade)
- [2026-05-23] `queued` [2026-05-23_feature_skill-improvements-anthropic-audit.md](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md) — feature — Plan: feature — skill-improvements-anthropic-audit
- [2026-05-23] `queued` [2026-05-23_feature_work-loop-v2.md](plans/2026-05-23_feature_work-loop-v2.md) — feature — Plan: feature — Work loop 2.0 (S2 of harness-upgrade)
- [2026-05-24] `queued` [2026-05-24_feature_parallel-pipeline.md](plans/2026-05-24_feature_parallel-pipeline.md) — feature — Plan: feature — Parallel pipeline (S5 of harness-upgrade)
- [2026-05-23] `paused` [2026-05-23_feature_goal-driven-autopilot-phase.md](plans/2026-05-23_feature_goal-driven-autopilot-phase.md) — feature — Plan: feature — goal-driven-autopilot (Phase roadmap)
- [2026-06-07] [plans/2026-06-07_refactor_rules-context-economy.md](plans/2026-06-07_refactor_rules-context-economy.md) — refactor — rules-context-economy
<!-- /mb-active-plans -->

## Recently done

<!-- mb-recent-done -->
- 2026-05-27 — [plans/done/2026-05-24_fix_ci-baseline-wave-0.md](plans/done/2026-05-24_fix_ci-baseline-wave-0.md) — fix — CI baseline (Wave 0 before Wave 1; latest green `26528106396`)
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
