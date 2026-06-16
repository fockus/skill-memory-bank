# Pattern: adversarial-verify

N skeptic branches each try to REFUTE a single claim. Keep the claim only if a
majority fail to refute it — the burden of proof is on the skeptics, so a claim
survives by withstanding attack, not by being asserted.

## Fan-out shape

N skeptic branches (typically 3–5; odd N makes the majority unambiguous; cap
below). The **portable default** is `scripts/mb-fanout.sh`: one `--branch` per
skeptic, each prompt carrying the SAME claim but a different refutation angle
(logic hole, missing edge case, counter-example, security/scalability attack).

```bash
bash scripts/mb-fanout.sh "$MB" \
  --cmd 'codex exec "$MB_FANOUT_PROMPT"' \
  --branch "Refute: <claim> — find a logic flaw; return {\"refuted\":bool,\"why\":…}" \
  --branch "Refute: <claim> — find a missing edge case; return {\"refuted\":bool,…}" \
  --branch "Refute: <claim> — construct a counter-example; return {\"refuted\":bool,…}" \
  --max-branches 5
```

A Claude-Code host MAY fan the skeptics out with the native Task tool as an
optimization, but `mb-fanout.sh` is the portable default and exit-code authority.

## Per-branch skill

Each branch runs a **skeptic/critic** agent instructed to actively disprove the
claim, returning `{"refuted": true|false, "why": …}`. The aspect reviewers make
natural skeptics here — e.g. `mb-reviewer-logic` for a reasoning attack,
`mb-reviewer-security` for an exploit angle, `mb-reviewer-scalability` for a
load/limits attack — each pointed at the one claim.

## Aggregation / judge

Count `refuted` across `branches[].result`. The claim SURVIVES only if a
**strict majority** did NOT refute it (`not_refuted_count > N/2`, equivalently
`refuted_count < N/2`); otherwise it is rejected with the union of refutation
reasons. A **tie** — equal refuters and non-refuters, possible only for even
`N` (e.g. 2-of-4) — REJECTS: the burden of proof is on the claim, so an
undecided vote never survives (default-to-refuted). Prefer an **odd `N`** so a
tie cannot arise. This is a deterministic majority-vote tally — NOT a new LLM
rubric. When the refutations conflict or are
themselves weak, escalate with `/reflexion-critique` (debate the refutations) or
hand the survived/rejected claim plus reasons to `mb-judge` for the final
GO / NO_GO. The review ensemble (`mb-reviewer-lead` coordinating the aspect
reviewers via `commands/review.md`) may supply additional skeptic angles. No new
judge rubric dimension is introduced.

## Termination rule

Stop when `mb-fanout.sh` returns `ok:true` for all skeptic branches AND the
tally is decided: claim KEPT (strict majority failed to refute) or REJECTED
(refuters ≥ half, i.e. a majority refuted OR a tie). If any skeptic branch
failed (`mb-fanout.sh` exit `2`), the tally is inconclusive — HALT and re-run
the failed branch rather than counting a missing vote as a pass.

## Firewall

A kept claim that drives a code change is NOT "done" until the change passes the
firewall (REQ-DF-086):

```bash
bash scripts/mb-flow-verify.sh <bank> [--phase <p>]
```

Exit `0` PASS, `1` FAIL (clean red — name the breach, repair, re-run), `2` BROKE
(a check script itself malfunctioned — fix the runner first). Only an exit-0
firewall run certifies the verified outcome.
