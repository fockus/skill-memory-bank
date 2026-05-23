# claude-skill-memory-bank — Чеклист

> **Convention.** Short active list only; hard cap ≤120 lines. Detailed history lives in `progress.md`, `roadmap.md`, and `plans/done/`.

## ⏳ In flight

<!-- mb-plan:2026-05-24_fix_ci-baseline-wave-0.md -->
### Wave 0 — CI baseline before Wave 1
- ⬜ Stage 1: Casing — `BACKLOG.md` → `backlog.md` in affected tests
- ⬜ Stage 2: Init-bank scaffold expectations — lowercase core files + `roadmap.md`
- ⬜ Stage 3: Go-skip TAP format on macOS
- ⬜ Stage 4: Real bugs — compact / context --deep / drift / research / file-change-log
- ⬜ Stage 5: GraphRAG adapter regressions
- ⬜ Stage 6: CI green + verify on PR

## ⏭ Queued waves after Wave 0

- ⬜ W1 code — [reviewer-v2](plans/2026-05-23_feature_reviewer-v2.md)
- ⬜ W1 docs — [skill-improvements-anthropic-audit](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md)
- ⬜ W2 — [work-loop-v2](plans/2026-05-23_feature_work-loop-v2.md)
- ⬜ W3 — [handoff-v2](plans/2026-05-23_feature_handoff-v2.md)
- ⬜ W4 — [cost-multi-model](plans/2026-05-23_feature_cost-multi-model.md)
- ⬜ W5 — [goal-driven-autopilot sprint 1](plans/2026-05-23_feature_goal-driven-autopilot-sprint-1-prompt-overlay.md)
- ⬜ W6 — [goal-driven-autopilot sprint 2](plans/2026-05-23_feature_goal-driven-autopilot-sprint-2-mb-debugger.md)
- ⬜ W7 — [goal-driven-autopilot sprint 4](plans/2026-05-23_feature_goal-driven-autopilot-sprint-4-atomic-commit.md)
- ⬜ W8 — [goal-driven-autopilot sprint 6](plans/2026-05-23_feature_goal-driven-autopilot-sprint-6-goal-layer.md)
- ⬜ W9 — [goal-driven-autopilot sprint 3](plans/2026-05-23_feature_goal-driven-autopilot-sprint-3-worktree.md)
- ⬜ W10 — [goal-driven-autopilot sprint 5](plans/2026-05-23_feature_goal-driven-autopilot-sprint-5-parallel-waves.md)
- ⬜ W11 — [goal-driven-autopilot sprint 7](plans/2026-05-23_feature_goal-driven-autopilot-sprint-7-autopilot.md)
- ⬜ W12 — [parallel-pipeline](plans/2026-05-24_feature_parallel-pipeline.md)

## 🧭 Roadmap-only / paused

- ⏸ [goal-driven-autopilot phase roadmap](plans/2026-05-23_feature_goal-driven-autopilot-phase.md) — planning umbrella only; execute sprint plans, not this phase wrapper.

## ✅ Recently completed

- ✅ GraphRAG-lite code context — [plan](plans/done/2026-05-21_architecture_graph-rag-lite-code-context.md), verify PASS with rules-check 0 violations, focused pytest 40 passed, bats 17+9 ok, full `mb-test-run` 708 passed.
- ✅ rule-profiles-and-stack-presets — [plan](plans/done/2026-05-21_feature_rule-profiles-and-stack-presets.md), 22 presets + profile CLI + rules-check integration.
- ✅ global-storage-agent-support — [plan](plans/done/2026-05-21_feature_global-storage-agent-support.md), resolver-aware hooks/adapters + E2E coverage.
- ✅ global-storage-core — [plan](plans/done/2026-05-21_feature_global-storage.md), resolver contract + global/local/rules-only semantics.
- ✅ sdd-unification — [task model](plans/done/2026-05-21_refactor_sdd-task-model.md), [work engine](plans/done/2026-05-21_refactor_sdd-work-engine.md), [traceability docs](plans/done/2026-05-21_refactor_sdd-traceability-docs.md).

## 🔓 Open backlog hot list

- I-023 (MED) — `grep → find` cleanup in `start.md` / `mb-doctor`.

## See also

- `roadmap.md` — full wave order and release gate.
- `status.md` — current phase, active plan inventory, metrics.
- `traceability.md` — generated REQ coverage matrix.
- `progress.md` — append-only historical log.
