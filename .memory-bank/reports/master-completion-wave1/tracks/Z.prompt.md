# Track Z — Stage 19: fix full-suite regressions

Brief (binding, read it first): /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-wave1/brief.md
Role: mb-developer · model sonnet · size standard · Skill path: /Users/fockus/Apps/skill-memory-bank
Working tree: /Users/fockus/Apps/skill-memory-bank · Bank: /Users/fockus/Apps/skill-memory-bank/.memory-bank

<!-- mb-stage:1 -->
## Task
Fix the 15 pytest failures from the Stage 19 full run (list: /private/tmp/claude-502/-Users-fockus-Apps-skill-memory-bank/dc795ad2-23d2-4e73-bc4c-6c49e807e25c/scratchpad/pytest-failed.txt; full log /private/tmp/claude-502/-Users-fockus-Apps-skill-memory-bank/dc795ad2-23d2-4e73-bc4c-6c49e807e25c/scratchpad/full-pytest.log) caused by this plan's changes: new commands critique/risk-find/final-report (descriptions what+when, command-description baseline, total listing budget), SKILL.md reference TOC/file mentions, new bats files with hollow negations / byte-blind comparisons, global host files 1 KB headroom, Cyrillic planning terms outside the whitelist. Fix the product files (descriptions, docs, the offending new bats assertions); change a test or a budget only if the test pins a now-wrong fact — say which and why.

**Role:** developer
**Files:** `/Users/fockus/Apps/skill-memory-bank/commands/critique.md`, `/Users/fockus/Apps/skill-memory-bank/commands/risk-find.md`, `/Users/fockus/Apps/skill-memory-bank/commands/final-report.md`, `/Users/fockus/Apps/skill-memory-bank/SKILL.md`, `/Users/fockus/Apps/skill-memory-bank/README.md`, `/Users/fockus/Apps/skill-memory-bank/tests/pytest/fixtures/command_descriptions_baseline.json`, `/Users/fockus/Apps/skill-memory-bank/tests/pytest/test_command_descriptions.py`, `/Users/fockus/Apps/skill-memory-bank/tests/pytest/test_skill_guide_compliance.py`, `/Users/fockus/Apps/skill-memory-bank/tests/pytest/test_global_prompt_guard.py`, `/Users/fockus/Apps/skill-memory-bank/tests/pytest/test_terminology_canonicalization.py`, `/Users/fockus/Apps/skill-memory-bank/tests/pytest/test_bats_assertion_contract.py`, `/Users/fockus/Apps/skill-memory-bank/tests/bats/*.bats`, `/Users/fockus/Apps/skill-memory-bank/references/mb/*.md`, `/Users/fockus/Apps/skill-memory-bank/references/*.md`, `/Users/fockus/Apps/skill-memory-bank/adapters/_lib_pi_global.sh`, `/Users/fockus/Apps/skill-memory-bank/docs/*.md`, `/Users/fockus/Apps/skill-memory-bank/.memory-bank/specs/*/design.md`
**Depends on:** —

**DoD:**
- [ ] Every test in the failing list passes; the six test files run green as a whole; no assertion weakened (any test/budget change listed with its reason)
<!-- /mb-stage:1 -->

## Pipeline (resolved — do not change it)
- This track runs through /mb work on /Users/fockus/Apps/skill-memory-bank/.memory-bank/plans/2026-11-18_feature_master-completion.md, driven by the orchestrator: you are dispatched per stage, and the verifier and review gates run inside that loop.
- TDD is required: failing test first; paste the command and output before and after into the report.

## Report and reply
Write /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-wave1/Z.md (format in the brief). Post STATUS on the board when you
start and finish. Reply with the STATUS line, five lines of summary and the report path. Do not commit; do not
message other tracks.
