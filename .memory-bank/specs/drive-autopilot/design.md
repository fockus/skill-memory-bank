---
type: spec-design
topic: drive-autopilot
status: ready
created: 2026-10-15
linked_requirements: requirements.md
---

# Design: drive-autopilot

> Slice S3 of `[SPEC:autopilot]`. Drive stops being a second pipeline and becomes a planner plus a
> dispatcher over `/mb work` (S1) and `/mb team` (S2). Lightweight by construction (NFR-001, AGR-075,
> AGR-078): five coarse implementation tasks, no new dependency, no check of drive's own except the
> existing firewall once before `stop_success`. The old decision core (implement → repair → pivot over a
> goal-wide cycle counter, `scripts/mb-drive.sh:147-203`) is deleted, not wrapped. Several drives may run in
> one bank, each on its own goal file (user decision 2026-10-15).

## Architecture

Two phases, one state file per drive run, one brain.

```
/mb drive [--goal G] ──► mb-drive.sh start ──► <bank>/.drive/<run_id>.json  {phase: planning, goal: G}
                                                     │
 PLANNING (with the user, prompt-driven: commands/drive.md §2)
   per criterion: /mb plan --tier T (trivial..standard)  |  /mb sdd <t> --auto + wrapper (large/extra)
   QA target settled (qa/README.md or `off — no QA target`), links written under each criterion
   one batch of approvals ──► mb-drive.sh phase execution --approve <topics>   (gate C3.2)
                                                     │
 EXECUTION (no human):  loop        (every call: --run-id R, or the only live run)
   action = mb-drive.sh next                      ◄── reads the run file, goal links, plan items, live
     work <plan>          → /mb work <plan> --auto         work claims, budget; the firewall only at the end
     team <p1> <p2> …     → /mb team (--no-goal, one track per plan, S2)
     pivot <plan>         → mb-architect, decompose mode (ADaPT) on that plan
     qa <plan>            → /mb work <plan> --auto again (resumes at its QA step)
     wait <plan> …        → items owned by another live run: sleep, then next
     final_qa             → /mb qa run @<topic> … (the run's own topics)
     stop_*               → mb-drive-stop.sh record --run-id R --action "<line>" ; final report ; break
   mb-drive.sh returned --action "<line>" --tokens N [--outcome …] [--work-run ID]…
     → budget add · stall / QA / wait accounting · final-QA gate and fix plans · goal ticks from evidence
```

Ownership after this spec:

| Concern | Owner |
|---|---|
| Item cycles, verify, eval gate, review, judge, QA loop (§5c2), checkbox flips, claims | `/mb work` (unchanged) |
| Parallel tracks, claims by source path, team stops | `/mb team` (S2) |
| Plan `qa:` declaration, test cases, wrapper, source bundle | `/mb plan`, `/mb sdd`, `/mb work` (S1) |
| What runs next, stalls, pivots, waits, budget, deferred QA, final QA and its fix plans, phase | drive (this spec) |
| Acceptance from evidence, goal ticks | `scripts/mb-goal-acceptance.sh` + `scripts/mb_goal_evidence.py` |
| Done authority | `scripts/mb-flow-verify.sh --skip acceptance`, once, before `stop_success`, after drive's own evidence check on its goal (REQ-DR-014 kept) |

Files (all new or rewritten files < 400 lines, NFR-002):

| File | Role | Size target |
|---|---|---|
| `scripts/mb-drive.sh` | thin CLI dispatcher (rewritten from 463 lines) | ≤ 120 |
| `scripts/mb_drive_state.py` | run-file IO and run selection; `start`, `resume`, `phase`, `returned`, `stop` | ≤ 300 |
| `scripts/mb_drive_decide.py` | facts gathering, pure `decide(facts)`, `status` | ≤ 300 |
| `scripts/mb_drive_qa.py` | final-QA gate, bug → topic grouping, fix-plan writer | ≤ 150 |
| `scripts/mb_goal_evidence.py` | goal link parser, plan closure, `check:` runner, ticks | ≤ 250 |
| `scripts/mb-work-slots.sh` | `mbw_drive_slot <bank> <run_id>` → `<bank>/.drive/<run_id>.json` (retargeted, kept) | unchanged size |
| `scripts/mb-drive-preflight.sh` | deleted (folded into `start`; its `drive 0` work-state init is I-270) | — |

Dependency direction: `mb_drive_decide` → `mb_drive_state`, `mb_goal_evidence`, `mb_work_waves`;
`mb_drive_state` → `mb_drive_qa`, `mb_goal_evidence`; `mb_goal_evidence` → `mb_work_items`,
`mb_work_plan_wrapper`; shell helpers (`mb-work-budget.sh`, `mb-work-state.sh`, `mb-qa-bug.sh`,
`mb-flow-verify.sh`) are subprocesses. Nothing in `/mb work` or `/mb team` imports drive.

## Interfaces

### C1 — Goal links and evidence acceptance — owner `scripts/mb-goal-acceptance.sh`

Links are indented sub-bullets under a criterion; the existing checkbox parser does not count them:

```markdown
## Acceptance criteria

- [ ] Users can pay by card
  - plan: plans/2026-10-15_feature_checkout.md
  - check: bats tests/bats/test_checkout.bats
- [ ] Admin audit log is exported
  - plan: plans/2026-10-15_feature_audit-export.md      # a spec is linked through its wrapper plan
```

- `plan: <bank-relative path>` — a plan or a spec wrapper (S1 REQ-011). When the path is absent,
  `plans/done/<basename>` is tried (the plan was closed by `/mb done`). A plan is **closed** when every
  work item it resolves to — its own `<!-- mb-stage:N -->` blocks, or for a wrapper the spec's
  `<!-- mb-task:N -->` blocks in its `tasks:` range — has status `done` (`mb_work_items.parse_work_items`
  + `mb_work_plan_wrapper.fm_value`). `/mb work` flips a block only after its gates passed (verifier
  PASS, eval green, QA gate at the cadence item), so "all done" is the durable trace of D-07's
  "verifier PASS and `@<topic>` QA gate green".
- `check: <command>` — run from the project root (`git -C <bank> rev-parse --show-toplevel`, else the
  bank's parent) with `MB_GOAL_CHECK_TIMEOUT` (default 900 s); met on exit 0. The checks of a criterion
  run only once all its plans are closed.
- A criterion is **met** when it has ≥ 1 link, every plan is closed and every check exits 0 (REQ-023).

`mb-goal-acceptance.sh [goal-path] [mb_path] [--tick | --ticks-only]` — the goal path argument already
exists; drive always passes its run's goal file (REQ-052):

| Goal | Mode | Output | Writes |
|---|---|---|---|
| no criterion carries a link | any | today's bytes `{"name","ok","findings"}` (REQ-043) | nothing |
| ≥ 1 link | default | `ok` from evidence, `findings` = labels of unmet criteria, plus `"unbacked": [labels ticked but unmet]`, `"criteria": [{"n","label","met","plans":[{"path","closed"}],"checks":[{"cmd","exit"}]}]` | nothing |
| ≥ 1 link | `--tick` | as default | the goal file: each linked criterion's box set to `met` (atomic replace) (REQ-042) |
| any | `--ticks-only` | today's checkbox count, no plan read, no check run | nothing |

An unlinked criterion in a goal with links is unmet (finding `no evidence link`). Exit stays 0 always
(ADR-3 check-runner contract); a malformed link line is a finding, never a crash. The firewall's
`acceptance` check (`scripts/mb-flow-verify.sh:344-350`) keeps reading `<bank>/goal.md` in the default
mode; drive skips it (C3.3 rule 15) because it has already judged its own goal file.

### C2 — Drive run file `<bank>/.drive/<run_id>.json` — owner `scripts/mb_drive_state.py`

```json
{
  "run_id": "20261015-…", "bank": "/abs/.memory-bank", "goal": "/abs/.memory-bank/goal.md",
  "session": "<host session id> | null",
  "phase": "planning | execution | stopped",
  "parallel": true, "parallel_reason": "default | serial-flag | pipeline | host",
  "approved": ["topic"], "steps": 0, "waits": 0,
  "items": {"plans/x.md": {"stalls": 0, "pivoted": false, "qa_blocked": 0, "deferred": false,
                           "qa_retried": false, "qa_reason": "", "work_runs": ["…"], "fix": false}},
  "final_qa": "pending | pass | blocked:<reason> | red", "final_qa_blocked": 0, "final_qa_cycle": 0,
  "stop_reason": "", "started": "<iso>", "updated": "<iso>"
}
```

- One file per run, path from `mbw_drive_slot <bank> <run_id>` — the per-run slot model of REQ-DR-034,
  now unconditional (a drive always has a run id) and moved under `<bank>/.drive/`. Each drive writes
  only its own file (atomic temp + `os.replace`), so runs never contend on state. Gitignored as
  `.memory-bank/.drive/`.
- **Run selection** for every subcommand but `start`: `--run-id R` → that file; no id → the only run
  whose phase is not `stopped`; several live runs and no id → exit 2 with one `run_id goal phase` line
  each; none → exit 1.
- **Live** = phase not `stopped`. `session` = `--session <id>`, else `$CLAUDE_CODE_SESSION_ID`, else
  `$MB_SESSION_ID`, else null (the hosts that expose one; `hooks/mb-session-turn.sh` reads the same).

### C3 — `scripts/mb-drive.sh` — the seam

```text
mb-drive.sh start   [--bank B] [--goal PATH] [--budget TOK] [--serial] [--host-serial] [--session ID] → prints run id
mb-drive.sh resume  [--bank B] [--run-id R]                                  → run_id=<id> goal=<path> phase=<phase>
mb-drive.sh phase   execution [--bank B] [--run-id R] [--approve t1,t2]       → exit 0 | 1 + one hint per gap
mb-drive.sh next    [--bank B] [--run-id R]                                  → ONE action line
mb-drive.sh returned --action "<line>" [--tokens N] [--outcome O] [--item-outcome <plan>=O]… [--work-run ID]… [--bank B] [--run-id R]
mb-drive.sh status  [--bank B] [--run-id R]                                  → JSON, never runs checks or the firewall
```

**C3.1 `start`.** Resolves the bank (`mb_resolve_path`); no bank → exit 1. Goal = `--goal PATH`
(absolute or bank-relative) or `<bank>/goal.md`. The default goal absent → scaffold `templates/goal.md`
and exit 1; an explicit `--goal` that does not exist → exit 1 (no scaffold at an arbitrary path);
`mb-goal-validate.sh <goal> <bank>` fails → exit 1 with its hints (both moved from today's
`commands/drive.md` fence). A live run whose `goal` has the same real path → exit 1:
`goal <path> is already driven by run <id> — resume it with /mb drive --resume <id>, or start on another goal file with --goal <path>` (REQ-051).
Mints the id with `mb-work-state.sh new-run-id`. `parallel`: `--serial` → false/`serial-flag`;
`drive.parallel: false` in the effective `pipeline.yaml` → false/`pipeline`; `--host-serial` →
false/`host` plus one stderr line `[drive] this host runs one dispatch at a time — items run serially through /mb work`
(REQ-033); else true/`default`. `--budget` → `MB_WORK_PARALLEL=1 mb-work-budget.sh init TOK --run-id <id>`
(the per-run budget slot). Writes `phase: planning`; prints the run id.

**C3.2 `phase execution`** — the planning gate (REQ-019, REQ-039). Refuses (exit 1, phase unchanged)
with one stderr line per gap: a criterion without a link; a `plan:` that resolves to no file; a plan
without a `qa:` frontmatter line (S1 C1); a wrapper whose spec `requirements.md` is not `status: ready`
and whose topic is not in `--approve` / `approved`; a `depends_on:` entry that names a plan neither
linked nor closed; a `spec:` line (hint: link the spec's wrapper plan). `--approve` topics are stored
in `approved` (the user's one-batch answer, D-02).

**C3.3 `next`** — items are the distinct `plan:` paths of the run's goal in goal order, then the run's
fix plans (C3.6). Facts per item: `closed` (C1), `deps` (plan frontmatter `depends_on:` resolved among
the items), `files` (union of `mb_work_waves.declared_files` over its pending work items),
`owned_by` (a live run of `MB_WORK_PARALLEL=1 mb-work-state.sh status --all` whose `source` is the
item path and whose id is not in the item's `work_runs`), plus the C2 record. Decision, first match wins:

| # | Condition | Action |
|---|---|---|
| 1 | phase `planning` | `plan` (finish the planning phase, then `phase execution`) |
| 2 | phase `stopped` | exit 1, `[drive] run <id> stopped: <stop_reason>` |
| 3 | goal, item, claim or budget input unreadable | `stop_human check-broke:<acceptance\|items\|claims\|budget>` |
| 4 | budget check exit 2, or `steps > 0` and `spent / steps > total − spent` | `stop_budget` (REQ-027) |
| 5 | an item with `stalls ≥ 2` | `stop_human stall` (REQ-025) |
| 6 | an item with `stalls == 1` and not `pivoted` | `pivot <item>` (REQ-025) |
| 7 | ready = open, not deferred, not owned elsewhere, every dep closed; `parallel` and the first wave of `mb_work_waves.assign_waves` over the ready items has ≥ 2 members | `team <item> <item>…` (REQ-021) |
| 8 | ready non-empty | `work <first ready item>` (REQ-021, REQ-022) |
| 9 | open items owned elsewhere and `waits < 3` | `wait <item> …` (REQ-055) |
| 10 | open items owned elsewhere and `waits ≥ 3` | `stop_human owned-elsewhere:<owning work run id>` (REQ-056) |
| 11 | a deferred item with `qa_retried` false | `qa <item>` (REQ-030) |
| 12 | a deferred item with `qa_retried` true | `stop_human qa-blocked:<qa_reason>` (REQ-031) |
| 13 | an item still open, or a criterion unmet (evidence, checks run now) | `stop_human acceptance-red:<n>` (first unmet criterion) |
| 14 | `final_qa` is `pending` and a linked plan says `qa: on` and `<bank>/qa/README.md` exists · `blocked:<r>` · `red` | `final_qa` (REQ-032) · `stop_human qa-blocked:<r>` · `stop_human qa-red` (REQ-054) |
| 15 | `mb-flow-verify.sh <bank> --skip acceptance` exit 0 / 1 / 2 | `stop_success` / `stop_human flow-red:<failed checks csv>` / `stop_human check-broke:<check>` (REQ-048) |

Rules 1–12 read files and run the claim listing only; checks run from rule 13 on, the firewall only at
rule 15 (NFR-001). The vocabulary has no `implement`, `repair` or review action and no cycle counter
(REQ-040). A team action passes the item paths; the orchestrator takes each item's `files` and its
recorded `work_runs` from `status` (REQ-041). An owned-elsewhere item is never a stall and is never
taken over (REQ-055).

**C3.4 `returned`** — after every non-stop action (REQ-026, REQ-042, REQ-044, REQ-030, REQ-055):

1. `--tokens N` (the usage the host reported for the dispatches of that run) →
   `MB_WORK_PARALLEL=1 mb-work-budget.sh add N --run-id <id>` when a budget exists; `steps += 1`.
   `--work-run ID` (repeatable) appends to the `work_runs` of the action's items.
2. `wait` → `waits += 1`; any other action → `waits = 0`.
3. Per item of a `work`, `team` or `qa` action (`--item-outcome` overrides `--outcome`; default `ok`):
   closed (C1) → `stalls = 0`; outcome `owned-elsewhere` (the work claim refused with exit 4) → no
   change; outcome `qa-blocked:<r>` → `qa_blocked += 1`, `qa_reason = r`, `deferred = qa_blocked ≥ 2`,
   and for a `qa` action `qa_retried = true`; any other outcome, `ok` and `stop_human:<why>` included
   → `stalls += 1`.
4. `pivot <item>` → `pivoted = true`. `final_qa` → C3.6.
5. `mb-goal-acceptance.sh <goal> <bank> --tick`.

**C3.5 `status`** (REQ-047) — `{run_id, goal, session, phase, parallel, parallel_reason, steps, waits,
budget:{total, spent}, items:[{path, heading, closed, ready, deps, files, owned_by, work_runs, stalls,
pivoted, qa_blocked, deferred, fix}], criteria:[{n, label, met, waiting_qa}], unbacked, final_qa,
final_qa_cycle, action}`; `heading` = the first pending work item's heading; `waiting_qa` = the
criterion links a deferred item; `action` = rule 1–14's action, or `firewall` where `next` would run
rule 15. `met` comes from `--ticks-only`, so `status` stays cheap.

**C3.6 Final QA and its fix cycle** — owner `scripts/mb_drive_qa.py` (REQ-032, REQ-053, REQ-054).
The final QA run id is `<run_id>-final<final_qa_cycle>`; its selection is `@<topic>` for each `topic:`
of the run's plans (wrapper: its spec topic), so one drive's final QA never runs another drive's cases.
On `returned --action final_qa`:

- outcome `qa-blocked:<r>` → `final_qa_blocked += 1`; the second sets `final_qa: blocked:<r>` (D-13,
  retry once).
- otherwise `mb-qa-bug.sh gate --run <final run id> --gate '<qa.gate>'`: exit 0 → `final_qa: pass`;
  exit 1 → `final_qa_cycle += 1`; when `final_qa_cycle > qa.max_cycles` → `final_qa: red`; else the
  blocking bugs (`mb-qa-bug.sh list --json --open --run <final run id>`) are grouped by the topic of
  their `- Scenario: qa/test_cases/<topic>/…` line and one fix plan per topic is written, added to
  `items` with `fix: true`, and `final_qa` returns to `pending`.
- Fix plan: `<bank>/plans/<date>_fix_drive-qa-<topic>-<run8>-<cycle>.md`, frontmatter `topic: <topic>`,
  `qa: on`, `drive_run: <id>`; one `<!-- mb-stage:1 -->` stage "Fix final-QA bugs" whose body quotes each
  bug id, title, steps and evidence path, with the `/mb work` §5c2 instruction "regression test first
  when the defect is reachable from tests; never edit `<bank>/qa/`", and one DoD line per bug:
  `BUG-NNN fixed — regression test carries mb:case reg-bug-nnn; mb-qa-bug.sh set BUG-NNN fixed`. A bug
  without a resolvable Scenario goes into a plan with topic `drive-<run8>` and `qa: off — no case`.
- The fix plan is an ordinary item: `work <fix plan>` runs `/mb work`'s own implement → verify → §5c2 QA
  (`@<topic>`, bounded by `qa.max_cycles` inside the item) → flip. Drive adds no fix chain and no check;
  the outer bound is `qa.max_cycles` final-QA cycles.

### C4 — Stop telemetry and resume gate — owners `scripts/mb-drive-stop.sh`, `hooks/mb-drive-resume-gate.sh`

- `mb-drive-stop.sh record [--run-id R] --action "<line>"` selects the run like C2, sets
  `phase: stopped` and `stop_reason` in its run file, then the existing two sinks (the `mb-flow` fence
  through `mb-flow-sync.sh`, `progress.md` through `mb-work-progress-append.sh`). The closed vocabulary
  gains `human:stall`, `human:acceptance-red:<n>`, `human:flow-red:<checks>`, `human:qa-blocked:<reason>`,
  `human:qa-red`, `human:owned-elsewhere:<id>` (tokens `[A-Za-z0-9._,:-]`); `state` / `path` print the
  run file. `arm` and the old `.drive-state` singleton go with the preflight (T5), their only callers.
- Resume gate, first match wins: kill-switch / sentinel → allow; bad stdin → allow;
  `stop_hook_active` → allow; no bank → allow; candidates = run files under `<bank>/.drive/` with
  phase `execution` — none → allow; the hook input's `session_id` matches some candidates' `session` →
  those; else, with a `session_id`, the candidates with no `session`; with no `session_id` from the
  host, every candidate (REQ-045, scenario 6); none → allow; one candidate whose
  `mb-goal-acceptance.sh <goal> <bank> --ticks-only` is `"ok":false` → block naming its run id; several
  → allow with one stderr warning listing them (REQ-045). `MB_WORK_RUN_ID`, the fence and the work-state
  cycle are no longer read (I-270, I-272). The header lists the hosts that call it: Claude Code
  (`settings/hooks.json`) and Codex (`hooks/mb-codex.py:152`) (I-274).

### C5 — Commands — owners `commands/drive.md`, `commands/goal.md`, `commands/mb.md`, AGENTS.md line

- Bundle and bank resolution in every fence (REQ-046): `SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"`
  plus the bundle check from `commands/sdd.md`, then `. "$SKILL_DIR/scripts/_lib.sh"; BANK="$(mb_resolve_path "${BANK:-}")"`.
  Replaces `commands/drive.md:34`, `commands/goal.md:40-41` and `commands/mb.md:1717`.
- `commands/drive.md`: `/mb drive [--goal PATH] [--budget TOK] [--serial] [--host-serial] [--resume [RUN_ID]]`;
  §1 start or resume (several live runs → list, ask for the id); §2 planning phase (tier per
  `references/effort-tiers.md`; `/mb plan <type> <topic> --tier T`; large/extra `/mb sdd <topic> --auto`
  — Step 0 self-interview, assumptions recorded — then the wrapper, S1 REQ-011; QA target question
  when `qa/README.md` is absent; links under each criterion; one approval batch; `phase execution
  --approve …`); §3 execution loop with the C3.3 action table, `--run-id` on every call; §4 executing
  `work`: `MB_WORK_PARALLEL=1`, the plan path as the positional `<source>` of `mb-work-state.sh init`
  (path-keyed claim, S2 C2), resume the item's recorded live work run instead of minting a new one,
  claim exit 4 → `returned --outcome owned-elsewhere`, never `--takeover`; executing `team` (team init
  `drive-<run8>` `--no-goal`, one `track add --source <plan> --files <csv>` per item, the brief filled
  from the goal and the plans, the planning approval stands for `team plan`, the team loop until
  `stop_success` or `stop_human`, `team close`); `wait` (sleep `MB_DRIVE_WAIT_SECONDS`, default 300,
  then `returned --action "<line>"`); `final_qa` (`/mb qa run` with the selection and run id of C3.6);
  §5 tokens, work run ids and `returned`; §6 stop recording and the final report (done, not verified,
  unbacked ticks, waiting for QA, open QA bugs, one question); §7 hosts — dispatch through `SKILL.md`
  § Invocation, parallel tracks per `commands/team.md` §9, `--host-serial` for a host that runs one
  dispatch at a time; §8 resume and several drives in one bank (`--goal`, one goal file per drive).
- `commands/goal.md`: the link grammar of C1, `--goal` goal files, and the resolution fence.
  `templates/goal.md`: one linked example criterion in the comment block.
- `commands/mb.md` drive row and § drive, and the AGENTS.md drive line
  (`adapters/_lib_agents_md.sh:218`): the same flags and actions (REQ-050).

## Contract

**Seams:**
- `scripts/mb-drive.sh` — the existing drive CLI (`start`, `resume`, `phase`, `next`, `returned`, `status` action and JSON lines); every drive requirement is observable through it.

`mb-goal-acceptance.sh` (C1) and the resume gate (C4) are existing collaborators behind that seam, not
new seams: drive reads acceptance through C3, and the gate reads only what C3 writes. Confirmed by the
user on 2026-10-15.

## Decisions

- **D1 — Drive dispatches plans, not work items.** `/mb work <plan>` runs the whole plan with its own
  cycles, verify cadence and QA; drive only sees "closed or not". This is what removes the second chain
  (I-265) and the unbounded `implement` (I-266) and leaves `max_cycles` with `/mb work` (I-270).
- **D2 — A spec is linked through its wrapper plan.** S1 REQ-011 always gives an executed spec a
  wrapper that carries `qa:` and the run instructions; one link kind keeps the gate, closure and team
  source to one path. A `spec:` line is reported by the gate with the hint to link the wrapper.
- **D3 — Closure = every resolved work item done.** The flip is gated by `/mb work`; reading it reuses
  `mb_work_items` and adds no verifier dispatch (NFR-001). Moving a plan to `plans/done/` stays with
  `/mb done`; a link survives the move through the `plans/done/<basename>` fallback.
- **D4 — Stall = an item's run returned and the item is not closed.** Context D-08 phrases it as
  "acceptance did not grow"; a criterion that links two plans would then stall on the first plan's
  success. Per item, closure is the growth of evidence that drive can attribute.
- **D5 — The drive budget lives in the per-run slot.** `MB_WORK_PARALLEL=1` on drive's own budget
  calls, so a drive budget never shares a file with a `/mb work` budget or another drive's.
- **D6 — One run file per drive, several drives per bank (user decision 2026-10-15).** The per-run slot
  model of REQ-DR-034 (`mbw_drive_slot`) is kept and retargeted to `<bank>/.drive/<run_id>.json`; the
  preflight script and the `.drive-state` singleton disappear. Run selection by `--run-id` or "the only
  live run" keeps the single-drive case flag-free.
- **D7 — Final QA bugs are fixed through ordinary `/mb work` items (user decision 2026-10-15).** One fix
  plan per owning case topic, `qa: on` with that topic, so `/mb work` runs its own §5c2 loop on it; drive
  only writes the plan from the bug registry and bounds the cycles with `qa.max_cycles`. No drive fix
  chain, no drive check. A spec-backed topic gets a separate fix plan instead of a new task in the
  accepted `tasks.md`.
- **D8 — Checks are lazy.** `check:` commands run when a criterion's plans are closed and from rule 13
  of `next`; `status` and the resume gate never run them.
- **D9 — A second drive uses its own goal file: `--goal <path>`, default `<bank>/goal.md`.** Today the
  goal is one file per bank (`scripts/mb-goal-acceptance.sh:61-62`, `scripts/mb-goal-state.sh:13`,
  `scripts/mb-flow-verify.sh:350`, `scripts/mb_team_status.py:214`). Drive stores the path and passes it
  to `mb-goal-validate.sh` and `mb-goal-acceptance.sh`, which already take one; the firewall runs with
  `--skip acceptance` because drive judged its goal at rule 13. `mb-goal-state.sh`, the done gates and
  `/mb team --goal` keep `<bank>/goal.md`.
- **D10 — `/mb work` under drive always uses per-run work slots.** Two drives, or a drive and a team,
  would otherwise share the singleton `.work-state.json`. With `MB_WORK_PARALLEL=1` and the plan path as
  the claim key, a second claimant gets exit 4, which drive turns into "owned elsewhere" (rule 9/10).
  Drive tells its own claims from foreign ones by the work run ids recorded with `--work-run`.

## Quality DoD

Rule sources (resolved by `scripts/mb-rules-resolve.sh`, referenced — never copied):
- [project] .memory-bank/RULES.md
- [profile] .memory-bank/rules-profile.json
- [project] AGENTS.md

Review rubric (from `pipeline.yaml:review_rubric`):
- logic: Every EARS requirement has at least one assertion in tests
- logic: Edge cases from requirements covered
- code_rules: SOLID: SRP — files <300 lines OR <=3 public methods
- code_rules: No placeholders (TODO/...)
- code_rules: Imports complete, functions copy-paste ready
- security: Input validation at boundaries
- security: No secrets in code
- security: No raw SQL string concat
- scalability: No N+1 queries introduced
- scalability: Async where IO-bound
- tests: Contract-first: Protocol/ABC defined before impl
- tests: Integration tests > unit tests (Testing Trophy)
- tests: No test.skip / describe.skip

Checker: `bash scripts/mb-rules-check.sh --files <touched-files-csv> --out json` — no violations
on this item's touched files.

## Eval declarations

Each Eval names a new focused test file (absent now → `pending_materialization` at generation; `/mb work`
writes it first and observes the red) plus the existing suites in the task's Scope. Anchors are the
runner's own failure line plus the task's test family prefix. The five lines below are byte-identical to
the Eval lines in `tasks.md`.

- **T1** — evidence acceptance (family `goal_evidence:`):
  **Eval:** bats tests/bats/test_goal_evidence.bats tests/bats/test_mb_goal_acceptance.bats — red: bats file materialised, mb-goal-acceptance.sh reads no plan or check links, has no tick modes and reports no unbacked ticks, so every named case goal_evidence fails; exit: 1; output~: not ok [0-9]+ goal_evidence:
- **T2** — drive brain:
  **Eval:** python3 -m pytest -q tests/pytest/test_mb_drive_brain.py tests/pytest/test_s2_file_size_contract.py — red: test file materialised, mb-drive.sh has no start, resume, phase or returned subcommand, keeps no run file per drive and next still prints implement, so the brain tests fail; exit: 1; output~: FAILED tests/pytest/test_mb_drive_brain.py
- **T3** — stop record and resume gate (family `drive_gate:`):
  **Eval:** bats tests/bats/test_drive_stop_gate.bats tests/bats/test_mb_drive_stop.bats tests/bats/test_mb_drive_resume_gate.bats — red: bats file materialised, the stop record writes no run file and the resume gate still keys on MB_WORK_RUN_ID and ignores the hook session, so every named case drive_gate fails; exit: 1; output~: not ok [0-9]+ drive_gate:
- **T4** — final-QA fix cycle:
  **Eval:** python3 -m pytest -q tests/pytest/test_mb_drive_final_qa.py tests/pytest/test_s2_file_size_contract.py — red: test file materialised, a final QA with a blocking bug writes no fix plan and returned never sets final_qa red, so the final QA tests fail; exit: 1; output~: FAILED tests/pytest/test_mb_drive_final_qa.py
- **T5** — commands, docs and cleanup (family `drive_cmd:`):
  **Eval:** bats tests/bats/test_drive_command_contract.bats tests/bats/test_mb_drive_command.bats — red: bats file materialised, drive.md still documents implement, repair and max cycles, resolves the bundle through dirname and calls the preflight script, so every named case drive_cmd fails; exit: 1; output~: not ok [0-9]+ drive_cmd:

## Risks & mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| A plan's DoD boxes ticked by hand count as closure | M | M | `/mb work` is the only writer drive asks to run; unbacked goal ticks are reported; the firewall's tests/lint/qa checks still gate `stop_success` |
| The host reports no token usage, so `stop_budget` cannot fire | M | M | `returned` without `--tokens` warns once on stderr; drive.md tells the orchestrator to sum the dispatch usage the host shows |
| `check:` commands are slow (a full suite) | M | L | lazy evaluation (D8); `MB_GOAL_CHECK_TIMEOUT` |
| A halted work run of another drive keeps its claim live for ever | M | M | three waits, then `stop_human owned-elsewhere:<id>` names the owner (REQ-056); never `--takeover` |
| Another drive's open QA bugs turn this drive's firewall `qa` check red | M | M | the final QA is scoped to the run's topics; a red `qa` check outside them is reported as `flow-red:qa` with the bug ids, a human decision |
| Two drives link the same plan | L | L | the work claim serialises them; the second sees owned-elsewhere, waits, then finds the plan closed (evidence is shared) |
| Removing `--route/--phase/--max-cycles` breaks a user's habit | L | L | `start` refuses unknown flags with the new usage; CHANGELOG line |
| Existing drive tests encode the old table (`tests/bats/test_mb_drive.bats`, command/stop/gate suites) | H | M | each task replaces the suite of the files it owns; the full suite runs once at the end of the spec |
| Team under drive asks for a brief and `team plan` confirmation | M | M | drive.md §4: drive fills the brief from goal and plans; the planning approval stands for `team plan` |
| `mb-flow-verify.sh` runs twice at the end (team's last `next`, then drive's rule 15) | M | L | accepted: one per owner, both pre-existing; drive's run is the done authority |

## Edge cases

- A criterion with only `check:` links: met as soon as its checks pass; no item, so no dispatch.
- Two criteria link the same plan: one item; both criteria wait on it.
- A ready item whose plan declares no `Files:`: `assign_waves` gives it a wave of its own → `work`, never in a team.
- A team `stop_human claim:<id>` (overlap despite `Files:`): a stall of the unclosed items → pivot (context Edge Cases).
- A dependency on a deferred item: the dependent is not ready; rule 11 retries the deferred QA first.
- A fix plan that itself stalls twice: `stop_human stall` like any item.
- The user edits code during the run: `/mb work` and `/mb team` scope diffs and commits; drive touches only its run file, its goal ticks and its fix plans.
- `next` while `phase: planning` prints `plan`; `returned` in the planning phase exits 2.
- A legacy goal without links: `phase execution` refuses it (REQ-019) — legacy goals keep working with `mb-flow-verify.sh` and `/mb team --goal`, not with the new drive.
- `--goal` pointing at `<bank>/goal.md` by another spelling: compared by real path, refused like the default.

## Open questions

- none — seam, the final-QA fix cycle and several drives per bank were decided by the user on 2026-10-15.
