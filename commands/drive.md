---
description: "Drives a goal to completion — autonomous goal-driven loop: plans with the user, runs /mb work and /mb team to the deterministic firewall. Use when hands-off execution is wanted — «доведи до конца», «работай автономно»."
allowed-tools: [Bash, Read, Write, Edit, Task]
---

# /mb drive

Drive a goal file to completion in two phases: **planning** with the user (every acceptance criterion gets its
plans, specs, QA decision or check, one batch of approvals), then **execution** without the user, where
`scripts/mb-drive.sh` decides what runs next and `/mb work` and `/mb team` do the running.

**You are the runtime.** `mb-drive.sh` prints exactly ONE action per `next` call and dispatches nothing itself. You
run the action, report it with `returned`, call `next` again, and stop on a `stop_*` action. State lives in one run
file per drive, `<bank>/.drive/<run_id>.json`, so a resumed or compacted session continues where it left off.

```
/mb drive [--goal PATH] [--budget TOK] [--serial] [--host-serial] [--resume [RUN_ID]]
```

| Flag | Meaning |
|---|---|
| `--goal PATH` | Goal file (absolute or bank-relative); default `<bank>/goal.md` |
| `--budget TOK` | Token budget of this run (`mb-work-budget.sh` slot under the run id) |
| `--serial` | Never run items in parallel: every item goes through `/mb work` |
| `--host-serial` | This host runs one dispatch at a time (§7) |
| `--resume [RUN_ID]` | Continue a stored run instead of starting one (§8) |

## 1. Start or resume

Shell variables do not survive between tool calls: every later command writes the run id literally (or the
selection takes the only live run). Start a new run with the user's flags:

<!-- mb-drive:start -->
```bash
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"
[ -f "$SKILL_DIR/scripts/_lib.sh" ] || { echo "mb: skill bundle not found at $SKILL_DIR — set MB_SKILLS_ROOT" >&2; exit 2; }
# shellcheck source=../scripts/_lib.sh
. "$SKILL_DIR/scripts/_lib.sh"
BANK="$(mb_resolve_path "${BANK:-}")"

# The user's flags: GOAL=<path> BUDGET=<tokens> SERIAL=1 HOST_SERIAL=1
args=()
[ -z "${GOAL:-}" ] || args+=(--goal "$GOAL")
[ -z "${BUDGET:-}" ] || args+=(--budget "$BUDGET")
[ "${SERIAL:-0}" != 1 ] || args+=(--serial)
[ "${HOST_SERIAL:-0}" != 1 ] || args+=(--host-serial)

# Refuses (exit 1) without a bank, without a goal (the default goal.md is scaffolded from
# templates/goal.md first), on a goal that fails scripts/mb-goal-validate.sh (its hints on stderr),
# and on a goal another live run already drives (the message names that run).
RUN_ID="$(bash "$SKILL_DIR/scripts/mb-drive.sh" start --bank "$BANK" ${args[@]+"${args[@]}"})" || exit $?
echo "run_id=$RUN_ID"
```

A refusal is final for this call: fix what the message says (fill in the scaffolded goal, apply the validator's
hints, or resume the named run) and run `/mb drive` again. `start` records the host session from
`CLAUDE_CODE_SESSION_ID` or `MB_SESSION_ID` (or `--session ID`), which the Stop-hook gate uses (§8).

`/mb drive --resume [RUN_ID]` runs `bash "$SKILL_DIR/scripts/mb-drive.sh" resume --bank "$BANK" [--run-id <id>]`
instead; it prints `run_id=<id> goal=<path> phase=<phase>`, and you continue in that phase (§2 or §3).

## 2. Planning phase

`next` prints `plan` while the run is in this phase. Plan with the user, criterion by criterion, from the run's
goal file:

1. Size each criterion's work with `references/effort-tiers.md` and route it by tier —
   - trivial to standard: `/mb plan <type> <topic> --tier <tier>`; you write the plan, no stop.
   - large or extra: `/mb sdd <topic> --auto`, then its plan wrapper (`/mb sdd` offers it; under `--auto` it is created). The self-interview records its assumptions in the spec.
   - work that is already planned: link the existing plan or spec wrapper.
2. QA: when `<bank>/qa/README.md` is absent, ask the user for the QA target; without one, plans declare `qa: off — no QA target`. Every linked plan must carry a `qa:` line.
3. Link the evidence under each criterion (grammar: `commands/goal.md` § Evidence links) — `plan: <path>` for a plan
   or a spec wrapper (never `spec:`), `check: <command>` for a command that proves the criterion. Plans that must
   wait for each other say so with `depends_on:` in their frontmatter.
4. Ask for the approval of every large or extra spec in one batch, then open the execution phase with the approved
   topics:

```text
bash "$SKILL_DIR/scripts/mb-drive.sh" phase execution --bank "$BANK" --run-id <id> --approve <topic>,<topic>
```

The gate exits 1 with one line per gap (a criterion without a link, a missing plan, a plan without `qa:`, a spec that
is neither `status: ready` nor approved, a `depends_on:` outside the goal, a `spec:` link). Fix each gap and run it
again; exit 0 starts execution. From here on nothing waits for the user until a `stop_*`.

## 3. Execution loop

```text
bash "$SKILL_DIR/scripts/mb-drive.sh" next --bank "$BANK" --run-id <id>
```

Run the printed action (§4), report it (§5), call `next` again. Items are named by their plan path.

| Action | What you do |
|---|---|
| `plan` | The run is still planning: finish §2 |
| `work <plan>` | Run `/mb work <plan> --auto` (§4) |
| `team <plan> <plan>…` | Run the plans as parallel tracks of one `/mb team` (§4) |
| `pivot <plan>` | The plan stalled once: dispatch `pipeline.yaml` `roles.planner` (`mb-architect`) in decompose mode (ADaPT) on that plan; it rewrites the pending part into smaller items |
| `qa <plan>` | The plan's QA was deferred: run `/mb work <plan> --auto` again; it resumes at its QA step |
| `wait <plan>…` | Those plans are claimed by another live `/mb work` run: `sleep "${MB_DRIVE_WAIT_SECONDS:-300}"` |
| `final_qa` | Run the final QA of this run's own topics (§4) |
| `stop_success` | Done: goal met from evidence, final QA green, firewall green (§6) |
| `stop_budget` | The budget, or the average step cost against what is left, ends the run (§6) |
| `stop_human <why>` | A human decision is needed: `stall`, `acceptance-red:<n>`, `owned-elsewhere:<run>`, `qa-blocked:<reason>`, `qa-red`, `flow-red:<checks>`, `check-broke:<what>` (§6) |

Drive runs no verify, review or judge of its own: every gate of an item runs inside `/mb work` (and so inside each
`/mb team` track), and the firewall `scripts/mb-flow-verify.sh --skip acceptance` runs once, inside `next`, before
`stop_success`. Your own sense that the work looks finished is never a stop: only `stop_success` means done.

`bash "$SKILL_DIR/scripts/mb-drive.sh" status --bank "$BANK" --run-id <id>` prints the run as JSON — items with their
first pending heading, `files`, `work_runs`, stalls and QA state, criteria with `waiting_qa`, unbacked ticks — without
running a check or the firewall.

## 4. Executing an action

**`work <plan>`.** Run the plan with `/mb work <plan> --auto` (`commands/work.md`), with these rules under drive:

- always export `MB_WORK_PARALLEL=1`: per-run work slots, so this run never shares state with another drive or team.
- Claim with the plan path as the positional `<source>` of `mb-work-state.sh init` (a path-keyed claim).
- If `status` lists a live work run of this plan among the item's `work_runs`, continue that run (`--run-id` of it)
  instead of minting a new one.
- On a claim refusal, exit 4 from `mb-work-state.sh init`, stop and report `--outcome owned-elsewhere`: another run owns the plan.
- never pass `--takeover`; `next` waits and then stops with `owned-elsewhere:<run>`.

**`team <plan> <plan>…`.** One `/mb team` (`commands/team.md`) runs the plans as tracks:

- `team init drive-<run8> --no-goal` (`<run8>` = the first 8 characters of the run id): drive measures the goal itself.
- one `track add <id> --source <plan> --files <csv> --task "<first pending heading>" --dod "<plan> closed"` per plan,
  with `files` and the heading from `mb-drive.sh status`, and `--size` the plan's tier.
- Fill the brief from the goal and the plans; the planning approval stands for `team plan`, so no second question.
- Run the team loop until `stop_success` or `stop_human`, then `team close`. Each track runs `/mb work` on its plan.

**`final_qa`.** `python3 "$SKILL_DIR/scripts/mb_drive_qa.py" selection --bank "$BANK" --run-id <id>` prints
`<final run id> @<topic>…`; run `/mb qa run @<topic>…` (`commands/qa.md`) with that run id. Blocking bugs become fix
plans that later `work` actions execute; drive writes them, `/mb work` fixes them.

## 5. Tokens, work runs and `returned`

After every action except `plan` and `stop_*`:

```text
bash "$SKILL_DIR/scripts/mb-drive.sh" returned --bank "$BANK" --run-id <id> --action "<the action line>" \
  --tokens <N> [--outcome <O>] [--item-outcome <plan>=<O>]… [--work-run <work run id>]…
```

- `--tokens`: the sum of the token usage the host reported for every dispatch of this action. Without it the budget
  cannot count the step (one warning).
- `--work-run`: every `/mb work` run id this action used (team tracks included), so `next` tells this run's claims
  from foreign ones.
- `--outcome` (all items) or `--item-outcome` (one plan of a team): `ok` by default; `owned-elsewhere` for a claim
  refusal; `qa-blocked:<reason>` when the environment blocked QA; `stop_human:<why>` when `/mb work` or the team
  halted on a hard stop. A run that ends with its plan still open counts as a stall.

`returned` adds the tokens to the run budget, counts stalls, waits and QA deferrals, applies the final-QA gate and
ticks the goal's linked criteria from evidence.

## 6. Stops and the final report

Record every `stop_*` before you finish — the run file, the `mb-flow` fence and `progress.md` in one call:

```text
bash "$SKILL_DIR/scripts/mb-drive-stop.sh" record --bank "$BANK" --run-id <id> --action "<the stop line>"
```

Then give the final report from `mb-drive.sh status`: what is done (closed plans and met criteria), what is not
verified (deferred QA, criteria `waiting_qa`), unbacked ticks, open QA bugs (`scripts/mb-qa-bug.sh list --open`)
and, for a `stop_human`, the one concrete question the user has to answer. `qa-blocked` and `qa-red` always get this
report before you hand over.

## 7. Hosts

Dispatch every agent by role name with the host's tool from `SKILL.md` § Invocation; parallel team tracks follow
`commands/team.md` § 9. Use `--host-serial` on a host that runs one dispatch at a time: the run is recorded as serial
with reason `host`, one notice line says so, and every item goes through `/mb work`.

## 8. Resume and several drives

- `/mb drive --resume RUN_ID` continues that run at its stored phase; `/mb drive --resume` alone takes the only live
  run. With several live runs and no id, `resume` lists them (`run_id goal phase`) and exits 2: ask the user which.
- Several drives share a bank on distinct goal files: a second drive takes `--goal <path>` (scaffold it from
  `templates/goal.md`). A start on a goal that a live run drives is refused with that run's id.
- The Stop-hook gate `hooks/mb-drive-resume-gate.sh` blocks ending the session while this session's run is in
  execution and its goal is not met; a recorded stop releases it.

## Exit codes

- `0` — started, resumed, or printed an action.
- `1` — refused: no bank, no or invalid goal, goal already driven, planning gaps, a stopped run, no live run.
- `2` — usage error, or several live runs and no `--run-id`.

## See also

- `commands/goal.md` — goal files and evidence links.
- `commands/work.md` — the item engine every action runs through.
- `commands/team.md` — parallel tracks.
