# Pattern: tournament

Generate N candidates, then run a pairwise/bracket judge to reduce them to a
single winner. A `fanout-synthesize` whose aggregation is a knockout bracket —
best when "pick the best" needs head-to-head comparison rather than independent
scoring.

## Composition

Tournament = **`fanout-synthesize`** whose aggregation step is a **pairwise /
bracket comparator**, not a flat synthesizer. Concretely:

1. Run the `fanout-synthesize` fan-out shape to produce N candidate results
   (see `fanout-synthesize.md`).
2. Replace the synthesize step with a knockout bracket: in each round, pair the
   survivors and have **`/sadd-do-competitively`** (the competitive multi-judge
   evaluator that ranks/selects a winner from rival candidates) pick the winner
   of each pair; the winners advance. Repeat until one candidate remains.
   `mb-judge` is NOT a pairwise comparator — it returns GO / GO_WITH_BACKLOG /
   NO_GO, so it is used only as the FINAL gate on the lone winner, never to
   compare two candidates head-to-head.

The bracket is the aggregation; everything else is inherited from
`fanout-synthesize`.

## Fan-out shape

N candidate branches, same as `fanout-synthesize` (typically a power of two so
the bracket is balanced — e.g. 4 or 8; cap below). The **portable default** is
`scripts/mb-fanout.sh`: one `--branch` per candidate, one `--cmd` sub-invoke,
emitting the aggregate JSON, exit `0`/`2`.

```bash
bash scripts/mb-fanout.sh "$MB" \
  --cmd 'codex exec "$MB_FANOUT_PROMPT"' \
  --branch "candidate 1: …" --branch "candidate 2: …" \
  --branch "candidate 3: …" --branch "candidate 4: …" \
  --max-branches 8
```

A Claude-Code host MAY use the native Task tool for the candidate generation and
each pairwise comparison call as an optimization, but `mb-fanout.sh` is the
portable default.

## Per-branch skill

Each generator branch runs the same **candidate-producing** skill/agent (the
route's implementer or a `general-purpose` author) under a diversified prompt,
returning a candidate JSON object. Each bracket match runs
`/sadd-do-competitively` as the head-to-head comparator over a pair.

## Aggregation / judge

The aggregation is the **bracket itself**: pairwise `/sadd-do-competitively`
comparisons collapse the N candidates to one winner. Use only the existing
assets — `/sadd-do-competitively` as the canonical competitive comparator that
picks a winner from rival candidates, and the review ensemble
(`mb-reviewer-logic`, `mb-reviewer-tests`, `mb-reviewer-quality`,
`mb-reviewer-security`, `mb-reviewer-scalability` under `mb-reviewer-lead`, via
`commands/review.md`) to inform a match. `/reflexion-critique` may debate a tied
match before re-comparing. The lone bracket winner is then handed to `mb-judge`
for the FINAL GO / GO_WITH_BACKLOG / NO_GO gate (mb-judge is a gate, not a
pairwise comparator). No new judge rubric dimension is introduced — the bracket
reuses the existing comparators only.

## Termination rule

Stop when the bracket has collapsed to exactly **one** winner (the explicit stop
predicate: `survivors == 1`). The number of rounds is bounded by
`ceil(log2(N))`, so the tournament always terminates. If `mb-fanout.sh` exits
`2` (a candidate branch failed) or a bracket match cannot be judged, HALT and
re-run the failed step — never declare a winner over an incomplete bracket.

## Firewall

The winning candidate is NOT "done" until it passes the firewall (REQ-DF-086):

```bash
bash scripts/mb-flow-verify.sh <bank> [--phase <p>]
```

Exit `0` PASS, `1` FAIL (clean red — name the breach, repair, re-run), `2` BROKE
(a check script itself malfunctioned — fix the runner first). Only an exit-0
firewall run certifies the tournament winner.
