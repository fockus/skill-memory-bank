
# claude-skill-memory-bank — Чеклист

> **Convention.** Short active list only; hard cap ≤100 lines. Detailed history lives in `progress.md`, `roadmap.md`, and `plans/done/`. Commit hashes, test counts and closeouts belong in `progress.md`, not here.

## 🔄 Active — long-running autonomous sessions (SEQUENCE)

Plan: [plans/2026-07-05_SEQUENCE_long-running-sessions.md](plans/2026-07-05_SEQUENCE_long-running-sessions.md).
Roles: plans by Opus · `/mb work` implement=**sonnet** · review=**codex gpt-5.6-sol** · judge=**opus** (`pipeline.yaml`).

- ✅ Phase 0 — doc-drift cleanup (no code): status/roadmap still claim dynamic-flow Phase 2 paused; it is DONE on disk — закрыто `/mb doctor` 2026-09-13
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

- ⬜ **Fix-слайс по ревью Sprint 1** (судья NO_GO 2026-09-13, [отчёт](reports/2026-09-13_sprint1-review.md)): I-194 · I-195 · I-196 — HIGH, точечные правки; I-208 — HIGH, 22 предсуществующих + 11 средовых красных тестов. Плана ещё нет
- ⬜ **mb-work-cost-diet** — `graph-semantic-adoption` (блок ниже, пререквизит по AGR-044) → [Sprint 2](plans/2026-09-05_fix_mb-work-cost-diet-sprint2.md) → [Sprint 3](plans/2026-09-05_fix_mb-work-cost-diet-sprint3.md)
- ⏸ **Group `sdd-vision-pipeline`** (AGR-017, goal G-001, пауза с 2026-07-27): S1 ✅ 6/6 · S2 ✅ 9/9 · S7 2/4 · S4 3/9 · S8 3/8 (по T7/T8 есть коммиты, судьи не было) · S9 2/5 · S6/S3/S5 не начаты; порядок AGR-029; живые счётчики — `roadmap.md` § Group
- ⬜ openspec-adapter — последний пункт: строка `/mb openspec` в `commands/mb.md` (заморозка файла снята AGR-033)
- ⬜ cursor-extension Task 9 — hook-rename sync после handoff-v2 ([план](plans/2026-05-24_fix_cursor-compatibility-remediation.md) 20/23)
- ⬜ I-084 — [dispatcher-wiring-transports](plans/2026-06-23_feature_dispatcher-wiring-transports.md) (после I-086)
- ⬜ W1 docs — [skill-improvements-anthropic-audit](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md)

## 🔓 Open backlog

SSOT: [backlog.md](backlog.md). Hot clusters:

- **Cross-agent parity (HIGH):** I-045 (Pi) · I-048/I-049 (OpenCode install+frontmatter) · I-054/I-055/I-056 (dispatch abstraction, hook mapping, plugin-first) · I-061 (Cursor)
- **Cross-agent parity (MED/LOW):** I-046, I-047, I-050..I-053, I-057..I-060
- **Harness chain (from Phases 1–3):** I-095 (DRY-fold) · I-096 (inert cache path) · I-097 (pipeline review_examples wiring) · I-098 (split mb-review.sh) · I-099 (cache-key reconcile) · I-100 (composable `--review` empty loop) · I-101 (traceability `.bats` suffix) · I-102 (mb-drive.sh 455>400 → split)
- **Older:** I-023 (`grep → find` cleanup) · I-062 (EARS validator hardening)

## See also

- `roadmap.md` — full wave order and release gate.
- `status.md` — current phase, active plan inventory, metrics.
- `backlog.md` — open ideas/ADRs (SSOT).
- `traceability.md` — generated REQ coverage matrix.
- `progress.md` — append-only historical log.

<!-- mb-plan:2026-07-28_fix_graph-semantic-adoption.md -->
## graph-semantic-adoption — 0/7
- ⬜ Stage 1 — Nudge v2 — повторяемый и действенный
- ⬜ Stage 2 — Bootstrap векторного индекса при `/mb graph --apply`
- ⬜ Stage 3 — Auto-catchup графа на SessionStart
- ⬜ Stage 4 — Короткий враппер `mb-graph.sh` + короткие тексты подсказок
- ⬜ Stage 5 — Статус графа в диспатче субагентов
- ⬜ Stage 6 — Покрытие — bash и bats в графе
- ⬜ Stage 7 — Граф в каждом диспатче `/mb work` + замер adoption

