# /mb drive — the goal loop

<p class="mb-lede" markdown>Write the end state as acceptance criteria and let the loop run. Drive
plans every criterion **with you**, takes one batch of approvals, then executes **without you** —
through `/mb work` and `/mb team` — until evidence says the goal is met.</p>

| | |
|---|---|
| **Use it for** | Hands-off delivery of a goal with several criteria: "drive it to the end" |
| **Needs** | A Memory Bank and a goal file that validates (`/mb goal`) |
| **Writes** | `.drive/<run_id>.json`, plans and specs per criterion, `progress.md`, the `mb-flow` fence in `status.md` |
| **Stops on** | `stop_success`, `stop_budget` or `stop_human` — nothing else |
| **Status in 5.4.1** | Rebuilt in 5.4. Canonical reference: [`commands/drive.md`](../commands/drive.md) |

## Quick start

```text
/mb goal                     # scaffold goal.md + project.md, then validate
/mb drive                    # phase 1: plan with you · phase 2: execute
/mb drive --budget 2000000   # cap the run by tokens
/mb drive --resume           # continue a stored run
```

| Flag | Meaning |
|---|---|
| `--goal PATH` | Goal file, absolute or bank-relative. Default `<bank>/goal.md` |
| `--budget TOK` | Token budget of this run |
| `--serial` | Never run items in parallel: every item goes through `/mb work` |
| `--host-serial` | This host runs one dispatch at a time |
| `--resume [RUN_ID]` | Continue a stored run instead of starting one |

## Step 1 — write the goal

`/mb goal` copies `templates/goal.md` and `templates/project.md` into the bank when they are
absent, then validates the goal. `goal.md` holds the end state and the acceptance criteria;
`project.md` holds slow-changing constraints read at flow start.

```markdown
## Acceptance criteria

- [ ] Users can pay by card
  - plan: plans/2026-11-20_feature_checkout.md
  - check: bats tests/bats/test_checkout.bats
- [ ] Guests can check out without an account
  - plan: plans/2026-11-20_feature_guest.md
```

Evidence links are indented sub-bullets under a criterion:

- `plan: <bank-relative path>` — closed only when every work item it resolves to is done: its
  `<!-- mb-stage:N -->` blocks, or for a spec wrapper the spec's `<!-- mb-task:N -->` blocks.
  Link a plan or a spec wrapper, never `spec:`.
- `check: <command>` — runs from the project root after every linked plan of the criterion is
  closed; passes on exit 0 (timeout `MB_GOAL_CHECK_TIMEOUT`, default 900 s).

!!! warning "A tick only counts when it is backed"
    A linked criterion is met **only** from that evidence. A checkbox ticked by hand without it is
    listed under `unbacked` and ignored.

## Step 2 — planning, with you

`next` prints `plan` while the run is in this phase. Criterion by criterion:

<div class="mb-steps" markdown>

1. **Size it**

    Estimate the tier of each criterion's work.

2. **Plan it**

    Trivial to standard: `/mb plan <type> <topic> --tier <tier>`. Large or extra:
    `/mb sdd <topic> --auto` and its plan wrapper. Already planned: link the existing file.

3. **Decide QA**

    Without `qa/README.md` the user is asked for a QA target; every linked plan carries a `qa:` line.

4. **Link the evidence**

    `plan:` and `check:` under each criterion; `depends_on:` in plan frontmatter for ordering.

5. **Approve once**

    Every large or extra spec is approved in one batch, then the execution phase opens.

</div>

The gate into execution exits 1 with one line per gap — a criterion without a link, a missing
plan, a plan without `qa:`, an unapproved spec, a `depends_on:` outside the goal. Fix each gap and
run it again. From there nothing waits for you until a `stop_*`.

## Step 3 — execution, without you

The script prints exactly **one** action per `next` call and dispatches nothing itself. The agent
runs the action, reports it with `returned`, and calls `next` again.

| Action | What happens |
|---|---|
| `work <plan>` | `/mb work <plan> --auto` |
| `team <plan> <plan>…` | The plans run as parallel tracks of one `/mb team` |
| `pivot <plan>` | The plan stalled once: the architect rewrites its pending part into smaller items |
| `qa <plan>` | The plan's QA was deferred: `/mb work` resumes at its QA step |
| `wait <plan>…` | Another live run owns those plans: sleep, then ask again |
| `final_qa` | The final QA pass over this run's topics |
| `stop_*` | The run ends (below) |

Drive runs **no verify, review or judge of its own**. Every gate of an item runs inside `/mb work`
(and so inside each team track); the firewall runs once, before `stop_success`.

## The three stops

| Stop | Meaning |
|---|---|
| `stop_success` | The goal is met from evidence, final QA is green, the firewall is green |
| `stop_budget` | The budget, or the average step cost against what is left, ends the run |
| `stop_human <why>` | A human decision is needed |

`stop_human` reasons: `stall`, `acceptance-red:<n>`, `owned-elsewhere:<run>`,
`qa-blocked:<reason>`, `qa-red`, `flow-red:<checks>`, `check-broke:<what>`.

Every stop is recorded — the run file, the `mb-flow` fence and `progress.md` — and followed by a
final report: what is done, what is not verified, unbacked ticks, open QA bugs and, for a
`stop_human`, the one concrete question you have to answer.

## Resume and several drives

- State lives in `<bank>/.drive/<run_id>.json`, so a compacted or restarted session continues
  where it left off: `/mb drive --resume`.
- Several drives share one bank on **distinct goal files**: `/mb drive --goal goals/G-002.md`.
  A start on a goal that a live run already drives is refused with that run's id.
- A Stop-hook gate blocks ending the session while its run is in execution and the goal is not
  met; a recorded stop releases it. On Pi, a settle gate resumes an unfinished run the session
  owns.

## Limits in 5.4.1

- `/mb goal` scaffolds and validates only. A goal lifecycle (`status | init | set | done | list`)
  is not shipped.
- Drive is as autonomous as the host allows: on a host that runs one dispatch at a time, use
  `--host-serial` and expect serial execution.
- The budget counts only the tokens the host reports for each dispatch; an action reported
  without `--tokens` is not counted.
- The old `--route`, `--phase` and `--max-cycles` flags and the old preflight script are removed.

!!! agent "For agents"
    You are the runtime. Follow [`commands/drive.md`](../commands/drive.md) exactly; this page is
    the map, that file is the contract.

    1. Run the printed action, report it with `mb-drive.sh returned … --tokens N`, call `next`
       again. Stop only on a `stop_*` action.
    2. **Your own sense that the work looks finished is never a stop.** Only `stop_success` means
       done.
    3. Always export `MB_WORK_PARALLEL=1` and claim each plan by its path.
    4. Never pass `--takeover`. On a claim refusal report `--outcome owned-elsewhere`.
    5. Record every stop with `mb-drive-stop.sh record` before you finish, then give the final
       report from `mb-drive.sh status`.
    6. Shell variables do not survive between tool calls: write the run id literally in every
       command.

## Related

- [/mb work — the execution engine](mb-work.md) · [/mb team — parallel tracks](mb-team.md) · [/mb qa — acceptance QA](mb-qa.md)
- [Routes, firewall and cost](routes-and-firewall.md)
