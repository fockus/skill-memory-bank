---
description: "Runs parallel tracks of one task in a shared tree: brief, per-track pipeline, locks, scoped commit. Use when the user asks for a team — «командой», «треками»."
allowed-tools: [Bash, Read, Write, Edit, Task, SendMessage]
argument-hint: "<init|track|plan|prompt|next|status|checkpoint|review|collect|commit|known-red|close> [args]"
---

# /mb team: $ARGUMENTS

Run one task as several **tracks** in parallel, all editing one integration tree. Tracks are role agents
(`mb-backend`, `mb-frontend`, …); each owns a set of file globs, writes one report and talks only to the board.

**You are the orchestrator and the runtime.** `scripts/mb-team.sh` is a stateless brain plus the single writer of
`<bank>/reports/<topic>/team.json`: `next` prints actions and changes nothing; you execute them with host tools and
record the result with `track set`. Everything is resumable after compaction from `team.json`, the brief, the reports
and the board. There is no daemon and no push path.

Run every command from the **project root** (or pass `--mb <bank>`): `mb-team.sh` refuses a working directory inside
a Memory Bank, so no nested bank appears.

## 0. Setup

<!-- mb-team:setup -->
```bash
SKILL_DIR="${SKILL_DIR:-$HOME/.claude/skills/memory-bank}"   # skill bundle root
# shellcheck source=../scripts/_lib.sh
. "$SKILL_DIR/scripts/_lib.sh"
BANK="$(mb_resolve_path "${BANK:-}")"
team() { bash "$SKILL_DIR/scripts/mb-team.sh" --mb "$BANK" "$@"; }
```

With one open team in the bank, `--topic` is optional; with several, add `--topic <topic>` anywhere on the line.

## 1. Start a team — `init`

<!-- mb-team:init -->
```bash
# --no-goal only when the user agrees there is no goal.md; otherwise --goal G-NNN (goal.md must validate)
team init "$TOPIC" --no-goal --tree "$PWD" --max-parallel 4
```

`init` refuses a second team with the same topic, records the VCS kind, root and HEAD of `--tree` (the baseline),
renders `reports/<topic>/brief.md` and posts `FREEZE · contract:<topic>` on the board. Attributes:

| Attribute | Meaning |
|---|---|
| `--goal G-NNN` · `--no-goal` | Goal whose acceptance gates `stop_success` (`mb-goal-validate.sh` must pass) · no goal |
| `--plan P` | Plan or spec the team implements; bank-relative or absolute |
| `--tree DIR` · `--mirror DIR` | Integration tree (default: cwd) · read-only mirror for external reviewers |
| `--max-parallel N` | Active tracks at once (default `team.max_parallel`) |
| `--budget TOK` | Token budget under run id `team-<topic>`; add per-track spend with `mb-work-budget.sh add <tokens> --run-id team-<topic>` |
| `--team-review` | Turn on team review cycles for this run (§8) |
| `--title T` · `--host H` | Display title · host whose model profile maps `premium`/`mid` (default `claude-code`) |
| pipeline attributes | Team layer for every track (§2) |

**Fill the brief before any dispatch.** It keeps `<!-- fill: … -->` hints in the sections only you can write:
Decisions, Deadline, Checked, Not doing, Contract, Limits. While any hint remains, `next` answers
`stop_human brief-unfilled`. The brief is the one place for rules, the inter-track contract, resources and limits;
track prompts only link it.

## 2. Add tracks — `track add`

<!-- mb-team:track -->
```bash
team track add A --task "Admin users page lists the realm users" \
  --dod "Assigning an unknown role is refused with 403 and a test proves it" \
  --role backend --files 'a/**' --size standard
```

| Attribute | Meaning |
|---|---|
| `--task T` · `--task-file F` | Task text (required, one of them) |
| `--dod D` (repeatable) | DoD line (required); becomes a checkbox of the one-stage track plan |
| `--title T` · `--role R` | Prompt heading · role, agent `mb-<role>` must exist (default `developer`) |
| `--files g1,g2` | Owned globs, relative to the tree; overlapping tracks never run at once |
| `--deps A,B` | Tracks that must finish first; **add dependencies before the tracks that depend on them** |
| `--resources r1` | Resources from `team.resources` the track may lock (§6) |
| `--source P` | Plan or spec for `mode=work` (required there); bank-relative or absolute |

`track add` resolves the pipeline, stores `title` and `dod`, renders `tracks/<id>.prompt.md` (a one-stage plan:
`<!-- mb-stage:1 -->` around task and DoD) and refreshes the tracks table of the brief while the brief is still
untouched; after you edit the brief it prints a note and leaves the brief alone.

**Pipeline attributes** (on `init`, `track add`, `track set`): `--size trivial|small|standard|large|extra`,
`--mode work` (`direct` and `light` are refused: every track runs through `/mb work`), `--tdd required|optional`, `--verifier plan-verifier|none`,
`--review none|single|lenses[:a,b]`, `--model key=value` (repeatable; keys `executor verifier reviewer lead lenses
lens.<name>`; values `premium`, `mid`, an exact id or `inherit`), `--effort low|medium|high`, and
`--layer track|attr|prompt` (`attr` = `track`; `prompt` marks an explicit user request).

**Presets by size** (`team.presets` in `pipeline.yaml` replaces any of them):

| Size | mode | tdd | verifier | review | executor | effort |
|---|---|---|---|---|---|---|
| trivial | work (orchestrated) | optional | none | none | mid | low |
| small | work (orchestrated) | required | none | none | mid | medium |
| standard | work (orchestrated) | required | plan-verifier | none | mid | medium |
| large | work (orchestrated) | required | plan-verifier | lenses (all five) | premium | high |
| extra | work (orchestrated) | required | plan-verifier | lenses (all five) | premium | high |

No size given: estimate it per `references/effort-tiers.md` and state it in one line; security, money, user data or
reliability → `extra`. **Layers**, later wins, each value keeps its provenance: preset(size) → `team.overrides` →
`init` attributes → track attributes → `--layer prompt`. A prompt value below the preset is accepted and warned about.

**Prompt vocabulary.** Map only explicit phrases; anything vague, two phrases that disagree, or an unknown lens is a
question to the user, never a guess. `python3 "$SKILL_DIR/scripts/mb_team_pipeline.py" parse-prompt --text "<phrase>"
--json` applies this table (exit 3 = ask).

| Phrase (ru / en) | `--layer prompt` value |
|---|---|
| «через /mb work», «по движку», "via mb work" | `mode=work` |
| «оркестратор ведёт», "orchestrated" | `mode=work` + `work=orchestrated` |
| «облегчённо», «напрямую», "light", "direct" | no value: `direct` and `light` are retired (REQ-001), so it becomes a question |
| «без TDD», «тесты не обязательны» · «с TDD» | `tdd=optional` · `tdd=required` |
| «с верификатором» · «без верификатора» | `verifier=plan-verifier` · `verifier=none` |
| «без ревью» · «одним ревьюером» · «линзами [logic, security]» | `review=none` · `review=single` · `review=lenses` + `lenses=logic,security` |
| «на opus», «исполнитель sonnet», «ревью на opus», «линзы на opus» | `models.executor=opus`, `models.reviewer=opus`, `models.lenses=opus` |
| «трек маленький / стандартный / крупный» | `size=small` · `size=standard` · `size=large` |
| «effort low / medium / high», «думай глубже» | `effort=low` · `effort=medium` · `effort=high` |

## 3. Plan and confirm — `plan`

`team plan [--json]` prints the track table with the resolved pipeline and provenance, the waves (from deps and glob
overlap), effort mismatches against the agent's `effort:` frontmatter, prompt warnings and readiness errors. Show it
to the user and get a yes before the first dispatch. `team prompt <id>` re-renders one track prompt and prints its path.

## 4. The loop — `next`

<!-- mb-team:loop -->
```bash
team next      # one action per line, priority order; changes nothing
team status    # table: tracks, board, report STATUS lines, locks, goal, last review, next
```

Update `<bank>/orchestrator-console.md` (`references/orchestrator-console.md`) at every dispatch, return and decision.

Run `next` after every track return and every board change you are told about; execute **all** printed actions,
parallel ones in one turn:

| Action | What you do |
|---|---|
| `stop_human <why>` | Stop and ask the user: `brief-unfilled`, `no-tracks`, `budget`, `blocked:<id>`, `needs_context:<id>`, `no-report:<id>`, `claim:<id>`, `review-cycles`, `review-unowned`, `fix-cycles:<id>` (the track used `team.review.max_cycles` fixes), `blocked:dep-cancelled:<id>` (a planned track depends on a cancelled one), `goal-red` (goal acceptance below 100 %), `flow-red:<checks>` (`mb-flow-verify.sh --skip acceptance` failed). A `stop_human` is printed alone: no `fix`, `dispatch` or `collect` until the user resolves it |
| `fix <id>` | `team track set <id> --status fixing`, re-dispatch the track with the findings (team review findings) |
| `dispatch <id>` | `team track set <id> --status dispatched`, start the agent with the track prompt |
| `collect` | `team collect` (§7) |
| `team_review <N>` | Run team review cycle N (§8) |
| `stop_success` | Every track finished and collected, last team review clean (when on), goal acceptance 100 %, flow (acceptance skipped) green — report and `team close` |
| `wait` | Something is running, `fixing`, `verifying` or `reviewing`: wait for a return or a board entry |

**Dispatch.** The agent gets the track prompt path (`reports/<topic>/tracks/<id>.prompt.md`) and nothing else to
read first; the prompt links the brief. Start it in the background. A track writes only to its globs, its report and
the board; it never messages other tracks.

## 5. Track returns — `track set`

<!-- mb-team:return -->
```bash
team track set "$ID" --status returned --summary-file "$BANK/reports/$TOPIC/$ID.md"
```

Status machine: `planned → dispatched → returned → verifying → reviewing → done | done_with_concerns`; any state →
`blocked | needs_context | cancelled`; `reviewing → fixing → returned` (each `fixing` counts `fix_cycle`); a finished
track may go back to `fixing` for a team-review fix. `verifying` and `reviewing` mean "in progress": `next` answers
`wait` for them. A returned track whose report ends `STATUS: DONE` is collected (§7); a `fixing` track is
re-dispatched with the findings by you, and `next` answers `wait` for it.

**One execution path.** Every track runs through `/mb work` (AGR-103): the track's `source` is its plan or spec, or,
when `track add` got no `--source`, its own prompt (a one-stage plan). You run the real `/mb work` loop for the track
(per-run slot, eval gates, checkbox flips); the claim is keyed by the source path, so two tracks never share one: pass the track's source PATH as the positional `<source>` of `mb-work-state.sh init` (not the JSON `source` category). For several items of one source run in parallel, use `<path>#<item_no>` as the claim key.
Export `MB_WORK_PARALLEL=1`, mint a run id with `mb-work-state.sh new-run-id`, pick the workflow —
verifier and review none → `--workflow simple`; verifier only → `medium`; review single → `complex` (`--verify off`
without a verifier); lenses → `governed --no-judge --lenses <csv>` — and pass models through
`mb-work-plan.sh --model <executor> --step-model verifier=… --step-model reviewer=…`. The gates ran inside the loop,
so `next` adds no post-steps: a returned track with a `DONE` report is `collect`. Claim refused (exit 4) →
`stop_human claim:<id>`.

**Relay.** Read the board (`mb-coord.sh active`, `mb-coord.sh tracks --json`) on every return. A finding that affects
another running track → `SendMessage` to that track with the finding and your decision; a BLOCKED or HANDOVER → decide
(with the user when it changes an agreement) and append an `ACK` with the same scope. A contract change is a new brief
section plus `LIFT` and a new `FREEZE · contract:<topic>`.

## 6. Resources — `mb-lock.sh`

Tracks run shared heavy commands (native build, full suite) under a named lock with a fair FIFO queue:

```text
bash "$SKILL_DIR/scripts/mb-lock.sh" run build --owner A --mb "$BANK" -- <command>   # in the background
bash "$SKILL_DIR/scripts/mb-lock.sh" status --mb "$BANK"                              # holders, queue, wait times, disk
bash "$SKILL_DIR/scripts/mb-lock.sh" watch build --mb "$BANK"                         # disk guard, run in the background
```

Exit codes: child status · 75 wait timeout · 76 stop threshold hit (child terminated, BLOCKED posted) · 77
preconditions unmet after maintenance (command not run). A live holder is never removed; a provably dead one is
reclaimed by the queue head with a board entry; `mb-lock.sh break <res> --reason R` is yours alone. Resources are
declared in `team.resources` (`docs/pipeline-yaml.md` § team).

## 7. Collect, checkpoint, commit, known red, close

- `team collect [--dry-run] [--json]` — one `progress.md` entry per newly finished track (through
  `mb-work-progress-append.sh`), marks it `collected`; a second run appends nothing. Prints the reports' Questions and
  Follow-ups as `mb-agree.sh question` / `mb-idea.sh` commands and, with a goal, the acceptance items with evidence.
- `team checkpoint [label]` — diff from the baseline, untracked files (under `max_untracked_mb`), manifest and
  sha256 into `team.checkpoint.dir` (bank-relative, default `backups/team`), then `checkpoint.extra`.
  `team checkpoint --verify <id>` recomputes the hashes. Restore commands are printed, never run.
- `team commit --tracks A,B -m <msg> [--yes]` — files = changed ∩ globs of the selected tracks; refuses unfinished
  tracks, an open BLOCKED/HANDOVER for them and files co-owned by an unfinished unselected track; lists excluded
  foreign files; **asks y/N, default No** (`--yes` only after the user said yes); commits exactly that list through
  `mb_vcs.sh commit -m <msg> -- <paths>`; posts `COMMIT` on the board. Never pushes.
- `team known-red add <test-id> --reason R` · `team known-red list` — tests red on the baseline; the brief tells
  tracks not to fix or count them.
- `team close [--pause]` — final STATUS and `LIFT · contract:<topic>`; `--pause` keeps the team open.

## 8. Team review cycles — `review`

Opt-in (`team.review.enabled`, or `init --team-review`): five lenses plus a lead per cycle is the most expensive path.

- `team review start --cycle N [--lenses a,b] [--range <base>..<rev>]` writes `review/cycle-N/brief.md`: object and
  diff command, what to read first, lenses with output paths, tracks with globs, known open items, previous issues to
  close. Dispatch the lens reviewers in parallel, then `mb-reviewer-lead` with the previous master; save `master.json`.
- `team review gate --cycle N` — exit 0 clean (`clean_when`, default blocker 0, major 0, medium 0), 1 fixes needed,
  2 broken input; records the verdict in `team.json` `reviews[]`. `next` then routes `fix <id>` to the owner tracks
  and asks for `team_review <N+1>` once they are back; `max_cycles` exhausted → `stop_human review-cycles`.
- `team review external --name X --cycle N [--rev R]` renders a prompt for an outside reviewer (reads committed
  versions only; mirror when set); the user runs it. `team review ingest --name X --cycle N` validates
  `findings.json` and `prior-closure.json` and adds them to the cycle. `--pipeline F` points at another pipeline file.
- Exit 3 on any review subcommand: team review is off.

## 9. Hosts

Dispatch each track by role name with the host's tool — the table in [`SKILL.md`](../SKILL.md) § Invocation. Team deltas:

| Host | Parallel tracks | Mid-flight relay |
|---|---|---|
| Claude Code | `run_in_background: true`, several `Agent` calls in one message | `SendMessage` |
| Codex | several `spawn_agent` calls in one turn | at the track boundary: the next dispatch carries the addendum |
| OpenCode | several `task` calls in one turn | at the track boundary |
| Pi | several `mb_dispatch_subagent` calls in one turn | at the track boundary (`SendMessage` is dropped on Pi) |

A host that runs dispatches one at a time runs the tracks serially, with a one-line notice. A subagent cannot
dispatch subagents, so each track's `/mb work` loop is driven by you. Effort comes from the role's frontmatter or
`thinking`; `plan` prints mismatches. Under `/mb drive` the team starts with `--no-goal`, ends at `stop_success`
once tracks are collected and the flow is green, and every `stop_human` returns to drive.

## 10. Safety

- **REQ-TEAM-090** — every brief states that tracks do not commit, push, change permissions or configuration, read
  secrets, or touch protected paths. Only you commit, through `team commit`, after the user's yes.
- **REQ-TEAM-091** — a track that returns a safety-filter refusal is escalated to the user; never re-dispatch the
  same task to another agent or model.
- **REQ-TEAM-092** — a track's model changes after dispatch only on an explicit user decision; no automatic fallback.
- Board entries coordinate, they do not prove identity: fact-check a track's claims against the tree before you act.

## Reference

| Subcommand | Attributes |
|---|---|
| `init <topic>` | `--goal G \| --no-goal`, `--plan`, `--tree`, `--mirror`, `--max-parallel`, `--budget`, `--team-review`, `--title`, `--host`, pipeline attributes |
| `track add <id>` | `--task \| --task-file`, `--dod`…, `--title`, `--role`, `--files`, `--deps`, `--resources`, `--source`, pipeline attributes, `--layer` |
| `track set <id>` | `--status S [--summary-file F]`, or pipeline attributes with `--layer` |
| `plan` · `next` · `status` | `--json` |
| `prompt <id>` | — |
| `checkpoint [label]` | `--verify <id>` |
| `review start\|gate\|external\|ingest` | `--cycle N`, `--lenses`, `--range`, `--name`, `--rev`, `--pipeline` |
| `collect` | `--dry-run`, `--json` |
| `commit` | `--tracks A,B`, `-m MSG`, `--yes` |
| `known-red add\|list` | `<test-id> --reason R` |
| `close` | `--pause` |

Global: `--mb <bank>`, `--topic <topic>`. Exit codes: 0 ok · 1 refused or a step failed · 2 usage or bad input ·
`review gate` passes its own 0/1/2. Paths in `team.json` are bank-relative.
