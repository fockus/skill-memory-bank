# Track D — Split commands/mb.md for Opus 5.5 / Fable

Brief (binding, read it first): /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-w1/brief.md
Role: mb-developer · model sonnet · size standard · Skill path: /Users/fockus/Apps/skill-memory-bank
Working tree: /Users/fockus/Apps/skill-memory-bank · Bank: /Users/fockus/Apps/skill-memory-bank/.memory-bank

<!-- mb-stage:1 -->
## Task
Execute master-completion Stage 12 (plan plans/2026-11-18_feature_master-completion.md): commands/mb.md keeps only the router table and always-needed rules (<=16384 bytes); each subcommand section moves to references/mb/<sub>.md, loaded on route; add /mb help <sub>. About 45 test files read commands/mb.md: prefer one shared test helper that reads the whole command corpus (commands/mb.md + references/mb/*.md) and switch those tests to it, instead of editing assertions one by one. Mark opus55-prompt-fit Stage 7 dropped (AGR-102).

**Role:** developer
**Files:** `/Users/fockus/Apps/skill-memory-bank/commands/mb.md`, `/Users/fockus/Apps/skill-memory-bank/references/mb/**`, `/Users/fockus/Apps/skill-memory-bank/commands/done.md`, `/Users/fockus/Apps/skill-memory-bank/tests/pytest/test_doc_counts.py`, `/Users/fockus/Apps/skill-memory-bank/tests/pytest/*helper*`, `/Users/fockus/Apps/skill-memory-bank/tests/pytest/conftest.py`, `/Users/fockus/Apps/skill-memory-bank/tests/bats/test_helper*`, `/Users/fockus/Apps/skill-memory-bank/tests/bats/helpers/**`, `/Users/fockus/Apps/skill-memory-bank/.memory-bank/plans/2026-09-24_fix_opus55-prompt-fit.md`
**Depends on:** —

**DoD:**
- [ ] wc -c < commands/mb.md <= 16384; a new test proves every router row points at an existing references/mb/*.md
- [ ] Every test that read commands/mb.md before the split (recorded list) is green after it
- [ ] opus55-prompt-fit plan: Stage 6 ticked, Stage 7 marked dropped (AGR-102)
<!-- /mb-stage:1 -->

## Pipeline (resolved — do not change it)
- This track runs through /mb work on /Users/fockus/Apps/skill-memory-bank/.memory-bank/plans/2026-11-18_feature_master-completion.md, driven by the orchestrator: you are dispatched per stage, and the verifier and review gates run inside that loop.
- TDD is required: failing test first; paste the command and output before and after into the report.

## Report and reply
Write /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-w1/D.md (format in the brief). Post STATUS on the board when you
start and finish. Reply with the STATUS line, five lines of summary and the report path. Do not commit; do not
message other tracks.
