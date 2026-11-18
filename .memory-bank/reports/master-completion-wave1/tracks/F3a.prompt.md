# Track F3a — S5 rebaseline on ADaPT-lite (spec only)

Brief (binding, read it first): /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-wave1/brief.md
Role: mb-architect · model sonnet · size small · Skill path: /Users/fockus/Apps/skill-memory-bank
Working tree: /Users/fockus/Apps/skill-memory-bank · Bank: /Users/fockus/Apps/skill-memory-bank/.memory-bank

<!-- mb-stage:1 -->
## Task
First half of master-completion Stage 18 (plan plans/2026-11-18_feature_master-completion.md): map svp-adapt-escalation REQ-001..010 onto ADaPT-lite (commit 190251c, AGR-080/082; scripts/mb_work_adapt.py, the adapt: block in references/pipeline.default.yaml, references/adapt.md § Lite slice). Covered parts → waiver with the commit link; the rest stays as tasks rewritten onto existing files (mb_work_adapt.py, adapt:) — stubs REQ-004, escalation journal under mb_lock_acquire REQ-007/008, cascade REQ-010; scope guard REQ-002 as a minimal check inside mb_work_adapt.py against the item's Files: (S3's mb-work-scope-check.sh is out of scope). Conformance (Seams, REQ-049 for T3/T4) until mb-spec-validate --require-scenarios rc=0. Spec docs only, no code.

**Role:** architect
**Files:** `/Users/fockus/Apps/skill-memory-bank/.memory-bank/specs/svp-adapt-escalation/requirements.md`, `/Users/fockus/Apps/skill-memory-bank/.memory-bank/specs/svp-adapt-escalation/design.md`, `/Users/fockus/Apps/skill-memory-bank/.memory-bank/specs/svp-adapt-escalation/tasks.md`, `/Users/fockus/Apps/skill-memory-bank/references/adapt.md`
**Depends on:** —

**DoD:**
- [ ] svp-adapt-escalation requirements/design/tasks rebased: every REQ either waived with a commit link or owned by a task on existing files; mb-spec-validate.sh --require-scenarios rc=0; adapt.verify_fail_cycles default 3 unchanged
<!-- /mb-stage:1 -->

## Pipeline (resolved — do not change it)
- This track runs through /mb work on /Users/fockus/Apps/skill-memory-bank/.memory-bank/plans/2026-11-18_feature_master-completion.md, driven by the orchestrator: you are dispatched per stage, and the verifier and review gates run inside that loop.
- TDD is required: failing test first; paste the command and output before and after into the report.

## Report and reply
Write /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-wave1/F3a.md (format in the brief). Post STATUS on the board when you
start and finish. Reply with the STATUS line, five lines of summary and the report path. Do not commit; do not
message other tracks.
