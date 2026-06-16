# Pattern: generate-filter

Generate K candidate solutions in parallel, then filter/score them and keep only
the survivors. Diverge wide, then prune — useful when the right answer is not
obvious up front and exploring several is cheaper than committing to one.

## Fan-out shape

K generator branches (typically 3–6; cap below), each producing one candidate.
The **portable default** is `scripts/mb-fanout.sh`: one `--branch` per candidate
prompt (vary temperature/angle for diversity), one `--cmd` sub-invoke. It emits
the aggregate JSON and exits `0`/`2`.

```bash
bash scripts/mb-fanout.sh "$MB" \
  --cmd 'codex exec "$MB_FANOUT_PROMPT"' \
  --branch "candidate 1: …; return {\"candidate\":…}" \
  --branch "candidate 2: …; return {\"candidate\":…}" \
  --branch "candidate 3: …; return {\"candidate\":…}" \
  --max-branches 6
```

A Claude-Code host MAY generate the candidates with the native Task tool as an
optimization, but `mb-fanout.sh` is the portable default.

## Per-branch skill

Each branch runs the **same generator** skill/agent (the route's implementer or
a `general-purpose` author) under a diversified prompt, returning a candidate as
a JSON object. Generation only — scoring is a separate aggregation step, never
inlined into the generator.

## Aggregation / judge

Filter then keep the survivors. The filter is a scorer/critic over
`branches[].result`: drop candidates that fail a hard predicate (e.g. don't
compile, miss an acceptance criterion), then rank the rest. Use the existing
combine assets only:

- `/sadd-do-competitively` — the canonical generate-then-LLM-judge-and-pick flow
  for competing candidates;
- the review ensemble (`mb-reviewer-logic`, `mb-reviewer-tests`,
  `mb-reviewer-quality`, `mb-reviewer-security`, `mb-reviewer-scalability` under
  `mb-reviewer-lead`, via `commands/review.md`) to score each candidate on the
  existing dimensions;
- `mb-judge` for a GO / NO_GO on each survivor;
- `/reflexion-critique` to debate close calls.

The hard-predicate filter is deterministic; no new judge rubric dimension is
introduced.

## Termination rule

Stop when `mb-fanout.sh` returns `ok:true` for the generator branches AND the
filter has produced a non-empty survivor set (the survivor count is the explicit
stop predicate — e.g. "keep the top S survivors that pass the hard filter"). If
every candidate is filtered out, HALT and regenerate with a corrected prompt
rather than shipping a rejected candidate. If a generator branch failed
(`mb-fanout.sh` exit `2`), surface it and do not score a missing candidate.

## Firewall

A kept survivor is NOT "done" until it passes the firewall (REQ-DF-086):

```bash
bash scripts/mb-flow-verify.sh <bank> [--phase <p>]
```

Exit `0` PASS, `1` FAIL (clean red — name the breach, repair, re-run), `2` BROKE
(a check script itself malfunctioned — fix the runner first). Only an exit-0
firewall run certifies a survivor.
