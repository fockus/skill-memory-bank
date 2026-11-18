# Track G — Pi settle-resume gate

Brief (binding, read it first): /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-wave1/brief.md
Role: mb-backend · model sonnet · size standard · Skill path: /Users/fockus/Apps/skill-memory-bank
Working tree: /Users/fockus/Apps/skill-memory-bank · Bank: /Users/fockus/Apps/skill-memory-bank/.memory-bank

<!-- mb-stage:1 -->
## Task
Execute master-completion Stage 20 (plan plans/2026-11-18_feature_master-completion.md): an agent_before_settle handler in a new adapters/pi_native_settle.mjs (registered next to the other native hooks) that resumes an unfinished /mb drive or /mb work run with a hidden message and continue:true, capped at 3 per settle cycle, fail-open, never on error/aborted; persistence lines in the Pi AGENTS.md block; retry-once wording in pi_subagent_extension.ts; recommended Pi retry settings documented, not written.

**Role:** backend
**Files:** `/Users/fockus/Apps/skill-memory-bank/adapters/pi_native_settle.mjs`, `/Users/fockus/Apps/skill-memory-bank/adapters/pi_graph_rag_extension.ts`, `/Users/fockus/Apps/skill-memory-bank/adapters/_lib_pi_global.sh`, `/Users/fockus/Apps/skill-memory-bank/adapters/pi.sh`, `/Users/fockus/Apps/skill-memory-bank/adapters/pi_subagent_extension.ts`, `/Users/fockus/Apps/skill-memory-bank/tests/pytest/test_pi_native_settle.py`, `/Users/fockus/Apps/skill-memory-bank/docs/cross-agent-setup.md`
**Depends on:** —

**DoD:**
- [ ] tests/pytest/test_pi_native_settle.py red before and green after (unfinished run continues, finished run settles, cap, corrupt state, error response); existing tests/pytest/test_pi_native_*.py green
- [ ] docs/cross-agent-setup.md documents the gate and the recommended retry settings
<!-- /mb-stage:1 -->

## Pipeline (resolved — do not change it)
- This track runs through /mb work on /Users/fockus/Apps/skill-memory-bank/.memory-bank/plans/2026-11-18_feature_master-completion.md, driven by the orchestrator: you are dispatched per stage, and the verifier and review gates run inside that loop.
- TDD is required: failing test first; paste the command and output before and after into the report.

## Report and reply
Write /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-wave1/G.md (format in the brief). Post STATUS on the board when you
start and finish. Reply with the STATUS line, five lines of summary and the report path. Do not commit; do not
message other tracks.
