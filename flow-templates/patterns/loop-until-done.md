# Pattern: loop-until-done

Wrap a body pattern and re-run it until a stop predicate holds — or an iteration
cap is hit. The iterative shape behind "keep refining until the firewall is
green" or "retry the fan-out until acceptance is met", with a hard cap so it can
never spin forever.

## Composition

Loop-Until-Done = a **body pattern** (any of `fanout-synthesize`,
`generate-filter`, `adversarial-verify`, `tournament`, or `classify-and-act`)
re-run inside a bounded loop:

1. Run the body pattern once (its own fan-out + aggregation + firewall).
2. Evaluate the **stop predicate** against the body's aggregated result.
3. If the predicate holds → done. Else if `iteration < cap` → feed the result
   back as context and re-run the body. Else → HALT at the cap (see below).

The body is whatever inner pattern the route chose; this pattern only adds the
loop and the cap.

## Fan-out shape

Inherited from the wrapped body pattern — each iteration runs that body's
fan-out. The **portable default** primitive every iteration uses is
`scripts/mb-fanout.sh` (the body's `--branch` set + `--cmd` sub-invoke), emitting
the aggregate JSON, exit `0`/`2`.

```bash
for i in $(seq 1 "$MAX_ITERS"); do          # MAX_ITERS is the hard cap, e.g. 5
  # A failed fan-out (exit 2) is an INCONCLUSIVE iteration — never fall through
  # to a stale/green firewall on it. Surface it and retry within the cap.
  if ! bash scripts/mb-fanout.sh "$MB" --cmd 'codex exec "$MB_FANOUT_PROMPT"' \
       --branch "iteration $i: …" --max-branches 8; then
    echo "[loop] iteration $i: fan-out failed (exit 2) — retrying within cap" >&2
    continue
  fi
  bash scripts/mb-flow-verify.sh "$MB" && break    # stop predicate: firewall green
done
```

A Claude-Code host MAY drive each iteration's fan-out with the native Task tool
as an optimization, but `mb-fanout.sh` is the portable default.

## Per-branch skill

Inherited from the wrapped body pattern — whatever generator/critic/classifier
skill that body runs in each branch (e.g. the route's implementer, or a
`general-purpose` author). The loop adds no new per-branch skill.

## Aggregation / judge

Inherited from the wrapped body pattern's aggregation, evaluated once per
iteration to feed the stop predicate. Use only the existing assets the body
allows — `mb-judge` for a per-iteration GO / GO_WITH_BACKLOG / NO_GO,
`/reflexion-reflect` to self-refine the draft between iterations,
`/reflexion-critique` to debate whether to continue, and the review ensemble
(`mb-reviewer-lead` coordinating `mb-reviewer-logic`, `mb-reviewer-tests`,
`mb-reviewer-quality`, `mb-reviewer-security`, `mb-reviewer-scalability` via
`commands/review.md`). No new judge rubric dimension is introduced.

## Termination rule

Stop on the FIRST of:

- **stop predicate met** — the explicit done condition holds (e.g. the firewall
  exits `0`, or `mb-judge` returns GO, or acceptance criteria are satisfied); or
- **iteration cap reached** — a hard cap of **MAX_ITERS = 5 iterations** by
  default (cited here so the loop can never run unbounded). On hitting the cap
  without the predicate, HALT and report NOT-DONE with the last result and the
  blocking findings — never silently accept the final iteration as success.

A body iteration whose `mb-fanout.sh` exits `2` is a failed iteration: surface
the failing branch and either retry within the remaining cap or HALT.

## Firewall

Each iteration's body result, and the final accepted result, are NOT "done"
until the firewall passes (REQ-DF-086):

```bash
bash scripts/mb-flow-verify.sh <bank> [--phase <p>]
```

Exit `0` PASS, `1` FAIL (clean red — name the breach, repair, loop again within
the cap), `2` BROKE (a check script itself malfunctioned — fix the runner
first). A green firewall is the canonical stop predicate; reaching the cap with a
non-green firewall is a HALT, not a done.
