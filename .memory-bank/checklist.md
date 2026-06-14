
# claude-skill-memory-bank — Чеклист

> **Convention.** Short active list only; hard cap ≤120 lines. Detailed history lives in `progress.md`, `roadmap.md`, and `plans/done/`.

## ✅ Done — spec: tier1-graph-memory (17/17)

_Governed `/mb work`: implement (Opus) → verify → DUAL review (Codex gpt-5.5 + main-agent) → judge (GO/GO_WITH_BACKLOG/NO_GO) → fix loop ≤2 then judge_decides. Spec COMPLETE 2026-06-14; 5.1.0 prepped (PyPI publish + git tag pending explicit go)._

- ✅ Task 1 — RRF fusion module (c015831)
- ✅ Task 2 — RRF auto default (491b717)
- ✅ Task 3 — import-aware call binding (21ba225)
- ✅ Task 4 — PageRank god-nodes signal (ca6a358 + f5e0d15)
- ✅ Task 5 — git churn signal (74f14a1)
- ✅ Task 6 — community retrieval (3434cb3)
- ✅ Task 7 — per-turn capture ok|err + diffstat (a0d6711)
- ✅ Task 8 — summary schema v2 (e1bbff1)
- ✅ Task 9 — progressive-disclosure recall + RRF fusion (5a041d2)
- ✅ Task 10 — `/mb recap <sid>` (8c8d900)
- ✅ Task 11 — `/mb conflicts` Jaccard + negation finder (b365e59)
- ✅ Task 12 — `/mb consolidate` $0 session fold (73a095e)
- ✅ Task 13 — [SUPERSEDED] convention + drift checker (7ba7174)
- ✅ Task 14 — `--sessions` graph layer (4bca7f6)
- ✅ Task 15 — wiki staleness-aware incremental rebuild (1e94d6d)
- ✅ Task 16 — deterministic wiki Decisions section (0ac97f2)
- ✅ Task 17 — tier1 docs + 5.1.0 release prep (8ff17bb)
- ✅ Release-gated backlog fixes — I-069 (07221e9), I-066+I-067 (306835a)

_Wave queues unchanged below._

## ⏭ Queued waves after Wave 0

- ⬜ W0.5 — [opencode-first-adaptation](plans/2026-05-24_feature_opencode-first-adaptation.md) — OpenCode native plugin, host-agnostic dispatch, hook parity (cross-cutting infrastructure for W1–W12)
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

- ✅ Wave 0 CI baseline — [plan](plans/done/2026-05-24_fix_ci-baseline-wave-0.md), GitHub `test.yml` run `26528106396` green after closeout commit; first full green was `26527319286`.
- ✅ OpenCode integration audit — `adapters/opencode.sh` contract fixed (top-level hooks, `directory` param, auto-discovery, cleanup), tests 15/15 passed. Full audit report: [reports/2026-05-24_opencode-integration-audit.md](reports/2026-05-24_opencode-integration-audit.md).
- ✅ GraphRAG-lite code context — [plan](plans/done/2026-05-21_architecture_graph-rag-lite-code-context.md), verify PASS with rules-check 0 violations, focused pytest 40 passed, bats 17+9 ok, full `mb-test-run` 708 passed.
- ✅ rule-profiles-and-stack-presets — [plan](plans/done/2026-05-21_feature_rule-profiles-and-stack-presets.md), 22 presets + profile CLI + rules-check integration.
- ✅ global-storage-agent-support — [plan](plans/done/2026-05-21_feature_global-storage-agent-support.md), resolver-aware hooks/adapters + E2E coverage.
- ✅ global-storage-core — [plan](plans/done/2026-05-21_feature_global-storage.md), resolver contract + global/local/rules-only semantics.
- ✅ sdd-unification — [task model](plans/done/2026-05-21_refactor_sdd-task-model.md), [work engine](plans/done/2026-05-21_refactor_sdd-work-engine.md), [traceability docs](plans/done/2026-05-21_refactor_sdd-traceability-docs.md).

## 🔓 Open backlog hot list

- I-023 (MED) — `grep → find` cleanup in `start.md` / `mb-doctor`.
- I-061 (HIGH) — Cursor compatibility remediation: spec `cursor-extension` (REQ-300..REQ-324), plan `cursor-compatibility-remediation.md` queued. See `reports/2026-05-24_cursor-compatibility-audit.md`.
- I-045 (HIGH) — Pi compatibility remediation: spec `pi-extension` created (REQ-200..REQ-222), plan `pi-compatibility-remediation.md` queued. Next: implement extension (Stages 1-6).
- I-046 (MED) — `test_pi_adapter.bats` expansion: prompt install, skill content, hook body, MB_PATH propagation tests.
- I-047 (MED) — Pi `agents/*.md` global install path (currently only Claude gets agents globally).
- I-048 (HIGH) — OpenCode global skill alias in `install.sh` (~/.config/opencode/skills/memory-bank symlink).
- I-049 (HIGH) — Commands `*.md` frontmatter: add OpenCode `agent`/`subtask` fields (or generic `role:`).
- I-050 (MED) — OpenCode plugin hooks parity: map bash hooks (`mb-protected-paths-guard`, `mb-plan-sync-post-write`, etc.) to TS plugin.
- I-051 (LOW) — OpenCode agent definitions (`agents/opencode/*.md`).
- I-052 (LOW) — Tests: add `node --check` for generated OpenCode plugin JS.
- I-053 (MED) — Cross-agent research note fix: Pi native hooks disclaimer (`notes/2026-04-20_03-36_cross-agent-research.md`).
- I-054 (HIGH) — `scripts/mb-dispatch.sh`: host-agnostic dispatch abstraction (Task/opencode run/codex run/pi run). Blocks W1–W12 on OpenCode. See `reports/2026-05-24_plans-specs-opencode-gap-analysis.md` §5.1.
- I-055 (HIGH) — `references/opencode-hooks-mapping.md` + plugin guard implementation (`onBeforeToolExecute` for dangerous-cmd/protected-paths, `experimental.session.compacting` for pre-compact, `onReady` for session start). Blocks W3 handoff-v2 on OpenCode.
- I-056 (HIGH) — OpenCode plugin-first architecture: replace `adapters/opencode/dispatch.sh` bash sequential loop with JS plugin leveraging native hooks/subtask. Blocks W12 parallel-pipeline on OpenCode. See report §5.1.3.
- I-057 (MED) — Model resolver OpenCode probe: `mb-pipeline-model-resolve.sh` should check `.opencode/skills/` and `~/.config/opencode/skills/` for `host_supported`. Blocks W4 cost-multi-model on OpenCode.
- I-058 (MED) — Provider-neutral model aliases: `fast/balanced/powerful` should resolve per-host, not hardcode Anthropic IDs. Blocks W4 cost-multi-model on OpenCode (Kimi defaults).
- I-059 (MED) — OpenCode test fixtures: add `test_opencode_*.bats` for dispatch, guards, hooks in each wave. Cross-cutting.
- I-060 (LOW) — Commands `*.md` OpenCode frontmatter: `name`, `description`, `agent`, `subtask` for all 24+ command files. Cross-cutting.

## See also

- `roadmap.md` — full wave order and release gate.
- `status.md` — current phase, active plan inventory, metrics.
- `traceability.md` — generated REQ coverage matrix.
- `progress.md` — append-only historical log.
