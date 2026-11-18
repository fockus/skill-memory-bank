# master-completion wave 1: brief for track executors (2026-11-18)

Plan: /Users/fockus/Apps/skill-memory-bank/.memory-bank/plans/2026-11-18_feature_master-completion.md
Goal: none (team started with --no-goal).
Decisions: AGR-101 (OpenSpec round-trip), AGR-102 (opus55 only Opus 5.5 / Fable), AGR-103 (master plan, shortcuts allowed, GraphRAG first), AGR-097 (standard track = executor with TDD + plan-verifier), AGR-084 (no release/tag); all in `.memory-bank/agreements.md`.
Deadline: none

## Checked by the orchestrator
- `commands/work.md` and `references/work-reference.md` are both exactly 400 lines; the zone limit is 400 (`tests/pytest/test_s2_file_size_contract.py`). Track A must not grow either.
- `commands/mb.md` is 1792 lines / ~111 KB; about 45 test files read it (`grep -rlE 'commands/mb\.md' tests hooks/tests`).
- The graph is fresh: `bash scripts/mb-graph.sh status`; use `mb-graph.sh who-calls|impact|tests <Name>` before grep sweeps.
- Local pytest needs `PYTHONPATH=.`; Python in CI is 3.11/3.12, local 3.13 — no 3.13-only syntax.
- `hooks/mb-graph-nudge.sh:139-145` (fallback stopwords) let `sed`, `graph`, `pack` through as suggested symbols; `:88-91` keys the throttle by `session_id` only.
- An unrelated git commit with a pre-commit full suite may still be running; never stage, commit, stash or reset.

## Tracks
| Track | Role | Model | Size | Pipeline | Task | Depends on | Resources | Report |
|---|---|---|---|---|---|---|---|---|
| A | debugger | sonnet | standard | work · TDD · verifier | GraphRAG: nudge, cost-report graph share, work.md room | — | — | /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-wave1/A.md |
| C | developer | opus | large | work · TDD · verifier · lenses logic, tests, code_rules, security, scalability | mb-team review until clean | — | — | /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-wave1/C.md |
| D | developer | sonnet | standard | work · TDD · verifier · review single | Split commands/mb.md for Opus 5.5 / Fable | — | — | /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-wave1/D.md |
| E | developer | sonnet | standard | work · TDD · verifier | dynamic-flow T13: Pi and OpenCode sub-invoke | — | — | /Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-wave1/E.md |

## Not doing
- master-completion Stages 1, 5–10, 13, 15–19 (later waves).
- No version bump, tag, release or push.
- No edits to `.memory-bank/{checklist,roadmap,status,progress,backlog}.md` or `tests/pytest/test_spec_corpus_battery.py` — orchestrator only.

## Contract between tracks
Frozen on the board as `FREEZE · contract:master-completion-wave1`. Change it only through a HANDOVER to the orchestrator.
- Track A owns `commands/work.md`; Track D owns `commands/mb.md`. Neither edits the other's file.
- Test files that read both files (`test_tooling_core_wiring.py`, `test_s2_file_size_contract.py`, `test_graph_wrapper_instructions.py`, `test_phase*_registration.py`, `tests/pytest/fixtures/command_descriptions_baseline.json`) belong to nobody in this wave: if one needs a change, post a HANDOVER with the exact edit.
- Track D's shared reader: `tests/pytest/mb_corpus.py` exposes `read_mb_corpus() -> str`; `tests/bats/lib/mb_corpus.bash` exposes `mb_corpus` printing the same text.
- No track renames a heading that a test cuts text between.

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
- Run only targeted tests for your files (`bats <files>`, `PYTHONPATH=. python3 -m pytest -q <files>`, `bash scripts/mb-test-run.sh --files <changed> --out human`); never the full suite — the orchestrator runs it once.
- Lint only changed files: `shellcheck -x --source-path=SCRIPTDIR <sh>`, `ruff check <py>`.
- No new dependencies.

## Known red tests (do not fix, do not count as regressions)
- none

## Board
`bash /Users/fockus/Apps/skill-memory-bank/scripts/mb-coord.sh append --mb /Users/fockus/Apps/skill-memory-bank/.memory-bank --track <track> --type STATUS|BLOCKED|HANDOVER --title '<one line>'`
STATUS when you start and when you finish; BLOCKED when you cannot continue; read
`bash /Users/fockus/Apps/skill-memory-bank/scripts/mb-coord.sh active --mb /Users/fockus/Apps/skill-memory-bank/.memory-bank` before editing a file another track owns.

## Report
`/Users/fockus/Apps/skill-memory-bank/.memory-bank/reports/master-completion-wave1/<track>.md`, a `STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT` line (the last one counts), then:
Files · Tests (failing before → passing after, with output; each failing test marked new or known-red) · Remaining ·
Questions for the orchestrator · Follow-ups.
