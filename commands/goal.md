---
description: Scaffold and validate the durable goal.md + project.md artifacts
allowed-tools: [Bash, Read, Write]
---

# /mb goal

Scaffold the Dynamic Flow goal primitive — the durable `goal.md` (end-state +
`## Acceptance criteria`, the deterministic termination condition) and
`project.md` (slow-changing non-negotiable constraints read at flow start) — then
validate the goal.

> Phase-1 scope: scaffold + validate only. The full `/goal` lifecycle
> (`status | init | set | done | list`) is out of scope here and lands in a
> later phase. This command does NOT pick a route or run a flow.

## What it does

1. Resolve the active Memory Bank (`scripts/_lib.sh::mb_resolve_path`).
2. If `.memory-bank/goal.md` is **absent**, copy `templates/goal.md` to it and
   tell the user which fields to fill (`id`, `## Description`, `## Acceptance
   criteria`, and `progress_source`). Never overwrite an existing `goal.md`.
3. If `.memory-bank/project.md` is **absent**, copy `templates/project.md` to it
   so the slow-changing constraints exist for flow start (REQ-DF-002). Never
   overwrite an existing `project.md`.
4. Validate the goal with `scripts/mb-goal-validate.sh`. A valid goal exits `0`
   with `{"ok":true}`; an invalid one exits `1` and prints a concrete fix-hint
   per problem on stderr (missing acceptance, missing/unresolvable
   `progress_source`, or `mode: adaptive` without `replan_with`).

`goal.md` stays **durable-only** — no live check-results, no route/phase fields.
Per ADR-5 those ephemeral runtime fields live in the `<!-- mb-flow -->` fence
inside `status.md`, so the acceptance aggregator can grep `goal.md` for
`- [x]/N` without fence noise.

## Usage

```bash
# Scaffold both artifacts if absent, then validate the goal.
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"   # memory-bank skill bundle root
BANK=".memory-bank"

[ -f "$BANK/goal.md" ]    || cp "$SKILL_DIR/templates/goal.md"    "$BANK/goal.md"
[ -f "$BANK/project.md" ] || cp "$SKILL_DIR/templates/project.md" "$BANK/project.md"

bash "$SKILL_DIR/scripts/mb-goal-validate.sh" "$BANK/goal.md"
```

Run it before starting a goal-driven flow. Fix any hint the validator prints,
then re-run until it exits `0`.

## Exit codes (validator)

- `0` — goal is valid (`{"ok":true}`)
- `1` — goal is invalid (one fix-hint per problem on stderr)
- `2` — usage error
