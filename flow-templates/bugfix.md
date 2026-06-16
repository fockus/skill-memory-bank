# Route: bugfix

Fix a localized defect. The defining loop is **reproduce → debug → patch →
verify**: never patch a bug you have not first reproduced with a failing test,
and never declare it fixed until that test goes green behind the firewall.

## Phases

In strict order:

1. **reproduce** — pin the defect down with a NEW failing test (RED) that
   captures the wrong behaviour, plus the minimal repro steps. No reproduction →
   no fix; a bug you cannot reproduce is a research spike, not a bugfix.
2. **debug** — locate the root cause behind the failing test (read the seam,
   trace the graph, isolate the offending function). Diagnosis only — no patch yet.
3. **patch** — apply the minimal change that turns the RED test GREEN, touching
   the narrowest seam that closes the defect (no opportunistic refactor).
4. **verify** — re-run the repro test (now GREEN) plus the existing suite, then
   the firewall, confirming the fix closed the defect and broke nothing else.

## Per-phase skill

| Phase | L2 skill | Agent |
|-------|----------|-------|
| reproduce | `risk-find` (author the failing repro test) | `mb-qa` / `mb-developer` |
| debug | `implement` (root-cause isolation, no edit) | `mb-developer` |
| patch | `implement` (minimal fix against the RED test) | `mb-developer` / the seam's role-agent (`mb-backend`, `mb-frontend`) |
| verify | `verify` + firewall | `mb-test-runner` via `scripts/mb-flow-verify.sh` |

The implement skill composes `agents/mb-engineering-core.md` +
`agents/mb-tooling-core.md` + the role-agent + the defect body, exactly as
`commands/work.md` specifies.

## Boundary checks

At EVERY phase boundary, fire the firewall scoped to that phase:

```bash
bash scripts/mb-flow-verify.sh <bank> --phase <reproduce|debug|patch|verify>
```

- after **reproduce**: assert the new test is RED (the defect is genuinely
  captured) and `diff_scope` is clean — only the test changed.
- after **patch**: the repro test is GREEN, `no_todo` is clean, and `diff_scope`
  confirms the patch stayed in the intended seam.
- after **verify**: the full firewall (tests + rules + acceptance) exits `0`.

A non-zero firewall at any boundary forces the retry rule below; the flow is
never advanced on red (REQ-DF-024/044).

## Retry rule

If the patch boundary firewall is red (the repro test still fails or a regression
appears), **repair and re-run the patch→verify boundary** — do NOT advance. If the
firewall reports a red `diff_scope` breach (the patch leaked outside the seam) or
unmet `acceptance`, HALT and **re-run `analyze-task`** (REQ-DF-024) — a leaking
"bugfix" may actually be an `arch` change the route-floor must escalate. The
debug↔patch retry is bounded; on repeated failure escalate to `arch` rather than
widening the patch unboundedly.

## Sequential fallback

The four phases are inherently sequential — each consumes the prior phase's
result — so the default path needs no fan-out. Where a phase WOULD fan out (e.g.
several candidate root-cause hypotheses explored in parallel via the
`generate-filter` pattern), the portable default is `scripts/mb-fanout.sh`; on a
host with no resolvable shell sub-invoke the branches degrade to running
sequentially with a stderr WARN (REQ-DF-052), preserving correctness.

## Patterns invoked

- `adversarial-verify` (`flow-templates/patterns/adversarial-verify.md`) — in the
  verify phase, skeptic branches try to REFUTE "this patch truly closes the
  defect (no alternate trigger remains)"; the fix survives only on a strict
  majority that fails to refute it.
- `generate-filter` (`flow-templates/patterns/generate-filter.md`) — OPTIONAL in
  the debug phase when the root cause is non-obvious: generate several candidate
  diagnoses, filter to the one whose minimal patch turns the repro test GREEN.

## Firewall

The patched result is NOT "done" until it passes the firewall (REQ-DF-044/086):

```bash
bash scripts/mb-flow-verify.sh <bank> [--phase <p>]
```

Exit `0` PASS (every check green/skipped + severity-gate passes), `1` FAIL (a
clean red check — name the breach, repair, re-run), `2` BROKE (a check script
itself malfunctioned — fix the runner first). Only an exit-0 firewall run
certifies the fix; a red verify physically blocks "done" (REQ-DF-045).
