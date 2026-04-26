# claude-skill-memory-bank: Статус проекта

## Current phase

**v4.0.0 — RELEASED (2026-04-25). Audit-remediation план `refactor — v4-audit-remediation` закрыт 2026-04-27 (Stages 1-7 ✅).**

Skill v2 architectural refactor завершён: `pipeline.yaml`-driven engine, `/mb config` + `/mb work`, 9 role-agents + reviewer + verifier, severity-gated review-loop, 5 critical Claude Code hooks, prompt-trimming `--slim` mode, sprint context guard, checklist hard-cap enforcement, installer auto-registration с `superpowers:requesting-code-review` skill detection. Post-release: I-004 ships `scripts/mb-auto-commit.sh` (opt-in `MB_AUTO_COMMIT=1`).

Полный аудит skill'а проведён 2026-04-25 — обнаружено 7 групп drift (doc counts, status own-state, git hygiene, flaky tests, code-quality, security hardening, terminology canonicalization). Активный план закрывает все семь.

## ⏭ Следующий шаг

Audit-remediation закрыт. Следующая итерация — TBD (`/mb idea` при появлении сигнала). Кандидаты: refresh of legacy `plan.md` фикстур в bats тестах (11 pre-existing fails); Pi-mode skill telemetry; multi-language code graph extraction polish.

## Open backlog

- I-023 (MED) — `grep → find` cleanup в `start.md` / `mb-doctor` (low risk, дешёвый когда дойдут руки)
- I-034 (MED) — plugin-namespaced skill detection в reviewer-resolve

Все HIGH-приоритетные items закрыты на момент v4.0.0 ship + audit-remediation. Восстановить через `/mb idea` если регрессия обнаружится.

## Ключевые метрики

- VERSION: **4.0.0** (PyPI `memory-bank-skill==4.0.0` план; Homebrew tap bump план)
- Shell-скрипты: **41**, Python-скрипты: **4**, Hooks: **9**
- Агенты: **16** (3 utility: manager/doctor/codebase-mapper + 3 verifiers: plan-verifier/rules-enforcer/test-runner + 10 role-agents для `/mb work`: developer/architect/backend/frontend/ios/android/devops/qa/analyst/reviewer)
- Commands: **24** top-level (`/mb` hub + 23 dispatchers)
- Tests: **pytest 663** (3 consecutive runs × 0 flake post-Stage-7), bats 532 ok / 11 pre-existing fails (legacy `plan.md` fixtures, separate refactor), shellcheck/ruff clean
- Public website: **https://fockus.github.io/skill-memory-bank/**
- Текущий remote: `origin=https://github.com/fockus/skill-memory-bank.git`

## Active plans

<!-- mb-active-plans -->
<!-- /mb-active-plans -->

## Recently done

<!-- mb-recent-done -->
- 2026-04-27 — [plans/done/2026-04-25_refactor_v4-audit-remediation.md](plans/done/2026-04-25_refactor_v4-audit-remediation.md) — refactor — v4-audit-remediation
- 2026-04-21 — [plans/done/2026-04-21_refactor_core-files-v3-1.md](plans/done/2026-04-21_refactor_core-files-v3-1.md) — refactor — core-files-v3-1
- 2026-04-21 — [plans/done/2026-04-21_refactor_review-hardening-installer-boundaries.md](plans/done/2026-04-21_refactor_review-hardening-installer-boundaries.md) — refactor — review-hardening-installer-boundaries
- 2026-04-21 — [plans/done/2026-04-21_refactor_agents-quality.md](plans/done/2026-04-21_refactor_agents-quality.md) — refactor — agents-quality
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
