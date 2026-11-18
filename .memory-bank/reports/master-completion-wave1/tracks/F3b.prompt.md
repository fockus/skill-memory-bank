# Track F3b — S5 svp-adapt-escalation remainder (code)

Brief (binding, read it first): /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-wave1/brief.md
Role: mb-backend · model sonnet · size standard · Skill path: /Users/fockus/Apps/skill-memory-bank
Working tree: /Users/fockus/Apps/skill-memory-bank · Bank: /Users/fockus/Apps/skill-memory-bank/.memory-bank

<!-- mb-stage:1 -->
## Task
Second half of master-completion Stage 18 (plan plans/2026-11-18_feature_master-completion.md): implement the rebased svp-adapt-escalation tasks T2-T5 (.memory-bank/specs/svp-adapt-escalation/tasks.md, AGR-107): scope guard against the item's Files: inside the adapt path, review/judge/eval-not-green counters and the new adapt: keys (review_cycles 3, judge_cycles 2, cascade_stop 3) with validator support, escalation journal (JSONL) under mb_lock_acquire with a summary, cascade stop, verify-stub, stub + backlog chain. mb_work_adapt.py is 338 lines: put the journal and the stub in sibling modules scripts/mb_work_adapt_journal.py and scripts/mb_work_adapt_stub.py. adapt.verify_fail_cycles default 3 unchanged. commands/work.md is being edited by another track right now: do NOT edit it — post a HANDOVER with the exact net-zero edit you need.

**Role:** backend
**Files:** `/Users/fockus/Apps/skill-memory-bank/scripts/mb_work_adapt.py`, `/Users/fockus/Apps/skill-memory-bank/scripts/mb_work_adapt_journal.py`, `/Users/fockus/Apps/skill-memory-bank/scripts/mb_work_adapt_stub.py`, `/Users/fockus/Apps/skill-memory-bank/references/pipeline.default.yaml`, `/Users/fockus/Apps/skill-memory-bank/scripts/mb-pipeline-validate.sh`, `/Users/fockus/Apps/skill-memory-bank/scripts/mb_pipeline_validate_blocks.py`, `/Users/fockus/Apps/skill-memory-bank/scripts/mb_pipeline_validate_core.py`, `/Users/fockus/Apps/skill-memory-bank/references/adapt.md`, `/Users/fockus/Apps/skill-memory-bank/.memory-bank/specs/svp-adapt-escalation/tasks.md`, `/Users/fockus/Apps/skill-memory-bank/.memory-bank/specs/svp-adapt-escalation/design.md`, `/Users/fockus/Apps/skill-memory-bank/tests/pytest/test_mb_work_adapt*.py`, `/Users/fockus/Apps/skill-memory-bank/tests/pytest/test_adapt_*.py`, `/Users/fockus/Apps/skill-memory-bank/tests/bats/test_*adapt*.bats`
**Depends on:** —

**DoD:**
- [ ] Each task's Eval red before code, green after; open DoD = 0 and mb-spec-validate.sh --require-scenarios rc=0 for svp-adapt-escalation; existing adapt tests (grep -rl mb_work_adapt tests/) green; pipeline validator accepts the new adapt: keys and rejects bad values
- [ ] Escalations are written as JSONL under the lock (test); modules <= 300 lines; Python 3.11; shellcheck/ruff clean
<!-- /mb-stage:1 -->

## Pipeline (resolved — do not change it)
- This track runs through /mb work on /Users/fockus/Apps/skill-memory-bank/.memory-bank/plans/2026-11-18_feature_master-completion.md, driven by the orchestrator: you are dispatched per stage, and the verifier and review gates run inside that loop.
- TDD is required: failing test first; paste the command and output before and after into the report.

## Report and reply
Write /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-wave1/F3b.md (format in the brief). Post STATUS on the board when you
start and finish. Reply with the STATUS line, five lines of summary and the report path. Do not commit; do not
message other tracks.
