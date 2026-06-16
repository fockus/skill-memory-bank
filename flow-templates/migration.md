# Route: migration

A schema / data / dependency migration with **ordering risk**. The defining
hazards are sequence (steps must apply in a dependency-safe order) and
reversibility (every forward step needs a rollback). This is the highest route in
the ranking because a mis-ordered or irreversible migration can corrupt state in
ways no later phase recovers.

## Phases

In order:

1. **plan ordering** — derive the dependency-safe sequence of migration steps
   (topological order; never apply a step before the state it depends on exists),
   and identify every `protected_path` the migration will touch.
2. **forward migration** — apply the ordered forward steps (schema change /
   dependency bump / data transform), one step at a time, expand-then-contract
   where possible.
3. **data backfill / verify** — backfill the migrated data and verify integrity
   (row counts, invariants, referential consistency) before contracting the old
   shape.
4. **rollback plan** — author and dry-run the reverse path for every forward
   step, so the migration is reversible; a forward step with no tested rollback
   is not "done".

## Per-phase skill

| Phase | L2 skill | Agent |
|-------|----------|-------|
| plan ordering | `plan` (topological step order) — `commands/db-migration.md` | `mb-devops` / `mb-architect` |
| forward migration | `implement` (ordered forward steps) | `mb-backend` / `mb-devops` |
| data backfill / verify | `implement` + `verify` (integrity checks) | `mb-backend` |
| rollback plan | `implement` (reverse path) + `verify` (dry-run) + firewall | `mb-devops` via `scripts/mb-flow-verify.sh` |

The implement skill composes `agents/mb-engineering-core.md` +
`agents/mb-tooling-core.md` + the role-agent + the item body, per
`commands/work.md`. Touching infra/migration files frequently trips the
`protected_path` floor (REQ-DF-022), which is why migration is treated as a
high-care route.

## Boundary checks

At EVERY phase boundary, fire the firewall scoped to that phase:

```bash
bash scripts/mb-flow-verify.sh <bank> --phase <plan|forward|backfill|rollback>
```

- after **plan ordering**: `diff_scope` confirms only the planned migration files
  are in scope, and the `protected_path` check has been acknowledged
  (`--allow-protected` or human sign-off), never silently bypassed.
- after **forward migration** and **backfill**: integrity checks pass and
  `no_todo` / `rules` are clean.
- after **rollback plan**: the reverse path dry-run succeeds and the full firewall
  exits `0`.

A red boundary forces the retry rule below; never advance a migration on red
(REQ-DF-024/044) — a half-applied migration is the worst failure mode.

## Retry rule

If a forward/backfill boundary is red, **HALT and roll back to the last green
step** using the rollback plan, then repair and re-apply — do NOT push forward
through a red step (that is how state corrupts). A red `diff_scope` breach or a
`protected_path` hit that was not sanctioned HALTS and **re-runs `analyze-task`**
(REQ-DF-024). The forward↔repair retry is bounded by the work.md `max_cycles`;
on exhaustion, stop for a human rather than force an unverified migration.

## Sequential fallback

Migration is **ordering-first** — the steps MUST run in dependency order, so the
forward spine is intentionally sequential and never fanned out (parallel forward
steps would defeat the ordering guarantee). Independent read-only checks (e.g.
integrity probes across several tables) MAY fan out via `scripts/mb-fanout.sh`;
on a host with no resolvable shell sub-invoke they degrade to running
sequentially with a stderr WARN (REQ-DF-052), preserving correctness. Ordering of
the WRITE steps is never relaxed by the fallback.

## Patterns invoked

- `loop-until-done` (`flow-templates/patterns/loop-until-done.md`) — the forward
  migration applies ordered steps inside a bounded loop until none remain (the
  stop predicate is "no pending step AND firewall green"), with a hard iteration
  cap so it can never spin.
- `generate-filter` (`flow-templates/patterns/generate-filter.md`) — OPTIONAL in
  the rollback phase: generate candidate reverse paths and filter to the one whose
  dry-run restores the pre-migration state cleanly.

## Firewall

The migrated result is NOT "done" until it passes the firewall (REQ-DF-044/086):

```bash
bash scripts/mb-flow-verify.sh <bank> [--phase <p>]
```

Exit `0` PASS (every check green/skipped + severity-gate passes), `1` FAIL (a
clean red check — name the breach, repair, re-run), `2` BROKE (a check script
itself malfunctioned — fix the runner first). Only an exit-0 firewall run
certifies the migration; a red verify physically blocks "done" (REQ-DF-045).
