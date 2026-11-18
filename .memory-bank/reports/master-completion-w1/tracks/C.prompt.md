# Track C — mb-team review until clean

Brief (binding, read it first): /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-w1/brief.md
Role: mb-developer · model opus · size large · Skill path: /Users/fockus/Apps/skill-memory-bank
Working tree: /Users/fockus/Apps/skill-memory-bank · Bank: /Users/fockus/Apps/skill-memory-bank/.memory-bank

<!-- mb-stage:1 -->
## Task
Execute master-completion Stage 11 (plan plans/2026-11-18_feature_master-completion.md). Read .memory-bank/reports/mb-team/review.md and fix-verify.md. Fix the open findings m1, m2, m3, m4, m6, m7 that are real defects (blocker/major/medium); for each you judge minor, write a one-line backlog entry text in your report (orchestrator files it). Then the governed lens review of this track is the clean-review gate.

**Role:** developer
**Files:** `/Users/fockus/Apps/skill-memory-bank/scripts/mb_team_*.py`, `/Users/fockus/Apps/skill-memory-bank/scripts/mb-team*.sh`, `/Users/fockus/Apps/skill-memory-bank/scripts/mb-lock.sh`, `/Users/fockus/Apps/skill-memory-bank/scripts/mb_lock_*.py`, `/Users/fockus/Apps/skill-memory-bank/scripts/mb_vcs.sh`, `/Users/fockus/Apps/skill-memory-bank/commands/team.md`, `/Users/fockus/Apps/skill-memory-bank/.memory-bank/specs/mb-team/**`, `/Users/fockus/Apps/skill-memory-bank/tests/bats/test_mb_team_*.bats`, `/Users/fockus/Apps/skill-memory-bank/tests/bats/test_mb_lock_*.bats`, `/Users/fockus/Apps/skill-memory-bank/tests/pytest/test_mb_team_*.py`, `/Users/fockus/Apps/skill-memory-bank/tests/pytest/test_mb_lock_queue.py`
**Depends on:** —

**DoD:**
- [ ] Every open finding from reports/mb-team/fix-verify.md:198-205 is either fixed with a test or listed in the report as minor with a reason
- [ ] Team bats (tests/bats/test_mb_team_*.bats, tests/bats/test_mb_lock_*.bats) and pytest (tests/pytest/test_mb_team_*.py, test_mb_lock_queue.py) green
- [ ] Lens review of the track ends with 0 blocker, 0 major, 0 medium
<!-- /mb-stage:1 -->

## Pipeline (resolved — do not change it)
- This track runs through /mb work on /Users/fockus/Apps/skill-memory-bank/.memory-bank/plans/2026-11-18_feature_master-completion.md, driven by the orchestrator: you are dispatched per stage, and the verifier and review gates run inside that loop.
- TDD is required: failing test first; paste the command and output before and after into the report.

## Report and reply
Write /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-w1/C.md (format in the brief). Post STATUS on the board when you
start and finish. Reply with the STATUS line, five lines of summary and the report path. Do not commit; do not
message other tracks.
