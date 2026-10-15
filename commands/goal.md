---
description: "Scaffolds and validates the durable goal.md + project.md artifacts. Use when setting a long-running project goal — «поставь цель», success criteria for /mb drive."
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
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"
[ -f "$SKILL_DIR/scripts/_lib.sh" ] || { echo "mb: skill bundle not found at $SKILL_DIR — set MB_SKILLS_ROOT" >&2; exit 2; }
. "$SKILL_DIR/scripts/_lib.sh"
BANK="$(mb_resolve_path "${BANK:-}")"

[ -f "$BANK/goal.md" ]    || cp "$SKILL_DIR/templates/goal.md"    "$BANK/goal.md"
[ -f "$BANK/project.md" ] || cp "$SKILL_DIR/templates/project.md" "$BANK/project.md"

bash "$SKILL_DIR/scripts/mb-goal-validate.sh" "$BANK/goal.md" "$BANK"
```

Run it before starting a goal-driven flow. Fix any hint the validator prints,
then re-run until it exits `0`.

## Evidence links

A criterion may carry indented link sub-bullets; checkbox counting ignores them:

```markdown
## Acceptance criteria

- [ ] Users can pay by card
  - plan: plans/2026-10-15_feature_checkout.md
  - check: bats tests/bats/test_checkout.bats
```

- `plan: <bank-relative path>` is closed only when every work item it resolves to is done: its
  `<!-- mb-stage:N -->` blocks, or for a spec wrapper the spec's `<!-- mb-task:N -->` blocks in its
  `tasks:` range. A missing path falls back to `plans/done/<basename>`.
- `check: <command>` runs from the project root only after every linked plan of the criterion is closed; it passes on exit 0 (timeout `MB_GOAL_CHECK_TIMEOUT`, default 900 s).
- A linked criterion is met only from that evidence; a hand tick `[x]` without that evidence does not count and is listed under `unbacked`.
- In a goal with links, a criterion without one is unmet (`no evidence link`). A goal without any
  link keeps plain checkbox counting.

`scripts/mb-goal-acceptance.sh <goal> <bank>` reports it; `--tick` also writes each linked box to its
result, `--ticks-only` counts boxes without reading plans or running checks.

## Several drives in one bank

`<bank>/goal.md` is the default goal. A second `/mb drive` takes `--goal <path>`: each drive owns its own goal file and passes it as the first argument of `mb-goal-acceptance.sh`. Scaffold it from `templates/goal.md` the same way.

## Exit codes (validator)

- `0` — goal is valid (`{"ok":true}`)
- `1` — goal is invalid (one fix-hint per problem on stderr)
- `2` — usage error
