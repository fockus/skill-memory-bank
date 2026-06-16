# Route: arch

An architectural change — it touches contracts, domain rules, ports/interfaces,
or cross-module structure. This route is **mandatory**: the deterministic
route-floor (REQ-DF-022 / ADR-4) can FORCE `arch` regardless of the LLM's pick or
an explicit override, so its template must exist or the floor points at nothing.
arch is **contract-first**: design the contract, lock it with tests, only then
implement against it — never the other way around.

## Phases

In order:

1. **design / ADR** — frame the structural decision: context → decision →
   alternatives → consequences, recorded as an ADR. Compare design options before
   committing.
2. **contract / interface** — define the seam as a Protocol / ABC / interface
   FIRST, plus the contract tests that any correct implementation must pass
   (Contract-First: tests pass for ANY conforming implementation, not one).
3. **implement against the contract** — build the concrete implementation behind
   the locked interface, respecting the Clean Architecture direction
   (Infrastructure → Application → Domain; the domain stays dependency-free).
4. **review** — a multi-aspect gate over the change (logic, tests, security,
   scalability, quality) synthesized by the lead.
5. **verify** — the contract tests + the full suite + the firewall confirm the
   structural change is sound and in-scope.

## Per-phase skill

| Phase | L2 skill | Agent |
|-------|----------|-------|
| design / ADR | `plan` / `write-spec` (+ `commands/adr.md`) | `mb-architect` |
| contract / interface | `write-spec` (Protocol/ABC + contract tests) — `commands/contract.md` / `commands/api-contract.md` | `mb-architect` |
| implement | `implement` (against the locked contract) | the seam's role-agent (`mb-backend`, `mb-frontend`, `mb-ios`, `mb-android`) |
| review | `review` + `critique` (`commands/review.md`) | `mb-reviewer-lead` coordinating the aspect reviewers |
| verify | `verify` + firewall | `mb-test-runner` via `scripts/mb-flow-verify.sh` |

The implement skill composes `agents/mb-engineering-core.md` +
`agents/mb-tooling-core.md` + the role-agent + the item body, per
`commands/work.md`. The contract is authored and frozen BEFORE the implementer
sees it, so the implementation cannot bend the interface to its convenience.

## Boundary checks

At EVERY phase boundary, fire the firewall scoped to that phase:

```bash
bash scripts/mb-flow-verify.sh <bank> --phase <design|contract|implement|review|verify>
```

- after **contract**: the contract tests exist and are RED against no
  implementation (the seam is genuinely locked), and `diff_scope` shows only the
  interface + its tests.
- after **implement**: the contract tests are GREEN, `rules` and `no_todo` are
  clean, and `diff_scope` confirms the change respected the declared
  `protected_path` boundaries.
- after **review/verify**: the lead review carries no blocking issues and the
  full firewall exits `0`.

A red boundary forces the retry rule below; never advance a structural change on
red (REQ-DF-024/044).

## Retry rule

If a boundary firewall is red, **repair and re-run that boundary** within the
work.md fix-cycle (judge `NO_GO` returns only `blocking_issues` to implement,
bounded by `max_cycles`). A red `diff_scope` breach or unmet `acceptance` HALTS
and **re-runs `analyze-task`** (REQ-DF-024) — for arch this commonly means the
contract itself was wrong, so re-design rather than patch around it. Because arch
is already the route-floor's top forced target, a failure here escalates to a
human gate, never silently widens scope.

## Sequential fallback

The design→contract→implement→verify spine is sequential. The two phases that
naturally fan out — **design** (compare rival design options) and **review**
(parallel aspect reviewers) — use `scripts/mb-fanout.sh` as the portable default.
On a host with no resolvable shell sub-invoke, both degrade to running the design
options / aspect reviewers sequentially with a stderr WARN (REQ-DF-052),
preserving correctness; the firewall verdict is identical either way.

## Patterns invoked

- `tournament` (`flow-templates/patterns/tournament.md`) — in the design phase:
  generate N candidate designs and run a pairwise bracket
  (`/sadd-do-competitively`) down to one winning design before locking the
  contract.
- `fanout-synthesize` (`flow-templates/patterns/fanout-synthesize.md`) — in the
  review phase: the aspect reviewers (`mb-reviewer-logic`, `mb-reviewer-tests`,
  `mb-reviewer-security`, `mb-reviewer-scalability`, `mb-reviewer-quality`) run as
  parallel branches synthesized by `mb-reviewer-lead` into one canonical report.

## Firewall

The structural change is NOT "done" until it passes the firewall
(REQ-DF-044/086):

```bash
bash scripts/mb-flow-verify.sh <bank> [--phase <p>]
```

Exit `0` PASS (every check green/skipped + severity-gate passes), `1` FAIL (a
clean red check — name the breach, repair, re-run), `2` BROKE (a check script
itself malfunctioned — fix the runner first). Only an exit-0 firewall run
certifies the arch change; a red verify physically blocks "done" (REQ-DF-045).
