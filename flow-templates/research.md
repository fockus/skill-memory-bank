# Route: research

An investigation or spike — **no production code change is expected**. The
termination condition is a written report / decision, NOT merged code. The
firewall runs its standard fixed check set (`--phase` is informational and does
not change the gate), so for a research spike the load-bearing checks are
`acceptance` (the scoped questions are answered) and `diff_scope` (the spike did
not touch production code); `tests` simply stays green or skips because nothing
in the codebase changed. research is the lowest route in the ranking; if the
investigation turns into a real change, re-run `analyze-task` and let it route to
`code-change`/`arch`.

## Phases

In order:

1. **scope question** — frame the precise question(s) the spike must answer and
   the acceptance bar for "answered" (recorded in `goal.md` acceptance criteria).
2. **gather evidence** — collect evidence in parallel: codebase graph, web
   sources, prior notes/sessions. Each strand returns a cited finding, never an
   unsupported claim.
3. **synthesize** — merge the evidence strands into one coherent analysis with
   the trade-offs and the recommended decision.
4. **final-report** — write the report / decision (and an ADR if a decision is
   made). Termination is this artifact, not a code merge.

## Per-phase skill

| Phase | L2 skill | Agent |
|-------|----------|-------|
| scope question | `analyze-task` | `mb-analyst` |
| gather evidence | `risk-find` (graph + web + notes recall) | `mb-research` |
| synthesize | `critique` (debate the strands) | `mb-analyst` |
| final-report | `final-report` (write the decision / ADR via `commands/adr.md`) | `mb-analyst` via `scripts/mb-flow-verify.sh` |

No role-agent edits production code on this route — `mb-research` and
`mb-analyst` produce artifacts (findings, analysis, report), and the engineering
discipline still applies via the `agents/mb-engineering-core.md` prepend.

## Boundary checks

At EVERY phase boundary, fire the firewall. The check set is fixed — `--phase`
is informational and does not change the gate — but for a research spike the
load-bearing checks are `diff_scope` and `acceptance`:

```bash
bash scripts/mb-flow-verify.sh <bank> --phase <scope|gather|synthesize|report>
```

- after **gather/synthesize**: `diff_scope` is clean of production-code edits (a
  research spike that starts editing source is mis-routed — re-run
  `analyze-task`).
- after **final-report**: `acceptance` confirms the scoped questions are
  answered, `no_todo` confirms no dangling placeholder shipped in the report, and
  `tests` stays green/skip because no production code changed.

A red boundary forces the retry rule below; never declare the spike answered on
red (REQ-DF-024/044).

## Retry rule

If the report boundary firewall is red — a scoped question is unanswered
(`acceptance` short), or `no_todo` flags a placeholder left in the report —
**re-run the gather/synthesize phases** with a sharpened prompt; do NOT declare
the spike done on an unmet question. If `diff_scope` shows production code was
touched, HALT and **re-run `analyze-task`** (REQ-DF-024) so the work re-routes to
a code route. The gather↔synthesize retry is bounded; on a question that cannot be
answered within the cap, report NOT-DONE with the open question rather than
forcing a conclusion.

## Sequential fallback

Evidence gathering is the natural fan-out: independent strands (graph query, web
search, notes recall) run as parallel branches via `scripts/mb-fanout.sh` as the
portable default. On a host with no resolvable shell sub-invoke the strands
degrade to running **sequentially** with a stderr WARN (REQ-DF-052), preserving
correctness — the synthesis is identical whether the strands ran parallel or
sequential.

## Patterns invoked

- `fanout-synthesize` (`flow-templates/patterns/fanout-synthesize.md`) — the core
  shape: parallel evidence strands fanned out, then synthesized into one analysis.
- `tournament` (`flow-templates/patterns/tournament.md`) — OPTIONAL when the spike
  must choose among rival options: run a pairwise bracket
  (`/sadd-do-competitively`) over the candidate decisions down to one
  recommendation.

## Firewall

The investigation is NOT "done" until the report passes the firewall
(REQ-DF-044/086). The firewall runs its standard check set
(`tests`, `lint`, `no_todo`, `diff_scope`, `acceptance`) and `--phase` is
informational only; for a research spike the load-bearing checks are `acceptance`
(questions answered) and `diff_scope` (no production code), while `tests` stays
green/skip:

```bash
bash scripts/mb-flow-verify.sh <bank> [--phase <p>]
```

Exit `0` PASS (every relevant check green/skipped + severity-gate passes), `1`
FAIL (a clean red check — e.g. an unanswered question fails `acceptance` —
sharpen and re-run), `2` BROKE (a check script itself malfunctioned — fix the
runner first). Only an exit-0 firewall run certifies the spike answered; a red
verify physically blocks "done" (REQ-DF-045).
