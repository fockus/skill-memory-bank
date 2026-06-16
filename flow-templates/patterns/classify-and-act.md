# Pattern: classify-and-act

One classifier branch routes the task to exactly one of K downstream skills
(a fan-out of 1 + a deterministic dispatch). The cheapest pattern: spend one
branch deciding *which* specialist runs, then run only that specialist.

## Fan-out shape

A fan-out of **1**: a single classifier branch. The **portable default** is
`scripts/mb-fanout.sh` with exactly one `--branch` (the classifier prompt) and a
`--cmd` sub-invoke; it emits the aggregate JSON and exits `0`/`2`.

```bash
bash scripts/mb-fanout.sh "$MB" \
  --cmd 'codex exec "$MB_FANOUT_PROMPT"' \
  --branch "Classify this task into exactly one of {K labels}; return {\"label\":…}" \
  --max-branches 1
```

The classifier's JSON result carries the chosen label; the host then dispatches
the matching downstream skill directly (no further fan-out). A Claude-Code host
MAY use the native Task tool for the single classifier call as an optimization,
but `mb-fanout.sh` is the portable default.

## Per-branch skill

The single branch runs a lightweight **classifier** agent (a `general-purpose`
or the route's analyst agent) that reads the goal/diff and returns one of the K
labels. The downstream act-step is whichever specialist agent the label selects
(e.g. `mb-backend`, `mb-frontend`, `mb-qa`) — dispatched after the classifier,
not inside the fan-out.

## Aggregation / judge

There is no multi-branch merge — the single classifier result IS the routing
decision. Validate it before acting: the label must be one of the K known
labels (an unknown label is a fail-loud, not a silent default). When the
classification is ambiguous or high-stakes, escalate with `/reflexion-critique`
to debate the candidate labels, or hand the classifier output to `mb-judge` for
a GO / NO_GO on the chosen route. No new rubric dimension is introduced.

## Termination rule

Stop when `mb-fanout.sh` returns `ok:true` for the classifier branch AND the
returned label is one of the K known labels AND the dispatched downstream skill
has completed. If the label is unknown or the classifier branch failed
(`mb-fanout.sh` exit `2`), HALT and re-classify (re-run `analyze-task`) — never
dispatch on a missing or invalid label.

## Firewall

The dispatched act-step's output is NOT "done" until it passes the firewall
(REQ-DF-086):

```bash
bash scripts/mb-flow-verify.sh <bank> [--phase <p>]
```

Exit `0` PASS, `1` FAIL (clean red — name the breach, repair, re-run), `2` BROKE
(a check script itself malfunctioned — fix the runner first). Only an exit-0
firewall run certifies the acted result.
