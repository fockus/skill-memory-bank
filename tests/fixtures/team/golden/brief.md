# Corporate SSO on-prem: brief for track executors (2026-10-10)

Plan: /Users/me/proj/.memory-bank/plans/2026-10-09_feature_onprem-corporate-sso.md
Goal: G-002 (/Users/me/proj/.memory-bank/goal.md).
Decisions: <!-- fill: agreement ids and the file that holds them -->
Deadline: <!-- fill: code freeze and delivery dates, or "none" -->

## Checked by the orchestrator
<!-- fill: facts the orchestrator verified that tracks rely on, one bullet each -->

## Tracks
| Track | Role | Model | Size | Pipeline | Task | Depends on | Resources | Report |
|---|---|---|---|---|---|---|---|---|
| K | devops | sonnet | standard | direct · TDD | realm, mappers, service client in the kit | — | build | /Users/me/proj/.memory-bank/reports/sso-20261010/K.md |
| A | backend | opus | large | direct · TDD · review single | admin: users page, roles, secret file | K | build | /Users/me/proj/.memory-bank/reports/sso-20261010/A.md |
| C | backend | sonnet | small | direct · TDD | Core: user resolution order, 403 rules | — | — | /Users/me/proj/.memory-bank/reports/sso-20261010/C.md |

## Not doing
<!-- fill: what this run leaves out, one bullet each -->

## Contract between tracks
Frozen on the board as `FREEZE · contract:sso-20261010`. Change it only through a HANDOVER to the orchestrator.
<!-- fill: the inter-track contract (names, formats, invariants), one bullet each -->

## Working tree
- Edit only in /Users/me/arcadia-int (arc). /Users/me/arcadia3 is a clean mirror for bundles: do not touch.
- Run Memory Bank commands with `--mb /Users/me/proj/.memory-bank`, never from inside the bank directory.

## Rules
- Failing test first, then code. Put the test command and its output before and after the change into the report.
- Minimal diff in the layer that owns the invariant; no general refactors.
- Do not commit, push or open PRs: the orchestrator commits. Do not change permissions, settings or CLAUDE.md.
- Do not read or print secrets. Protected paths: .env*, CI, Docker/K8s/Terraform.
- Report to the orchestrator only; never message other tracks. Findings that affect another track: HANDOVER on the board.
- A safety-filter refusal is reported as BLOCKED, not worked around.
- Go code: gofmt and go vet clean before you report.
- Dockerfile and Helm are not edited; environment goes into the client code.
- Do not run find or du over the whole home directory.

## Resources
- **build** — every command that needs it goes through
  `bash /Users/me/.claude/skills/memory-bank/scripts/mb-lock.sh run build --owner <track> --mb /Users/me/proj/.memory-bank -- <command>`.
  Start it in the background and keep writing code and tests while it waits. It runs `./ya gc cache` itself when free
  disk is below 25 GiB; exit 77 means the start preconditions still fail — report BLOCKED. Exit 76 means free disk
  fell under 12 GiB during the run and the command was stopped. Never remove a lock; ask the orchestrator.

## Limits
<!-- fill: build and test limits (packages, parallelism, flags), one bullet each -->

## Known red tests (do not fix, do not count as regressions)
- library/harness TestRace — trunk data race (since 2026-10-09).

## Board
`bash /Users/me/.claude/skills/memory-bank/scripts/mb-coord.sh append --mb /Users/me/proj/.memory-bank --track <track> --type STATUS|BLOCKED|HANDOVER --title '<one line>'`
STATUS when you start and when you finish; BLOCKED when you cannot continue; read
`bash /Users/me/.claude/skills/memory-bank/scripts/mb-coord.sh active --mb /Users/me/proj/.memory-bank` before editing a file another track owns.

## Report
`/Users/me/proj/.memory-bank/reports/sso-20261010/<track>.md`, first line `STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT`, then:
Files · Tests (failing before → passing after, with output; each failing test marked new or known-red) · Remaining ·
Questions for the orchestrator · Follow-ups.
