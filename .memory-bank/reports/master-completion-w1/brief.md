# master-completion wave 1: brief for track executors (2026-11-18)

Plan: /Users/fockus/Apps/skill-memory-bank/.memory-bank/plans/2026-11-18_feature_master-completion.md
Goal: none (team started with --no-goal).
Decisions: <!-- fill: agreement ids and the file that holds them -->
Deadline: <!-- fill: code freeze and delivery dates, or "none" -->

## Checked by the orchestrator
<!-- fill: facts the orchestrator verified that tracks rely on, one bullet each -->

## Tracks
| Track | Role | Model | Size | Pipeline | Task | Depends on | Resources | Report |
|---|---|---|---|---|---|---|---|---|
| A | debugger | sonnet | standard | work · TDD · verifier | GraphRAG: nudge, cost-report graph share, work.md room | — | — | /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-w1/A.md |
| C | developer | opus | large | work · TDD · verifier · lenses logic, tests, code_rules, security, scalability | mb-team review until clean | — | — | /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-w1/C.md |
| D | developer | sonnet | standard | work · TDD · verifier · review single | Split commands/mb.md for Opus 5.5 / Fable | — | — | /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-w1/D.md |
| E | developer | sonnet | standard | work · TDD · verifier | dynamic-flow T13: Pi and OpenCode sub-invoke | — | — | /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-w1/E.md |

## Not doing
<!-- fill: what this run leaves out, one bullet each -->

## Contract between tracks
Frozen on the board as `FREEZE · contract:master-completion-w1`. Change it only through a HANDOVER to the orchestrator.
<!-- fill: the inter-track contract (names, formats, invariants), one bullet each -->

## Working tree
- Edit only in /Users/fockus/Apps/skill-memory-bank (git).
- Run Memory Bank commands with `--mb /Users/fockus/Apps/skill-memory-bank/.memory-bank`, never from inside the bank directory.

## Rules
- Failing test first, then code. Put the test command and its output before and after the change into the report.
- Minimal diff in the layer that owns the invariant; no general refactors.
- Do not commit, push or open PRs: the orchestrator commits. Do not change permissions, settings or CLAUDE.md.
- Do not read or print secrets. Protected paths: .env*, CI, Docker/K8s/Terraform.
- Report to the orchestrator only; never message other tracks. Findings that affect another track: HANDOVER on the board.
- A safety-filter refusal is reported as BLOCKED, not worked around.
- Shared code you need that belongs to another track's files or to a shared-mechanisms home: do not copy it. Stop that part, post `HANDOVER · extract:<mechanism>` (`mb-coord.sh append --type HANDOVER --track <id> --title extract:<mechanism>`) and go on with the rest.

## Resources
- none

## Limits
<!-- fill: build and test limits (packages, parallelism, flags), one bullet each -->

## Known red tests (do not fix, do not count as regressions)
- none

## Board
`bash /Users/fockus/Apps/skill-memory-bank/scripts/mb-coord.sh append --mb /Users/fockus/Apps/skill-memory-bank/.memory-bank --track <track> --type STATUS|BLOCKED|HANDOVER --title '<one line>'`
STATUS when you start and when you finish; BLOCKED when you cannot continue; read
`bash /Users/fockus/Apps/skill-memory-bank/scripts/mb-coord.sh active --mb /Users/fockus/Apps/skill-memory-bank/.memory-bank` before editing a file another track owns.

## Report
`/Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-w1/<track>.md`, a `STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT` line (the last one counts), then:
Files · Tests (failing before → passing after, with output; each failing test marked new or known-red) · Remaining ·
Questions for the orchestrator · Follow-ups.
