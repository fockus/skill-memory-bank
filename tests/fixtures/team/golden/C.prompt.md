# Track C — Core: user resolution order, 403 rules

Brief (binding, read it first): /Users/me/proj/.memory-bank/reports/sso-20261010/brief.md
Role: mb-backend · model sonnet · size small · Skill path: /Users/me/.claude/skills/memory-bank
Working tree: /Users/me/arcadia-int · Bank: /Users/me/proj/.memory-bank

<!-- mb-stage:1 -->
## Task
Core resolves the user by explicit binding, then by `harness_uid` with role `harness-user`, otherwise answers 403.

**Role:** backend
**Files:** `/Users/me/arcadia-int/neuroexpert/backend/core/auth/**`
**Depends on:** —

**DoD:**
- [ ] Each resolution branch and the 403 case have a test.
<!-- /mb-stage:1 -->

## Pipeline (resolved — do not change it)
- This track runs through /mb work on /Users/me/proj/.memory-bank/reports/sso-20261010/tracks/C.prompt.md, driven by the orchestrator: you are dispatched per stage, and the verifier and review gates run inside that loop.
- TDD is required: failing test first; paste the command and output before and after into the report.

## Report and reply
Write /Users/me/proj/.memory-bank/reports/sso-20261010/C.md (format in the brief). Post STATUS on the board when you
start and finish. Reply with the STATUS line, five lines of summary and the report path. Do not commit; do not
message other tracks.
