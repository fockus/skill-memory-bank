# Track A — GraphRAG: nudge, cost-report graph share, work.md room

Brief (binding, read it first): /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-w1/brief.md
Role: mb-debugger · model sonnet · size standard · Skill path: /Users/fockus/Apps/skill-memory-bank
Working tree: /Users/fockus/Apps/skill-memory-bank · Bank: /Users/fockus/Apps/skill-memory-bank/.memory-bank

<!-- mb-stage:1 -->
## Task
Execute master-completion Stages 2, 3 and 4 in order (plan plans/2026-11-18_feature_master-completion.md, sections 'Stage 2', 'Stage 3', 'Stage 4'): graph nudge suggests only real graph symbols with a per-subagent budget and stale-marker cleanup; graph_share in the cost report; move >=40 reference lines out of commands/work.md into new references/work-loop-reference.md.

**Role:** debugger
**Files:** `/Users/fockus/Apps/skill-memory-bank/hooks/mb-graph-nudge.sh`, `/Users/fockus/Apps/skill-memory-bank/hooks/tests/graph-discipline.bats`, `/Users/fockus/Apps/skill-memory-bank/hooks/tests/*nudge*`, `/Users/fockus/Apps/skill-memory-bank/memory_bank_skill/cost_report.py`, `/Users/fockus/Apps/skill-memory-bank/scripts/mb-cost-report.py`, `/Users/fockus/Apps/skill-memory-bank/tests/pytest/test_mb_cost_report.py`, `/Users/fockus/Apps/skill-memory-bank/commands/work.md`, `/Users/fockus/Apps/skill-memory-bank/references/work-loop-reference.md`, `/Users/fockus/Apps/skill-memory-bank/tests/bats/test_mb_work_command_doc.bats`, `/Users/fockus/Apps/skill-memory-bank/tests/bats/test_work_*.bats`
**Depends on:** —

**DoD:**
- [ ] Stage 2 DoD: new nudge bats red before and green after; existing nudge bats green; shellcheck clean on hooks/mb-graph-nudge.sh
- [ ] Stage 3 DoD: tests/pytest/test_mb_cost_report.py green with graph_share cases; scripts/mb-cost-report.py --json prints graph_share
- [ ] Stage 4 DoD: wc -l commands/work.md <= 360; test_s2_file_size_contract.py and every doc test reading commands/work.md green before and after
<!-- /mb-stage:1 -->

## Pipeline (resolved — do not change it)
- This track runs through /mb work on /Users/fockus/Apps/skill-memory-bank/.memory-bank/plans/2026-11-18_feature_master-completion.md, driven by the orchestrator: you are dispatched per stage, and the verifier and review gates run inside that loop.
- TDD is required: failing test first; paste the command and output before and after into the report.

## Report and reply
Write /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-w1/A.md (format in the brief). Post STATUS on the board when you
start and finish. Reply with the STATUS line, five lines of summary and the report path. Do not commit; do not
message other tracks.
