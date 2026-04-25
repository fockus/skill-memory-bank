---
type: decision
tags: [subagents, refactor, plan-closure, tdd, delegation]
related_features: [plan-verifier, mb-rules-enforcer, mb-test-runner, mb-codebase-mapper, mb-doctor, mb-manager]
sprint: null
importance: high
created: 2026-04-21
---

# agents-quality plan completed (6/6 mandatory stages shipped)

Date: 2026-04-21 15:42

## What was done

- **Stage 1** `plan-verifier` baseline-aware diff + RULES.md checks + live test execution → commit `3ee5842` (+14 bats)
- **Stage 2** new `mb-rules-enforcer` subagent + `scripts/mb-rules-check.sh` → commit `363a78f` (+30 bats)
- **Stage 3** new `mb-test-runner` subagent + `scripts/mb-test-run.sh` → commit `3a32724` (+17 bats)
- **Stage 4** `mb-codebase-mapper` graph.json integration → commit `bc1a44f` (+8 bats)
- **Stage 5** `mb-doctor` RESEARCH↔experiments drift + git safety + index regen → commit `51a5dd1` (+16 bats)
- **Stage 6** `mb-manager` first-class `action: done` + 5 conflict-resolution rules → commit `43c5bcc` (+17 bats)
- **Verify-loop fix** `78c2442` — closes 3 CRITICAL findings from plan-verifier audit (has_matching_test content-grep fallback, CHANGELOG 3.2.0, SKILL.md stale description)
- Stage 7 (`mb-session-recoverer`) explicitly deferred — reasoning in lessons.md

## New knowledge

- **Two-layer subagent pattern wins**: deterministic script (bash/python) + thin LLM prompt wrapping it. Tests stay bat-checkable; prompt stays small; output is machine-composable. Used for `mb-rules-enforcer`, `mb-test-runner` — copy-pastable template for future agents.
- **Contract tests on prompts catch drift cheaply.** 102 new bats assertions all-green for 6 commits in ~4 hours. Whenever a prompt declares a behavior in prose, grep-for-the-literal-instruction catches accidental deletions during refactors.
- **Basename-matching heuristic for tdd/delta needs content-grep fallback** when projects allow tests named by feature (not script). Two-pass design (stems → content) catches cross-layer coverage without over-matching.
- **`**Baseline commit:**` in plan header beats `HEAD~N` guessing.** Captured at plan-creation via `git rev-parse HEAD` inside `mb-plan.sh`, consumed by `plan-verifier` for exact diff scope.
- **DoD line-count targets are aspirational**; actual inline content is often smaller than estimated. Better metric: "delegation pattern present + regression tests green" rather than "≥N lines removed".
- **Plan-verifier is now self-hosting** — running `/mb verify` on the `agents-quality` plan surfaced 3 real CRITICAL + 6 WARNING issues that would have been invisible without live test execution + RULES.md enforcement + baseline-aware diff. Proves the Stage 1 upgrade earns its keep.

## Gate criteria scorecard

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Stages 1-6 DoD all ✅ | ✅ (after verify-loop fix) |
| 2 | `bats` run_all 0 failures | ✅ 158/158 |
| 3 | `/mb verify` PASS + test section populated | ✅ (after fixes) |
| 4 | `/review` via mb-rules-enforcer — 0 CRITICAL | ✅ (after has_matching_test fix) |
| 5 | SKILL.md lists all 6 agents | ✅ |
| 6 | CHANGELOG v3.2.0 entry | ✅ |
| 7 | Dogfooding: CONVENTIONS sharper | ⚠️ not re-measured (mapper re-run deferred) |

Gate: met for 6/7; criterion 7 is measurement-only and non-blocking.
