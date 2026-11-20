# /mb team — parallel tracks in one tree

<p class="mb-lede" markdown>Run one task as several **tracks** at once, all editing the same
working tree. Each track is a role agent that owns a set of file globs, runs the full `/mb work`
loop for its part, writes one report and talks only to a shared board.</p>

| | |
|---|---|
| **Use it for** | A task that splits into parts with separate files: backend + frontend + tests |
| **Needs** | A Memory Bank; a goal (`--goal G-NNN`) or an explicit `--no-goal` |
| **Writes** | `reports/<topic>/team.json`, `brief.md`, `tracks/<id>.prompt.md`, one report per track |
| **Never does** | Push. Commit without your yes. Let a track commit |
| **Status in 5.4.1** | New in 5.4. Canonical reference: [`commands/team.md`](../commands/team.md) |

## Quick start

```text
/mb team init checkout --goal G-004 --max-parallel 4
/mb team track add A --role backend  --files 'api/**' --size standard \
    --task "Card payments endpoint" \
    --dod "An unknown card is refused with 402 and a test proves it"
/mb team track add B --role frontend --files 'web/**' --size standard \
    --task "Checkout form" --dod "The form posts a card and shows the order page"
/mb team plan        # tracks, waves, pipeline per track — you confirm
/mb team next        # the loop
```

Run every command from the **project root**. With one open team in the bank, `--topic` is
optional; with several, add `--topic <topic>`.

## How a team runs

<div class="mb-steps" markdown>

1. **Init** — `team init <topic>`

    Records the tree's baseline, renders the brief, posts `FREEZE · contract:<topic>` on the board.

2. **Fill the brief**

    Decisions, Deadline, Checked, Not doing, Contract, Limits. Until every hint is filled, `next`
    answers `stop_human brief-unfilled`.

3. **Add tracks** — `team track add <id>`

    Task, DoD lines, role, owned globs, dependencies, size.

4. **Plan** — `team plan`

    Prints tracks, waves and the pipeline per track. You say yes before the first dispatch.

5. **Loop** — `team next`

    One action per line. The orchestrator executes all of them and calls `next` again.

6. **Wave end**

    Collect reports, verify every spec requirement, optional team review.

7. **Commit** — `team commit --tracks A,B -m "<msg>"`

    Asks y/N, default No. Then `team close`.

</div>

## Tracks

| Attribute | Meaning |
|---|---|
| `--task T` · `--task-file F` | Task text (required) |
| `--dod D` (repeatable) | Definition-of-Done line (required) |
| `--role R` | Agent `mb-<role>`; default `developer` |
| `--files g1,g2` | Owned globs. Overlapping tracks never run at once |
| `--deps A,B` | Tracks that must finish first. Add dependencies before their dependants |
| `--resources r1` | Named resources the track may lock |
| `--source P` | A plan or spec the track implements; without it the track prompt is a one-stage plan |
| `--contract C` | An executable contract (see below) |
| `--size` | `trivial · small · standard · large · extra` — picks the preset |

### Pipeline per track

Every track runs through `/mb work`. Its size picks the preset; `team.presets` in `pipeline.yaml`
replaces any row.

| Size | TDD | Verifier | Review | Executor model | Effort |
|---|---|---|---|---|---|
| trivial | optional | none | none | mid | low |
| small | required | none | none | mid | medium |
| standard | required | plan-verifier | none | mid | medium |
| large | required | plan-verifier | five lenses | premium | high |
| extra | required | plan-verifier | five lenses | premium | high |

Layers, later wins, each value keeps its provenance: preset(size) → `team.overrides` → `init`
attributes → track attributes → an explicit user phrase. Override one knob with `--tdd`,
`--verifier`, `--review none|single|lenses[:a,b]`, `--model key=value`, `--effort`.

## The `next` actions

| Action | What the orchestrator does |
|---|---|
| `dispatch <id>` | Marks the track `dispatched` and starts its agent with the track prompt |
| `fix <id>` | Marks it `fixing` and re-dispatches it with the findings |
| `extract <id> <mechanism>` | A track needs shared code in another track's zone: decide its home, record it, relay |
| `collect` | Appends one `progress.md` entry per finished track |
| `spec_verify <spec>` | Runs the plan-verifier over the whole `requirements.md` |
| `team_review <N>` | Runs team review cycle N |
| `wait` | Something is running: wait for a return or a board entry |
| `stop_human <why>` | Stop and ask the user. Printed alone; nothing else runs until it is resolved |
| `stop_success` | Every track collected, reviews clean, goal acceptance 100 %, flow green |

`stop_human` reasons: `brief-unfilled`, `no-tracks`, `budget`, `blocked:<id>`,
`needs_context:<id>`, `no-report:<id>`, `claim:<id>`, `review-cycles`, `fix-cycles:<id>`,
`goal-red`, `flow-red:<checks>`, `shared-foundation:<signal>`, `spec-gaps:<spec>`.

Track status machine: `planned → dispatched → returned → verifying → reviewing → done |
done_with_concerns`; any state → `blocked | needs_context | cancelled`; `reviewing → fixing →
returned`.

## Three guards that make parallel work safe

### Files have one owner

Waves come from dependencies and glob overlap. Heavy shared commands — a native build, the full
suite — run under a named lock with a fair FIFO queue:

```text
mb-lock.sh run build --owner A -- <command>
mb-lock.sh status
```

A live holder is never removed. Lock exit codes: `75` wait timeout, `76` stop threshold hit,
`77` preconditions unmet.

### No copy-paste foundations

Tracks that may not touch each other's files tend to each write their own copy of a mechanism they
all need. `team plan` lists every signal two or more tracks share — a `platform/`, `shared/`,
`common/` or `kit/` path, a `<word> kit|boundary|client|registry` phrase — as a **blocking shared
foundation**. Resolve it one of three ways:

- add a foundation track that the others list in `--deps`;
- add a row to `<bank>/shared-mechanisms.md` with status `exists`;
- accept a harmless overlap: `team plan --accept-shared <signal>`.

Every track prompt lists the registry rows it touches ("use X from Y; do not copy"). A second copy
of a listed mechanism outside its home is a review blocker.

### Contracts that execute

A contract (`<bank>/contracts/<id>.md`) holds spec, rules and DoD checks. Freeze it before
dispatch — spec items must be **red** at freeze time — and the track must turn them green.
`team commit` runs the contract again and refuses a missing or changed lock. Only the orchestrator
amends a frozen contract (`freeze --amend --reason R`).

## Wave end

- `team collect` writes one `progress.md` entry per finished track, prints the reports' questions
  and follow-ups, and scans the added lines for cross-track copies.
- `spec_verify` checks every REQ of the spec for code plus test evidence. Gaps become next-wave
  tracks or backlog items.
- `team review` is opt-in (`--team-review` or `team.review.enabled`): five lenses plus a lead per
  cycle. It is the most expensive path.
- `team checkpoint [label]` saves the diff from the baseline with a manifest and hashes. Restore
  commands are printed, never run.
- `team commit` stages exactly `changed ∩ globs of the selected tracks`, runs the rules gate
  (`team.rules_gate`, `mb-rules-check.sh`, the contract), commits and posts `COMMIT` on the board.

## Hosts

| Host | Parallel tracks | Mid-flight relay |
|---|---|---|
| Claude Code | Several `Agent` calls in one message, in the background | `SendMessage` |
| Codex | Several `spawn_agent` calls in one turn | At the track boundary |
| OpenCode | Several `task` calls in one turn | At the track boundary |
| Pi | Several `mb_dispatch_subagent` calls in one turn | At the track boundary |

A host that runs one dispatch at a time runs the tracks serially, with a one-line notice.

## Limits in 5.4.1

- There is no daemon. The orchestrator session **is** the runtime: `mb-team.sh` only prints
  actions and records state.
- A subagent cannot dispatch subagents, so each track's `/mb work` loop is driven by the
  orchestrator.
- The retired `direct` and `light` track modes are refused; every track runs through `/mb work`.
- Nothing is pushed. Path-scoped commits on Arc are unproven against the real client: check on a
  scratch branch first.
- Board entries coordinate; they do not prove identity. Fact-check a track's claims against the
  tree.

!!! agent "For agents"
    You are the orchestrator **and** the runtime. Follow [`commands/team.md`](../commands/team.md)
    exactly; this page is the map, that file is the contract.

    1. Never dispatch before the brief is filled and the user has confirmed `team plan`.
    2. After every track return and every board change, run `team next` and execute **all**
       printed actions; parallel ones in one turn.
    3. A `stop_human` is final until the user resolves it. Do not work around it.
    4. Tracks never commit, push, change permissions or read secrets. Only you commit, through
       `team commit`, after the user's yes.
    5. A track that returns a safety refusal is escalated to the user — never re-dispatched to
       another agent or model.
    6. Keep `<bank>/orchestrator-console.md` current at every dispatch, return and decision; read
       it first after a compaction.

## Related

- [/mb work — the execution engine](mb-work.md) · [/mb drive — the goal loop](mb-drive.md)
- [Coordination board](coordination.md)
- [`pipeline.yaml` schema](pipeline-yaml.md) (`team:` section)
