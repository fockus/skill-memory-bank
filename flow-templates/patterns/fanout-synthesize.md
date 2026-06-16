# Pattern: fanout-synthesize

Spawn N parallel branches with diverse prompts, then synthesize their results
into one merged answer. This is the base orchestration shape the other patterns
compose from.

## Fan-out shape

N branches, one per diverse prompt (typically 2–8; cap below). The **portable
default** primitive is `scripts/mb-fanout.sh`: pass one `--branch <prompt>` (or
`--branch-file <f>`) per branch and one `--cmd <sub-invoke>` template that each
branch runs with its prompt arriving through `MB_FANOUT_PROMPT`. It runs the
branches concurrently and emits ONE aggregate JSON object
(`{"branches":[…],"ok":…,"count":N,"failed":M}`), exit `0` (all branches
returned valid JSON) or `2` (any branch failed / non-JSON / cap / budget reject).

```bash
bash scripts/mb-fanout.sh "$MB" \
  --cmd 'codex exec "$MB_FANOUT_PROMPT"' \
  --branch "angle A: …" --branch "angle B: …" --branch "angle C: …" \
  --max-branches 8
```

Respect `mb-fanout.sh`'s `--max-branches` cap (default 16) and its opt-in
`--cost-per-branch` budget pre-check (reuses `mb-work-budget.sh`). A
Claude-Code host MAY instead fan these branches out with the native Task tool as
an optimization, but `mb-fanout.sh` stays the default and the portable contract.

## Per-branch skill

Each branch runs the **same** generating skill/agent under a *different* prompt
(the diversity is in the prompt, not the skill) — e.g. the route's
implementer/researcher agent, or a `general-purpose` exploration agent. The
branch returns a JSON object so `mb-fanout.sh` can aggregate it without dropping
results.

## Aggregation / judge

Synthesize the `branches[].result` array into one merged answer. Default merge =
a single synthesizer pass over the aggregate. When the branches disagree or a
quality bar is needed, escalate to the existing combine assets — never a new
rubric dimension:

- the review ensemble — `mb-reviewer-logic`, `mb-reviewer-tests`,
  `mb-reviewer-quality`, `mb-reviewer-security`, `mb-reviewer-scalability`,
  coordinated by `mb-reviewer-lead` (via `commands/review.md`);
- `mb-judge` for a single GO / GO_WITH_BACKLOG / NO_GO verdict over the merge;
- the global reflexion skills `/reflexion-critique` (multi-perspective debate
  over the branch set) and `/reflexion-reflect` (self-refine the merged draft);
- `/sadd-do-competitively` when the branches are competing candidates that need
  an LLM-as-judge pick.

No new judge rubric dimension is introduced — aggregation reuses the assets
above only.

## Termination rule

Stop when `mb-fanout.sh` reports `ok:true` (every branch returned valid JSON)
AND the synthesizer/judge has produced exactly one merged result. If
`mb-fanout.sh` exits `2` (a branch failed or was non-JSON), HALT and surface the
named failing branch(es) — do not synthesize a partial set as if complete.

## Firewall

The merged result is NOT "done" until it passes the firewall (REQ-DF-086):

```bash
bash scripts/mb-flow-verify.sh <bank> [--phase <p>]
```

Exit `0` PASS (every check green/skipped + severity-gate passes), `1` FAIL (a
clean red check — name the breach, repair, re-run), `2` BROKE (a check script
itself malfunctioned — loudest failure, fix the runner before re-certifying).
Only an exit-0 firewall run certifies the synthesized result.
