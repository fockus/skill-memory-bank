---
description: Drive a goal to completion over the deterministic firewall — the autonomous goal-driven loop
allowed-tools: [Bash, Read, Write, Task]
---

# /mb drive

Drive `goal.md` to completion by looping the deterministic decision function
`scripts/mb-drive.sh` — a "ralph-loop" rebuilt **over the firewall** instead of
over the model's own judgement (drive-loop ADR-1).

**You are the runtime.** `mb-drive.sh` is a stateless brain: it prints exactly
ONE next action and exits. It starts no daemon, holds no cross-invocation
state, and never dispatches a subagent itself. You call it, execute the action
it returned, then call it again — until it returns a `stop_*` action
(REQ-DR-002/003).

```
/mb drive [--route R] [--phase P] [--budget TOK] [--max-cycles N]
```

## 1. Preflight — resolve or refuse (REQ-DR-031)

`/mb drive` **never silently starts**. It reads `goal.md`; if the file is
absent it scaffolds `templates/goal.md` into the bank and still refuses, so you
have something concrete to fill in. If the file exists but does not resolve, it
reuses the `/mb goal` failure path verbatim — `scripts/mb-goal-validate.sh`
prints one concrete fix-hint per problem on stderr and exits `1`.

Run this before the loop, every time:

<!-- mb-drive:preflight -->
```bash
SKILL_DIR="${SKILL_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"   # memory-bank skill bundle root

# Bank resolution goes through the skill's ONE resolver (explicit arg → MB_PATH
# → local .memory-bank → global registry → legacy pointer). A hardcoded default
# would silently drive the wrong bank for globally-stored or relocated banks.
# shellcheck source=../scripts/_lib.sh
. "$SKILL_DIR/scripts/_lib.sh"
BANK="$(mb_resolve_path "${BANK:-}")"

# Flags this fence conducts. The loop below reads the very same variables, so a
# flag is either wired here or it does not exist.
BUDGET="${BUDGET:-}"          # --budget TOK
MAX_CYCLES="${MAX_CYCLES:-}"  # --max-cycles N

# No bank at all — /mb drive has nothing to drive.
if [ ! -d "$BANK" ]; then
  echo "[drive] refusing to start: no Memory Bank at '$BANK' — run /mb init first, then re-run /mb drive" >&2
  exit 1
fi

# Absent goal.md: scaffold the durable template, but still refuse. A bare
# template is not a goal — the loop must never start off placeholder text.
if [ ! -f "$BANK/goal.md" ]; then
  cp "$SKILL_DIR/templates/goal.md" "$BANK/goal.md"
  echo "[drive] refusing to start: no goal.md — scaffolded a template at $BANK/goal.md." >&2
  echo "[drive] fill in id, ## Description, ## Acceptance criteria and progress_source, then re-run /mb drive" >&2
  exit 1
fi

# Present but unresolvable: reuse the validator's failure path (exit 1 + one
# fix-hint per problem on stderr). The second argument pins the bank being
# driven, so `progress_source` resolves against IT and not against whatever
# .memory-bank happens to sit in the current working directory.
# An untouched scaffold fails here too: the validator rejects `<...>`
# placeholder acceptance criteria (a template is not a goal).
if ! bash "$SKILL_DIR/scripts/mb-goal-validate.sh" "$BANK/goal.md" "$BANK"; then
  echo "[drive] refusing to start: goal.md does not resolve — fix the hints above, then re-run /mb drive" >&2
  exit 1
fi

# ---- the goal resolves; arm durable state ---------------------------------
# ONE run id is minted here and threaded through every stateful consumer
# (work-state, budget, stop-telemetry, and the loop itself), so a parallel
# drive can never read another run's cycle counter or budget.
RUN_ID="${MB_WORK_RUN_ID:-$(bash "$SKILL_DIR/scripts/mb-work-state.sh" new-run-id)}"
export MB_WORK_RUN_ID="$RUN_ID"

# Durable cycle counter. `--max-cycles` reaches the run HERE or nowhere: it is
# what turns `stop_human max-cycle` from a constant into a user-set ceiling.
bash "$SKILL_DIR/scripts/mb-work-state.sh" init drive 0 --run-id "$RUN_ID" --mb "$BANK" ${MAX_CYCLES:+--max-cycles "$MAX_CYCLES"} >/dev/null

# Budget is stamped ONLY when --budget was given. A drive without --budget must
# not inherit or invent a ceiling — mb-drive.sh then never emits `stop_budget`.
if [ -n "$BUDGET" ]; then
  bash "$SKILL_DIR/scripts/mb-work-budget.sh" init "$BUDGET" --run-id "$RUN_ID" --mb "$BANK" >/dev/null
fi

# Arm stop-telemetry LAST — only a drive that actually starts is RUNNING. This
# is also the only thing that arms hooks/mb-drive-resume-gate.sh, so ordinary
# sessions are never gated (REQ-DR-033/034).
bash "$SKILL_DIR/scripts/mb-drive-stop.sh" arm --bank "$BANK" --run-id "$RUN_ID" >/dev/null
```

Only an exit `0` here means the loop may start.

## 2. The loop — `mb-drive.sh next` → execute → repeat

```bash
ACTION="$(bash "$SKILL_DIR/scripts/mb-drive.sh" next --bank "$BANK" --run-id "$RUN_ID" [--route R] [--phase P] [--budget TOK])"
```

Each call prints exactly one action line and exits `0`. Execute it, then call
`next` again. Repeat until the action starts with `stop_`.

| Action | What you do |
| --- | --- |
| `implement <route> <item>` | Dispatch the pipeline's implement role-agent for that item on that route. |
| `repair <item>` | Dispatch the same role-agent on the SAME item; bump the durable cycle with `scripts/mb-work-state.sh cycle --run-id "$RUN_ID"`. |
| `pivot <in_role\|via_architect> <item>` | Change approach instead of grinding: in-role pivot, or escalate via the architect role. |
| `stop_success` | Record, then **done.** Firewall exit `0` AND acceptance `100%`. Break the loop. |
| `stop_human <why>` | Record, then break and hand to the user: `check-broke:<name>`, `max-cycle`, `stall`, `undecidable`. |
| `stop_budget` | Record, then break: the budget ceiling would be exceeded by the next iteration. |

After each `implement` / `repair` / `pivot`, run the pipeline's
review → judge stages before calling `next` again.

**Every `stop_*` is recorded before you break** — the stop reason is the loop's
only durable trace, and an unrecorded stop leaves the drive marked RUNNING
(which keeps the Stop-hook resume-gate armed). Pass the action line verbatim;
`--action` maps it onto the closed reason vocabulary, so you never hand-roll a
reason string:

```bash
bash "$SKILL_DIR/scripts/mb-drive-stop.sh" record --action "$ACTION" --bank "$BANK" --run-id "$RUN_ID"
```

That single call writes all three sinks once each (the drive-state slot, the
`mb-flow` fence via `mb-flow-sync.sh`, and `progress.md` via the append-only
writer). Do not write any of them by hand.

`bash "$SKILL_DIR/scripts/mb-drive.sh" status --bank "$BANK"` prints the
gathered signals plus the action `next` would take, as one JSON object — a
read-only debugging aid, not part of the loop.

## 3. Dispatch — roles come from `pipeline.yaml` (REQ-DR-030)

Never guess a model. The dispatch tiers live in **`pipeline.yaml` `roles:`** and
nowhere else — locate the resolved file with `scripts/mb-pipeline.sh path`, read
the `roles:` entry for the step, and pass its **exact** `agent` / `model` /
`thinking` values. (`scripts/mb-workflow.sh` is a different question: it
resolves the step *sequence* — `steps`, `loop`, `entrypoint` — and carries no
role tiers.) The roles:

- `implement` / `repair` / `pivot` → the pipeline's implement role-agent
  (`mb-backend` / `mb-frontend` / `mb-developer` / …, with its configured
  fallback).
- `review` → the pipeline's external reviewer (codex), with its exact model and
  reasoning effort.
- `judge` → the pipeline's judge role, which terminates the review loop with
  `GO` / `GO_WITH_BACKLOG` / `NO_GO`.

Changing a model tier is a `pipeline.yaml` edit, never a `/mb drive` edit.

## 4. Never self-certify done (REQ-DR-014)

`stop_success` is the only "done" signal, and `mb-drive.sh` emits it **only**
when `scripts/mb-flow-verify.sh` exits `0` AND `scripts/mb-goal-acceptance.sh`
reports `100%`. Your own assessment that the work looks complete is not a stop
condition — a "done" over a red firewall always falls through to
`repair`/`pivot`. Do not stop the loop early, and do not report the goal as
finished on anything other than `stop_success`.

## 5. Resume after a kill

There is nothing to resume — all state lives in files (`goal.md`, the
`mb-flow` fence in `status.md`, `scripts/mb-work-state.sh`'s durable cycle
counter). Re-run the preflight and call `next` again; the loop picks up exactly
where it stopped (ADR-2).

## Exit codes

- `0` — preflight passed (goal resolves); `next` printed an action.
- `1` — refused: no bank, no `goal.md` (template scaffolded), or an
  unresolvable `goal.md` (fix-hints on stderr).
- `2` — usage error (bad flags / unknown subcommand).

## See also

- `commands/goal.md` — scaffold + validate `goal.md` / `project.md`.
- `commands/flow.md` — pin the route explicitly instead of auto-classifying.
- `commands/work.md` — the per-item governed executor `/mb drive` sequences.
