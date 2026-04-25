# Roadmap

<!-- mb-roadmap-auto -->
## Now (in progress)

_None._

## Next (strict order — depends)

_None._

## Parallel-safe (can run now)

_None._

## Paused / Archived

_None._

## Linked Specs (active)

_None._
<!-- /mb-roadmap-auto -->

_Last updated: auto-synced by mb-roadmap-sync.sh_

## Next intent (prose — not yet a plan file)

Phase 1 ✅ + Phase 2 (Sprint 1+2) ✅ + Phase 3 Sprint 1+2+3 ✅ + Phase 4 Sprint 1+2 ✅ (2026-04-25). Дальше:

1. **⏳ Phase 4 Sprint 3 — superpowers overrides + installer + release**
   - `superpowers:requesting-code-review` skill detection в installer → flip `pipeline.yaml:roles.reviewer.override_if_skill_present`
   - Auto-register all 5 hooks в `~/.claude/settings.json` через `install.sh`
   - SemVer bump + CHANGELOG release section + GitHub release

## Recently completed

- **✅ I-033 — `mb-checklist-prune.sh` + checklist hard-cap enforcement** [2026-04-25]
   - `scripts/mb-checklist-prune.sh` — bash dispatcher + python parser. Collapses fully-✅+plans/done sections to one-liners. Pre-write `.checklist.md.bak.<unix-ts>` backup. Hard-cap warn (>120 lines). Idempotent.
   - Wire-ins: `commands/done.md` step 4, `scripts/mb-plan-done.sh` chain, `scripts/mb-compact.sh --apply`. Best-effort (non-fatal on failure).
   - `tests/pytest/test_mb_checklist_prune.py` (11 cases) + `tests/pytest/test_checklist_cap.py` (CI cap-test enforcing ≤120 lines on repo's own `.memory-bank/checklist.md`).
   - Dogfood: repo checklist re-pruned 39 → 36 lines. pytest 584 → 596 passed (+12). shellcheck `-x` clean.
   - Plan: [plans/done/2026-04-25_refactor_checklist-prune-i033.md](plans/done/2026-04-25_refactor_checklist-prune-i033.md). Closes lessons.md "rotating artifact without enforcement" antipattern (now SHIPPED).

- **✅ Phase 4 Sprint 2 — `--slim`/`--full` end-to-end + sprint_context_guard** [2026-04-25]
   - `scripts/mb-context-slim.py` — prompt trimmer (active stage block + DoD bullets + covers_requirements list + optional `git diff --staged`); falls back к full prompt when stage marker не найден
   - `hooks/mb-context-slim-pre-agent.sh` upgraded to Sprint 2 behavior — при `MB_WORK_MODE=slim` parses prompt for `Plan:`/`Stage:` markers, runs trimmer, emits JSON `hookSpecificOutput.additionalContext` с slim version. Falls open на любой failure.
   - `scripts/mb-session-spend.sh` — companion CLI для session token-spend tracker (init/add/status/check/clear); chars→tokens via /4 estimate; thresholds из `pipeline.yaml:sprint_context_guard`
   - `hooks/mb-sprint-context-guard.sh` — 5-й hook (PreToolUse Task); accumulates prompt+description chars per dispatch, warns at soft threshold, exit 2 (block) на hard threshold
   - `references/hooks.md` обновлён: context-slim section reflects Sprint 2 behavior, добавлен 5-й hook section, combined settings.json snippet включает оба `Task`-matcher hook'а
   - `commands/work.md` — `--slim`/`--full` flag clarification (exports `MB_WORK_MODE` для loop subshell)
   - 32 new tests (9 context-slim + 5 hook-context-slim-upgrade + 7 session-spend + 5 sprint-context-guard + 6 registration). pytest 552 → 584 passed.
   - Plan: [plans/done/2026-04-25_feature_phase4-sprint2-slim-and-context-guard.md](plans/done/2026-04-25_feature_phase4-sprint2-slim-and-context-guard.md)

- **✅ Phase 4 Sprint 1 — 4 critical hooks** [2026-04-25]
   - `hooks/mb-protected-paths-guard.sh` — PreToolUse Write/Edit; blocks writes to `protected_paths` globs unless `MB_ALLOW_PROTECTED=1` (delegates к `mb-work-protected-check.sh`)
   - `hooks/mb-plan-sync-post-write.sh` — PostToolUse Write; chains `mb-plan-sync.sh → mb-roadmap-sync.sh → mb-traceability-gen.sh` для `.md` files под `plans/` или `specs/`. Best-effort.
   - `hooks/mb-ears-pre-write.sh` — PreToolUse Write для `specs/*/requirements.md` или `context/*.md`; runs `mb-ears-validate.sh -` against content; exit 2 на failure.
   - `hooks/mb-context-slim-pre-agent.sh` — PreToolUse Task; advisory note when `MB_WORK_MODE=slim` (Sprint 2 wires actual prompt rewrite).
   - `references/hooks.md` — full installation guide (per-hook section + combined `~/.claude/settings.json` snippet + operational notes).
   - 35 new tests (6 protected-paths + 5 plan-sync + 6 ears-pre-write + 4 context-slim + 14 registration). pytest 517 → 552 passed.
   - Plan: [plans/done/2026-04-25_feature_phase4-sprint1-critical-hooks.md](plans/done/2026-04-25_feature_phase4-sprint1-critical-hooks.md)

- **✅ Phase 3 Sprint 3 — review-loop ядро** [2026-04-25]
   - `scripts/mb-work-review-parse.sh` — strict JSON validator + cross-checks (CHANGES_REQUESTED ⇒ non-empty issues) + `--lenient` Markdown fallback
   - `scripts/mb-work-severity-gate.sh` — applies pipeline.yaml severity_gate to counts (PASS/FAIL exit codes), supports `--counts <json>` / `--counts-stdin` / `--gate <json>` override
   - `scripts/mb-work-budget.sh` — token budget tracker (init / add / status / check / clear), state в `<bank>/.work-budget.json`, exit codes 0/1/2 для ok/warn/stop
   - `scripts/mb-work-protected-check.sh` — matches changed files against `protected_paths` globs с `**` support
   - `agents/mb-reviewer.md` — production-grade review prompt (per-category walk + severity decision tree + strict JSON schema + fix-cycle behavior + hard guardrails)
   - `commands/work.md` — full review-loop wired: implement → protected-check → review (Task) → parse → severity-gate → fix-cycle → verify (plan-verifier) → stage-done; hard stops table для `--auto`
   - 43 new tests (11 review-parse + 9 severity-gate + 8 budget + 6 protected-check + 9 registration). pytest 474 → 517 passed.
   - Plan: [plans/done/2026-04-25_feature_phase3-sprint3-review-loop.md](plans/done/2026-04-25_feature_phase3-sprint3-review-loop.md)

- **✅ Phase 3 Sprint 2 — `/mb work` execution engine + 9 role-agents** [2026-04-25]
   - `scripts/mb-work-resolve.sh` — 5-form target resolver (existing path / substring / topic / freeform / empty active plan)
   - `scripts/mb-work-range.sh` — range parser (N / A-B / A-) с auto-detect уровня (plan→stages / phase→sprints)
   - `scripts/mb-work-plan.sh` — JSON Lines per-stage emitter с role auto-detection (ios/android/frontend/backend/devops/qa/architect/analyst → developer fallback) + `--dry-run` summary header
   - 9 implementer agents (mb-developer / mb-backend / mb-frontend / mb-ios / mb-android / mb-architect / mb-devops / mb-qa / mb-analyst) + 1 reviewer scaffold (mb-reviewer)
   - `commands/work.md` + router в `commands/mb.md`
   - 76 new tests (9 resolver + 9 range + 10 plan-emitter + 40 agents-registration + 8 work-registration). pytest 398 → 474 passed.
   - Plan: [plans/done/2026-04-25_feature_phase3-sprint2-work-engine.md](plans/done/2026-04-25_feature_phase3-sprint2-work-engine.md)

- **✅ Phase 3 Sprint 1 — `/mb config` + `pipeline.yaml`** [2026-04-25]
   - `references/pipeline.default.yaml` — full spec §9 schema (version, roles 11шт, stage_pipeline implement/review/verify, budget, protected_paths 6 паттернов, sprint_context_guard 150k/190k, review_rubric 5 секций, sdd 5 ключей)
   - `scripts/mb-pipeline-validate.sh` — структурный schema-валидатор (yaml-aware, 14 категорий проверок)
   - `scripts/mb-pipeline.sh` — dispatcher init/show/validate/path с idempotency guard и `--force`
   - `commands/config.md` + router в `commands/mb.md`
   - 63 new tests (33 default-shape + 14 validator + 11 dispatcher + 5 registration). pytest 335 → 398 passed.
   - Plan: [plans/done/2026-04-25_feature_phase3-sprint1-config-pipeline.md](plans/done/2026-04-25_feature_phase3-sprint1-config-pipeline.md)

- **✅ Phase 2 Sprint 2 — `/mb sdd` + SDD-lite в `/mb plan`** [2026-04-25]
   - `scripts/mb-sdd.sh` — Kiro-style spec triple `specs/<topic>/{requirements,design,tasks}.md`
   - EARS section copied verbatim из `context/<topic>.md` если существует
   - Idempotency guard + `--force` для overwrite
   - `scripts/mb-plan.sh` `--context <path>` + `--sdd` flags + auto-detect + `## Linked context` секция
   - 18 new tests (7 sdd + 6 plan-sdd-lite + 5 registration). pytest 317 → 335 passed.
   - Plan: [plans/done/2026-04-25_feature_phase2-sprint2-sdd-and-plan-lite.md](plans/done/2026-04-25_feature_phase2-sprint2-sdd-and-plan-lite.md)

- **✅ Phase 2 Sprint 1 — `/mb discuss` + EARS validator + `context/<topic>.md`** [2026-04-25]
   - `commands/discuss.md` — 5-phase interview (Purpose/EARS/NFR/Constraints/Edge)
   - `scripts/mb-ears-validate.sh` — 5 EARS pattern regex validator
   - `scripts/mb-req-next-id.sh` — monotonic REQ-NNN cross-spec generator
   - `context/<topic>.md` template в `references/templates.md`
   - 24 new tests (13 EARS + 6 req-id + 5 registration). pytest 293 → 317 passed.
   - Plan: [plans/done/2026-04-25_feature_phase2-sprint1-discuss-ears.md](plans/done/2026-04-25_feature_phase2-sprint1-discuss-ears.md)

- **✅ Sprint 3 — I-028 fix (multi-active correctness)** [2026-04-25]
   - Маркеры `<!-- mb-plan:<basename> -->` эмитятся sync-скриптом
   - Remove-logic в done-скрипте — plan-scoped по маркеру с backward-compat fallback
   - 4 collision-теста (pytest) + bats fixture v2-rename catch-up (4 файла)
   - pytest 289 → 293 passed; bats 479 → 515 passed
   - Plan: [plans/done/2026-04-25_refactor_sprint3-multi-active-fix.md](plans/done/2026-04-25_refactor_sprint3-multi-active-fix.md)

## Linked Specs (manual notes)

- `specs/mb-skill-v2/` — skill v2 design doc (Phase 1 completed; Phase 2 Sprint 1 done)

## Open high/medium backlog (см. backlog.md)

- I-028 ✅ resolved в Sprint 3 (multi-active marker-based ownership, 2026-04-25)
- I-026 ✅ resolved в Sprint 2 (Phase/Sprint/Task parser)
- I-023 (MED) — grep→find в start.md/mb-doctor

## Roadmap high-level (из specs/mb-skill-v2/design.md §20)

- **Phase 1 — Foundation** ✅ COMPLETE (rename + autosync + traceability-gen infrastructure)
- **Phase 2 — Discussion & SDD artifacts** (Sprint 1: discuss+EARS+context; Sprint 2: /mb sdd + specs/<topic>/ + SDD-lite)
- **Phase 3 — Work engine** (Sprint 1: pipeline.yaml + /mb config; Sprint 2: /mb work + 9 role-agents; Sprint 3: review-loop + severity gates)
- **Phase 4 — Hardening** (Sprint 1: plan-verifier + 4 critical hooks; Sprint 2: --auto/--range/--budget + sprint_context_guard; Sprint 3: superpowers overrides + installer update)

## See also
- traceability.md — REQ coverage matrix (пока "No specs yet", Phase 2 заполнит)
- backlog.md — future ideas & ADR
- checklist.md — current in-flight tasks
- notes/2026-04-22_20-30_sprint3-vs-phase2-priority.md — обоснование порядка Sprint 3 → Phase 2

---

### Legacy content (preserved from the previous plan-file format — review and integrate above)

# claude-skill-memory-bank — План

## Текущий фокус

**v3.0.0 stable + public website live.** Core release уже shipped, а 2026-04-21 для репозитория поднят GitHub Pages лендинг `https://fockus.github.io/skill-memory-bank/`. P0 hardening из full-repo review закрыт: 3 High finding'а покрыты тестами, `mb-compact.sh` снова отвечает только за decay, structural migration возвращён в `mb-migrate-structure.sh`, а installer/adapter surface сокращён перед `v3.1.0`.

После обратной связи внешнего ревью составлен план на 9 этапов через 3 минорных релиза (уточнён 2026-04-20):

- **v2.1 (этапы 1-4):** Auto-capture, drift checkers без AI, PII markers, compaction decay
- **v2.2 (этапы 5-7):** JSONL import, tree-sitter code graph, tags normalization
- **v3.0 (этапы 8-9):** Cross-agent (Cursor/Windsurf/Cline/Kilo/OpenCode/Pi Code/Codex) + repo migration + pipx/PyPI distribution + Homebrew tap
- **v3.1+ backlog:** benchmarks (LongMemEval), sqlite-vec, native memory bridge

Фактический статус по аудиту 2026-04-20:

- ✅ Этапы 1-8 закрыты в `checklist.md`
- 🔄 Этап 8.5 закрыт частично (migration сделана в коде/remote, release continuity ещё не доведена)
- 🔄 Этап 9 закрыт частично (package/docs/workflows готовы, release verification и smoke зелёные, не закрыты final release chores)
- ⬜ Gate v3.0 не выполнен: verification и smoke зелёные, но не завершены final release actions

Полный план: `plans/2026-04-20_refactor_skill-v2.1.md`.

## Active plans

<!-- mb-active-plans -->
<!-- /mb-active-plans -->

## Ближайшие шаги

1. v3.1.2 shipped — no active plans. Next work: v3.2.0 (agents-quality tag, CHANGELOG [3.2.0] already staged), or Stage 8.5 repo-migration cleanup.
2. Optional: Stage 7 `mb-session-recoverer` when user signal arrives.

## Уточнено 2026-04-20

- **Pi Code** = [pi-coding-agent от badlogic](https://github.com/badlogic/pi-mono) — 6-й adapter в Этапе 8; **Codex** добавлен как 7-й adapter (ADR-010)
- **Distribution** — pipx/PyPI primary (наш стек уже 12% Python), Homebrew tap secondary, Anthropic plugin tertiary. npm отменён.
- **Имена**: `memory-bank-skill` на PyPI ✓ свободно, `@fockus/memory-bank` на npm ✓ свободно (reserved на будущее), `fockus/homebrew-tap/memory-bank` создать при release
- **Benchmarks (Этап 10)** отложены в v3.1+ backlog

## Отклонено (после ревью)

- **Hash-based IDs** — решает multi-device конфликты, которых у нас нет (YAGNI)
- **KB compilation (`concepts/`, `connections/`, `qa/`)** — преждевременная иерархия
- **GWT в DoD** — дублирует test requirements в текущем шаблоне плана
- **Schema drift detection** — domain-specific, не fits generic skill
- `**/mb debug`** — дублирует `superpowers:debugging` skill
- **Viewer UI** — chrome over substance
- **REST API / daemon mode** — ломает наше архитектурное преимущество (simplicity, 93% Shell)
- **OpenAI/Cohere embeddings через API** — не деремся, local MiniLM

## Отложено (v3.1+ backlog)

- **sqlite-vec semantic search** — после Gate v3.0, когда keyword+tags+codegraph окажутся insufficient
- **i18n error-сообщений**
- **Native memory bridge** (программная синхронизация с Claude Code auto memory)
- **Viewer dashboard** (если adoption потребует)
