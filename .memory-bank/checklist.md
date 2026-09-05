
# claude-skill-memory-bank — Чеклист

> **Convention.** Short active list only; hard cap ≤120 lines. Detailed history lives in `progress.md`, `roadmap.md`, and `plans/done/`. Commit hashes, test counts and closeouts belong in `progress.md`, not here.

## 🔄 Active — long-running autonomous sessions (SEQUENCE)

Plan: [plans/2026-07-05_SEQUENCE_long-running-sessions.md](plans/2026-07-05_SEQUENCE_long-running-sessions.md).
Roles: plans by Opus · `/mb work` implement=**sonnet** · review=**codex gpt-5.5** · judge=**opus** (`pipeline.yaml`).

- ⬜ Phase 0 — doc-drift cleanup (no code): status/roadmap still claim dynamic-flow Phase 2 paused; it is DONE on disk
- ✅ Phase 1 — reviewer-2.0 (6/6 tasks) — payload orchestrator + layered rubric examples + strict verdict parse + calibration
- ✅ Phase 2 — work-loop-v2 (5/5 tasks) — trend · contract · pivot · `on_max_cycles` fail-fast · docs
- 🔄 Phase 3 — drive-loop (`/mb drive`), spec `specs/drive-loop/`
  - ✅ Task 1 — `mb-drive.sh next` stateless decision fn (fail-closed; `stop_success` needs green firewall AND 100% acceptance)
  - ✅ Task 2 — `/mb drive` command + AGENTS.md loop-contract (governed: 2 judge-цикла, codex ×3, GO_WITH_BACKLOG I-141…143)
  - ⬜ Task 3 — trend/pivot + route-reeval wiring (stall/last_pivot from the `mb-flow` fence)
  - ✅ Task 4 — stop telemetry + Stop-hook resume-gate + parallel keying (governed: 2 judge-цикла, codex ×2, GO_WITH_BACKLOG I-135…140; fence preserve-on-partial в mb-flow-sync.sh)
  - ⬜ Task 5 — docs
- ⬜ Phase 4 — parallel execution (`parallel-pipeline` + `parallel-team-execution`, on `mb-fanout.sh`)
- ⬜ Phase 5 — cost-multi-model + dynamic-flow Phase 3 (Tasks 13–14: pi/opencode sub-invoke arms)
- ⬜ Phase 6 — documentation: "how to use all of this"

## 🔄 In progress — I-086 config-validation-docs (codex remediation Wave 2)

- ✅ Stage 1 — pipeline validator runtime-block schema + duplicate keys
- ✅ Stage 2 — runtime dup-key loader + pipeline.yaml judge fix
- ⬜ Stage 3–6 — runtime parsers, budget/profile, config split, docs regen

## ⏭ Queued waves

- ⬜ **drive-loop T2+T4** (`/mb drive` + AGENTS.md loop-контракт · stop-телеметрия + Stop-hook resume-gate + parallel keying) — вытащены вперёд очереди ближайшим слотом (AGR-024, искл. из AGR-011); T3+T5 остаются в donor v5.6.0
- 🔄 **Group `sdd-vision-pipeline` (AGR-017, главный трек)** — ▶ волна R 2026-07-19 (goal G-001, роли AGR-023): umbrella T1 ✅ · S1 26/26 DoD, review-цикл 2 (fixer добивает хвосты) · **S2 svp-sdd-core COMPLETE 9/9, DoD 22/22, батарея зелёная — первичное codex-ревью зоны в полёте** · S4 9/9 impl, review-цикл 2 (ABA-blocker в работе) (детали `status.md`, доска COORDINATION); spec-ready база: 3 круга codex-ревью + ремедиация 75/75, батарея 10/10, S9 ревью waived (AGR-022); порядок T1 → S1 → S7 → S4 → S2 → S8 → S9 → S6 → S3 → S5 — детали в `roadmap.md` § Group
- ⬜ W0.5 — [opencode-first-adaptation](plans/2026-05-24_feature_opencode-first-adaptation.md) — OpenCode native plugin, host-agnostic dispatch, hook parity
- ⬜ W1 docs — [skill-improvements-anthropic-audit](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md)
- ⬜ W12 — [parallel-pipeline](plans/2026-05-24_feature_parallel-pipeline.md) → folded into Phase 4 above
- ⏸ [goal-driven-autopilot phase roadmap](plans/2026-05-23_feature_goal-driven-autopilot-phase.md) — superseded by `specs/dynamic-flow/` + the SEQUENCE plan; planning umbrella only

## 🔓 Open backlog

SSOT: [backlog.md](backlog.md). Hot clusters:

- **Cross-agent parity (HIGH):** I-045 (Pi) · I-048/I-049 (OpenCode install+frontmatter) · I-054/I-055/I-056 (dispatch abstraction, hook mapping, plugin-first) · I-061 (Cursor)
- **Cross-agent parity (MED/LOW):** I-046, I-047, I-050..I-053, I-057..I-060
- **Harness chain (from Phases 1–3):** I-095 (DRY-fold) · I-096 (inert cache path) · I-097 (pipeline review_examples wiring) · I-098 (split mb-review.sh) · I-099 (cache-key reconcile) · I-100 (composable `--review` empty loop) · I-101 (traceability `.bats` suffix) · I-102 (mb-drive.sh 455>400 → split)
- **Older:** I-023 (`grep → find` cleanup) · I-062 (EARS validator hardening)

## ✅ Done (detail → `progress.md` · `plans/done/` · `roadmap.md`)

- ✅ spec `openspec-adapter` — T1–T6 implemented (parse+convert+write core, CLI dispatcher, re-import/anchor-map, `--normalize` opt-in LLM layer); commits `0f39618`/`4bebbbc`/`226e65f` — ⬜ one item left: `/mb openspec` router entry in `commands/mb.md` — **deferred, commands/mb.md under adapter-parity FREEZE**, lands when the freeze lifts
- ✅ docs-site + landing refresh — 5/5 stages (MkDocs Material skeleton · 12 new pages · quick-start workflow/pipeline/surfaces blocks · combined Pages deploy `/docs/` · landing first-screen v2 + agreements card) — [plan](plans/2026-07-15_feature_docs-site-and-landing-refresh.md); push pending
- ✅ spec `tier1-graph-memory` — 17/17 tasks, v5.1.0 prepped (PyPI publish + tag pending explicit go)
- ✅ codex remediation Wave 1 — I-082 security-hardening (4 stages) · I-083 verification-gates · I-085 logic-correctness-portability (6 stages)
- ✅ I-087 — session-capture correctness + MB drift hygiene — [plan](plans/2026-07-04_fix_session-capture-and-mb-hygiene.md); follow-ups I-088..I-092
- ✅ I-093 — `/mb work` engine resilience (9 stages: durable state · gated flip · external parse · codex preflight) — [plan](plans/2026-07-04_fix_mb-work-resilience.md)
- ✅ I-094 — safe parallel `/mb work` runs (10 stages: slots · per-run state/budget/claim · baseline diff · locked append) — [plan](plans/2026-07-04_fix_mb-work-parallel-runs.md)
- ✅ install + cross-agent parity — [plan](plans/2026-07-04_fix_install-and-cross-agent-parity.md), Tracks A/B/C complete
- ✅ W3 — handoff-v2 (5/5 tasks, governed dual-review + judge)
- ✅ dynamic-flow Phase 1 + Phase 2 — goal primitive · `mb-flow-sync` fence · THE firewall `mb-flow-verify.sh` · `mb-fanout.sh` · closure wiring
- ✅ cross-session coordination — `references/coordination.md` protocol + `COORDINATION.md` board wiring
- ✅ GraphRAG-lite code context · rule-profiles-and-stack-presets · global-storage (core + agent-support) · sdd-unification · Wave 0 CI baseline

## See also

- `roadmap.md` — full wave order and release gate.
- `status.md` — current phase, active plan inventory, metrics.
- `backlog.md` — open ideas/ADRs (SSOT).
- `traceability.md` — generated REQ coverage matrix.
- `progress.md` — append-only historical log.

<!-- mb-plan:2026-07-18_fix_spec-group-round3-remediation.md -->
## Stage 1: Пакеты находок и ТЗ для 4 фиксеров
- ✅ Пакеты находок и ТЗ для 4 фиксеров

<!-- mb-plan:2026-07-18_fix_spec-group-round3-remediation.md -->
## Stage 2: Волна 1 — F1 owners-state (umbrella + S4) на Opus
- ✅ Волна 1 — F1 owners-state (umbrella + S4) на Opus

<!-- mb-plan:2026-07-18_fix_spec-group-round3-remediation.md -->
## Stage 3: Волна 1 — F2 owners-norms (S2 + S1) на Opus
- ✅ Волна 1 — F2 owners-norms (S2 + S1) на Opus

<!-- mb-plan:2026-07-18_fix_spec-group-round3-remediation.md -->
## Stage 4: Волна 2 — F3 consumers-west (S7 + S3 + S5) на Opus
- ✅ Волна 2 — F3 consumers-west (S7 + S3 + S5) на Opus

<!-- mb-plan:2026-07-18_fix_spec-group-round3-remediation.md -->
## Stage 5: Волна 2 — F4 consumers-east (S6 + S8) на Opus
- ✅ Волна 2 — F4 consumers-east (S6 + S8) на Opus

<!-- mb-plan:2026-07-18_fix_spec-group-round3-remediation.md -->
## Stage 6: Финальный централизованный проход и актуализация банка
- ✅ Финальный централизованный проход и актуализация банка

<!-- mb-plan:2026-07-28_fix_graph-semantic-adoption.md -->
## Stage 1: Nudge v2 — повторяемый и действенный
- ⬜ Nudge v2 — повторяемый и действенный

<!-- mb-plan:2026-07-28_fix_graph-semantic-adoption.md -->
## Stage 2: Bootstrap векторного индекса при `/mb graph --apply`
- ⬜ Bootstrap векторного индекса при `/mb graph --apply`

<!-- mb-plan:2026-07-28_fix_graph-semantic-adoption.md -->
## Stage 3: Auto-catchup графа на SessionStart
- ⬜ Auto-catchup графа на SessionStart

<!-- mb-plan:2026-07-28_fix_graph-semantic-adoption.md -->
## Stage 4: Короткий враппер `mb-graph.sh` + короткие тексты подсказок
- ⬜ Короткий враппер `mb-graph.sh` + короткие тексты подсказок

<!-- mb-plan:2026-07-28_fix_graph-semantic-adoption.md -->
## Stage 5: Статус графа в диспатче субагентов
- ⬜ Статус графа в диспатче субагентов

<!-- mb-plan:2026-09-05_fix_mb-work-cost-diet-sprint1.md -->
## Stage 1: `mb-cost-report.py` — измерение и baseline
- ✅ `mb-cost-report.py` — измерение и baseline (2026-09-05, /mb work run 8bee263e, judge GO_WITH_BACKLOG → I-185)

<!-- mb-plan:2026-09-05_fix_mb-work-cost-diet-sprint1.md -->
## Stage 2: Fast lane без кода — дефолт `execution`, governed opt-in
- ⬜ Fast lane без кода — дефолт `execution`, governed opt-in

<!-- mb-plan:2026-09-05_fix_mb-work-cost-diet-sprint1.md -->
## Stage 3: Бюджет вывода `mb-context.sh`
- ⬜ Бюджет вывода `mb-context.sh`

<!-- mb-plan:2026-09-05_fix_mb-work-cost-diet-sprint1.md -->
## Stage 4: `mb-status-rotate.sh` — ротация `status.md`
- ⬜ `mb-status-rotate.sh` — ротация `status.md`

<!-- mb-plan:2026-09-05_fix_mb-work-cost-diet-sprint1.md -->
## Stage 5: Прунер `checklist.md` под реальную структуру
- ⬜ Прунер `checklist.md` под реальную структуру

<!-- mb-plan:2026-09-05_fix_mb-work-cost-diet-sprint1.md -->
## Stage 6: `mb-coord.sh active` — доска без 200 KB
- ⬜ `mb-coord.sh active` — доска без 200 KB
