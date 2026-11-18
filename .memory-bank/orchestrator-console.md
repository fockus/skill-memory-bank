# Orchestrator console — master-completion

Plan: plans/2026-11-18_feature_master-completion.md · Team: master-completion-wave1 (reports/master-completion-wave1/) · Decisions: AGR-101…103

## Tracks (wave 1)
| Track | Stage | Run id | State |
|---|---|---|---|
| A GraphRAG | 2→3→4 | d650943f… | done, collected (SKILL.md link added by orchestrator) |
| C mb-team | 11 | d64b240f… | fix cycle 4 (C4-M1, ownership marker) running; cycle budget exhausted (3/2) → after this fix mb-judge decides GO/GO_WITH_BACKLOG/NO_GO instead of another lead cycle |
| D mb.md split | 12 | c01987d5… | done, collected (re-review APPROVED) |
| E sub-invoke | 14 | 5dc1d6eb5ea64cd691d726be545ac3b8 | done, collected |
| G Pi settle gate | 20 | 3ebc0cb1… | done, collected (pi_native 173 passed); live Pi check still open |
| A2 graph dispatch | 5→6 | 7cbe79a3… | done, collected; Claude SubagentStart → I-293 |
| B OpenSpec decisions | 8 (draft) | 5987e086… | done; owner accepted all 11 → AGR-105 (Q-003 resolved) |
| B2 OpenSpec import+sidecar | 8 (code) | 3f1e69ff… | done, collected; carry-over (whole-file rewrite) → Stage 9 |
| B3 OpenSpec export+sync3 | 9 | 348b540a… | fix cycle 2 (last; then mb-judge): blockers A (scenarios outside unit) + B (incomplete topic bypasses link check), transactional apply, one bank lock for TOCTOU |
| H1 Fable run (J-1) | 13+7 | f46327e4… | done, collected (review 2 minor; stat idiom fixed by orchestrator; I-298) |
| H2 Opus run (dup-id lint) | 13+7 | 79b3f71b… | done, collected (review 3 minor → I-296); graph gap → I-297 |
| upgrade check (Stage 13) | 13 | — | FAILED in temp HOME (opencode-io manifest HOME); mb-debugger investigating |
| A3 graph test mapping (I-297) | 22 | 96a743f9… | dispatched |
| F3a S5 rebaseline (spec) | 18a | 65cd4572… | dispatched |
| F2 S4 backlog-db | 17 | 2e4f0940… | done, collected (verifier PASS_WITH_NOTES; follow-ups I-296) |
| G2 pdw ideas+spike | 21 | 2908adcc… | done, collected; no-go → I-295 |
| E2 T14 skills | 15 | 4088aa34… | done, collected; counts 39 in SKILL/README/install |
| F1 S7+S8 close | 16 | 98ec8014… | done, collected; verify.md S8-T5 line + KNOWN_FAILING trimmed by orchestrator |
| 0 bookkeeping | 1 | — | done (orchestrator) |

## Next step
Wave-1 commit: index free; goal.md parked to goals/G-001.md (AGR-106) → pre-commit no longer runs the full suite. Commit after B3 lands (B3 + upgrade-debug may touch more files); `git add` own list + `git commit --only --pathspec-from-file`; hermes staged set untouched.
On each return: `mb-team.sh next`, read board, verifier (plan-verifier) per track; apply D's HANDOVER test edits; then wave commit.

## Open
- C left: tests/pytest/test_mb_team_config.py has formatter-only churn (~97 lines) — at commit keep only the new test hunk (ask owner; restoring HEAD formatting was refused by auto-mode for the subagent). C's HANDOVER: test_mb_team_command.py router test → apply after D lands.
- Research done: Pi early stop → Stage 20 (track G, running); pi-dynamic-workflows → Stage 21, owner chose borrow + spike (AGR-104); runs after Stage 15 (T14).
- Staged but uncommitted from the first commit (aborted for wave 1): uv.lock, notes ×2, pipelines/opencode.yaml, plans/unfinished-work-completion, codebase graph → commit with wave 1.
- Another session's hung `git commit` (fix(drive), started 16:15, already in HEAD as 1815bcc) runs a full bats in the main tree — not ours, not touched.
- `.pi/` is a local install artifact: never commit. `hermes/` (untracked, not ours) — never commit.

## Unrecorded decisions
- none
