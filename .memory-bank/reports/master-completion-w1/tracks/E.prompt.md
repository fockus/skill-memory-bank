# Track E — dynamic-flow T13: Pi and OpenCode sub-invoke

Brief (binding, read it first): /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-w1/brief.md
Role: mb-developer · model sonnet · size standard · Skill path: /Users/fockus/Apps/skill-memory-bank
Working tree: /Users/fockus/Apps/skill-memory-bank · Bank: /Users/fockus/Apps/skill-memory-bank/.memory-bank

<!-- mb-stage:1 -->
## Task
Execute master-completion Stage 14 (plan plans/2026-11-18_feature_master-completion.md; spec .memory-bank/specs/dynamic-flow/tasks.md T13): pi_subinvoke_cmd / opencode_subinvoke_cmd and a subinvoke verb mirroring adapters/codex.sh:503-603, preferring native dispatch; scripts/mb-fanout.sh:210 runs sequentially with a WARN instead of die_usage when sub-invoke is unresolvable.

**Role:** developer
**Files:** `/Users/fockus/Apps/skill-memory-bank/adapters/pi.sh`, `/Users/fockus/Apps/skill-memory-bank/adapters/opencode.sh`, `/Users/fockus/Apps/skill-memory-bank/scripts/mb-fanout.sh`, `/Users/fockus/Apps/skill-memory-bank/scripts/mb-subinvoke-resolve.sh`, `/Users/fockus/Apps/skill-memory-bank/tests/bats/test_mb_fanout.bats`, `/Users/fockus/Apps/skill-memory-bank/tests/bats/test_mb_subinvoke_resolve.bats`, `/Users/fockus/Apps/skill-memory-bank/tests/bats/test_subinvoke_resolve.bats`, `/Users/fockus/Apps/skill-memory-bank/tests/bats/test_*subinvoke*.bats`, `/Users/fockus/Apps/skill-memory-bank/.memory-bank/specs/dynamic-flow/**`
**Depends on:** —

**DoD:**
- [ ] New bats with stub pi/opencode binaries red before and green after; tests/bats/test_mb_fanout.bats, test_mb_subinvoke_resolve.bats, test_subinvoke_resolve.bats green
- [ ] shellcheck clean on changed .sh; dynamic-flow T13 ticked through mb-work-state.sh done
<!-- /mb-stage:1 -->

## Pipeline (resolved — do not change it)
- This track runs through /mb work on /Users/fockus/Apps/skill-memory-bank/.memory-bank/plans/2026-11-18_feature_master-completion.md, driven by the orchestrator: you are dispatched per stage, and the verifier and review gates run inside that loop.
- TDD is required: failing test first; paste the command and output before and after into the report.

## Report and reply
Write /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-w1/E.md (format in the brief). Post STATUS on the board when you
start and finish. Reply with the STATUS line, five lines of summary and the report path. Do not commit; do not
message other tracks.
