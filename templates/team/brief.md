# {{title}}: brief for track executors ({{date}})

Plan: {{plan}}
Goal: {{goal}}
Decisions: <!-- fill: agreement ids and the file that holds them -->
Deadline: <!-- fill: code freeze and delivery dates, or "none" -->

## Checked by the orchestrator
<!-- fill: facts the orchestrator verified that tracks rely on, one bullet each -->

## Tracks
| Track | Role | Model | Size | Pipeline | Task | Depends on | Resources | Report |
|---|---|---|---|---|---|---|---|---|
{{tracks}}

## Not doing
<!-- fill: what this run leaves out, one bullet each -->

## Contract between tracks
Frozen on the board as `FREEZE · contract:{{topic}}`. Change it only through a HANDOVER to the orchestrator.
<!-- fill: the inter-track contract (names, formats, invariants), one bullet each -->

## Working tree
{{working_tree}}

## Rules
{{rules}}

## Resources
{{resources}}

## Limits
<!-- fill: build and test limits (packages, parallelism, flags), one bullet each -->

## Known red tests (do not fix, do not count as regressions)
{{known_red}}

## Board
`{{coord}} append --mb {{bank}} --track <track> --type STATUS|BLOCKED|HANDOVER --title '<one line>'`
STATUS when you start and when you finish; BLOCKED when you cannot continue; read
`{{coord}} active --mb {{bank}}` before editing a file another track owns.

## Report
`{{reports}}/<track>.md`, first line `STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT`, then:
Files · Tests (failing before → passing after, with output; each failing test marked new or known-red) · Remaining ·
Questions for the orchestrator · Follow-ups.
