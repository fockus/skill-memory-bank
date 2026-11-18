# Track B — OpenSpec round-trip: decision draft

Brief (binding, read it first): /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-wave1/brief.md
Role: mb-architect · model sonnet · size small · Skill path: /Users/fockus/Apps/skill-memory-bank
Working tree: /Users/fockus/Apps/skill-memory-bank · Bank: /Users/fockus/Apps/skill-memory-bank/.memory-bank

<!-- mb-stage:1 -->
## Task
First half of master-completion Stage 8 (plan plans/2026-11-18_feature_master-completion.md): write the round-trip decisions draft into .memory-bank/context/openspec-adapter.md as a new section 'Round-trip (AGR-101)' with, for each open question, 2-3 options, a recommendation and the reason: conflict rule when both sides changed; REQ-ID handling inside OpenSpec files; export scope (only openspec/changes/<id>/); what text goes back (raw vs normalized); how import keeps capability/kind/raw text/task ids; migration of existing imports; /mb work over a change id (sync first, dry-run export at the end). Read the current adapter code (scripts/mb-openspec.py, scripts/mb_openspec_*.py), its context/spec and the OpenSpec format (openspec/ layout in test fixtures). No code changes.

**Role:** architect
**Files:** `/Users/fockus/Apps/skill-memory-bank/.memory-bank/context/openspec-adapter.md`
**Depends on:** —

**DoD:**
- [ ] The section exists with every question above, options, a recommendation and evidence (file:line), and a short list of the decisions the owner must confirm
<!-- /mb-stage:1 -->

## Pipeline (resolved — do not change it)
- This track runs through /mb work on /Users/fockus/Apps/skill-memory-bank/.memory-bank/plans/2026-11-18_feature_master-completion.md, driven by the orchestrator: you are dispatched per stage, and the verifier and review gates run inside that loop.
- TDD is required: failing test first; paste the command and output before and after into the report.

## Report and reply
Write /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-wave1/B.md (format in the brief). Post STATUS on the board when you
start and finish. Reply with the STATUS line, five lines of summary and the report path. Do not commit; do not
message other tracks.
