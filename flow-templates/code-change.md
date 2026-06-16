# Route: code-change

The dominant case: a feature or change inside existing seams. This route is
deliberately **thin** — it does NOT re-decompose the work. Per ADR-7 / REQ-DF-013
it REUSES the existing `commands/work.md` implement→verify→review→fix loop
verbatim as **one skill**, then gates the result on the firewall.

## What it reuses (no over-split, ADR-7)

The whole point of this route is that the structured, context-preserving
`commands/work.md` loop already IS the right granularity for an in-seam change.
So code-change does NOT re-list `## Phases` or a `## Per-phase skill` table that
duplicates work.md — it runs the loop as a single skill:

- **Loop:** the `commands/work.md` `governed-execution` workflow —
  `implement → verify → review ensemble → judge → fix/backlog → done` — driven by
  `/mb work <target> --workflow governed-execution`. The implement step composes
  `agents/mb-engineering-core.md` + `agents/mb-tooling-core.md` + the resolved
  role-agent (e.g. `mb-backend`, `mb-frontend`, `mb-developer`) + the item body,
  exactly as work.md specifies.
- **One skill, not split into separate hops.** implement→review→fix is the SAME
  work.md loop; this route does NOT decompose it into separate skill hops (ADR-7).
  Splitting below the work.md granularity costs context-marshalling on agents
  without subagent context inheritance, which is exactly what ADR-7 forbids.

## Retry rule

The retry is work.md's own **fix-cycle**: judge `NO_GO` returns only the
`blocking_issues` to implementation, loops back to `verify`, and re-reviews —
bounded by `workflow.loop.max_cycles` (default 2, override with `--max-cycles N`).
On `on_max_cycles=stop_for_human` the loop halts for a human; on
`on_max_cycles=judge_decides` a final judge pass may close with `GO_WITH_BACKLOG`
or stop on `NO_GO`. If a phase-boundary firewall reports a red `diff_scope` breach
or unmet `acceptance`, HALT and re-run `analyze-task` (REQ-DF-024) rather than
advancing.

## Sequential fallback

The work.md loop is already sequential on a single item — implement, then verify,
then review, then fix — so no fan-out is required for the core path. Where a step
WOULD fan out (e.g. the `review_profile: ensemble` aspect reviewers run in
parallel), the portable default is `scripts/mb-fanout.sh`; on a host with no
resolvable shell sub-invoke the ensemble degrades to running the aspect reviewers
sequentially with a stderr WARN (REQ-DF-052), preserving correctness. The
firewall verdict is unchanged by whether review ran parallel or sequential.

## Patterns invoked

code-change is loop-first, not fan-out-first. The review step MAY use
`adversarial-verify` (`flow-templates/patterns/adversarial-verify.md`) — skeptic
branches try to refute "the change is correct and in-scope", and it survives only
on a strict majority — when an extra-rigorous gate is wanted; and the bounded
fix-cycle itself is a `loop-until-done`
(`flow-templates/patterns/loop-until-done.md`) whose stop predicate is a green
firewall within `max_cycles`. Neither is required for a routine in-seam change;
the work.md loop alone is the default.

## Firewall

The changed result is NOT "done" until it passes the firewall (REQ-DF-044/086):

```bash
bash scripts/mb-flow-verify.sh <bank> [--phase <p>]
```

Exit `0` PASS (every check green/skipped + severity-gate passes), `1` FAIL (a
clean red check — name the breach, repair, re-run), `2` BROKE (a check script
itself malfunctioned — fix the runner first). Only an exit-0 firewall run
certifies the change; a red verify physically blocks "done" (REQ-DF-045).
