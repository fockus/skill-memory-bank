---
type: spec-design
topic: mb-team
status: draft
created: 2026-10-10
linked_requirements: requirements.md
linked_examples: examples.md
---

# Design: mb-team

## 1. Shape

`/mb team` is a thin orchestration layer. The host agent (the orchestrator) is the runtime; scripts are a stateless
brain (`mb-team.sh next`) plus single-writer state (`team.json`), the same split as `/mb drive`.

```
user ──► orchestrator (Claude Code / Codex / Pi main session)
          │  /mb team init <topic>        → team.json + brief.md (+ goal check)
          │  /mb team track add …         → resolved pipeline per track (layers + provenance)
          │  /mb team plan                → table, waves, readiness checks, mismatches → user confirms
          │  loop:
          │    mb-team.sh next            → dispatch D1 · dispatch D2 · verify D3 · review D3 · wait · collect · team_review · stop_*
          │    execute each action with host tools (parallel Agent calls, run_in_background)
          │    track returns              → mb-team.sh track set <id> --status … --summary-file …
          │    board / reports            → relay findings (SendMessage), redirect, ACK
          │  /mb team checkpoint · commit (scoped, y/N) · review cycles · collect
          │  stop_success only over goal acceptance 100 % + mb-flow-verify exit 0
          ▼
tracks (role agents) ── edit integration tree ── mb-lock.sh run <res> -- <cmd> ── board STATUS/BLOCKED/HANDOVER ── report file
```

Everything the tracks share — rules, contract, resources, limits — is in one brief; each track prompt is short and links it.

## 2. Files

| File | New/changed | Purpose | Layer |
|---|---|---|---|
| `scripts/mb-team.sh` | new | dispatcher: init, track, plan, prompt, next, status, collect, commit, close, known-red | interface |
| `scripts/mb_team_state.py` | new | `team.json` schema, locked atomic writes, status machine, readiness (`next`) | application |
| `scripts/mb_team_pipeline.py` | new | layered pipeline resolution + provenance; reuses `mb_work_models.resolve_model` | application |
| `scripts/mb_team_config.py` | new | reads `team:` from the resolved pipeline (`mb-pipeline.sh path`), emits resource / preset JSON | infrastructure |
| `scripts/mb_team_render.py` | new | brief / track prompt / external-review prompt rendering | application |
| `scripts/mb_team_status.py` | new | status table + JSON (team.json + board + reports + locks + goal) | application |
| `scripts/mb_team_ops.py` | new | collect, commit, close (through `mb_vcs.sh`, `mb-coord.sh`, `mb-work-progress-append.sh`) | application |
| `scripts/mb-team-review.sh` | new | review cycle dirs, gate, external prompt, ingest | interface |
| `scripts/mb-team-checkpoint.sh` | new | checkpoint create / verify | interface |
| `scripts/mb_vcs.sh` | new | VCS seam (git, arc) | infrastructure |
| `scripts/mb-lock.sh` | new | resource locks CLI | interface |
| `scripts/mb_lock_queue.py` | new | ticket queue, liveness with process start time, status JSON | infrastructure |
| `templates/team/{brief,track-prompt,external-review}.md` | new | templates | — |
| `commands/team.md` | new | `/mb team` command contract | — |
| `scripts/mb-coord.sh` | changed | BLOCKED, COMMIT, `--track`, `tracks --json` | — |
| `scripts/mb_pipeline_minimal_yaml.py`, `scripts/mb_pipeline_validate_team.py` (new), `mb_pipeline_validate_core.py` | changed | parse + validate `team:` in both PyYAML and stdlib paths | — |
| `references/pipeline.default.yaml` | changed | bundled `team:` presets and review defaults, no resources | — |
| `scripts/mb-workflow.sh` | changed | `--lenses <csv>` → JSON `review_lenses` | — |
| `scripts/mb-work-plan.sh` | changed | `--step-model role=model` (repeatable) → JSON `step_models` | — |
| `commands/work.md` §5d | changed | ensemble dispatches only `review_lenses` when present (one line) | — |
| `scripts/mb-work-review-parse.sh`, `mb-work-severity-gate.sh`, `agents/mb-reviewer-lead.md` | changed if Q3 = A | optional `medium` severity | — |
| `scripts/_lib.sh` | changed | `mb_resolve_path` fallback: cwd inside a bank returns that bank (root cause of the nested-bank lesson) | — |
| `commands/mb.md`, `SKILL.md`, `docs/pipeline-yaml.md`, `references/scripts.md`, `references/coordination.md`, `CHANGELOG.md` | changed | one row / one section each | — |

## 3. Contracts (frozen before implementation — change only through the plan's HANDOVER rule)

### C1. `team.json`

```json
{
  "schema": 1, "topic": "sso-20261010", "created": "2026-10-10T09:12:00Z",
  "goal": "G-001", "plan": "plans/2026-10-09_feature_onprem-corporate-sso.md",
  "tree": "/Users/me/arcadia-int", "mirror": "/Users/me/arcadia3", "vcs": "arc",
  "baseline": "133e077c0755559b750221e967317f623e049c5f",
  "brief": "reports/sso-20261010/brief.md", "max_parallel": 6, "budget_run_id": null,
  "known_red": [{"id": "library/harness TestRace", "reason": "trunk data race", "since": "2026-10-09"}],
  "known_open": ["YDB recipe timeouts on Mac (environment)"],
  "tracks": [{
    "id": "A", "task": "...", "role": "backend", "agent": "mb-backend", "size": "standard",
    "source": null, "files": ["neuroexpert/backend/harness-admin/**"], "deps": [], "resources": ["build"],
    "pipeline": {"mode": "direct", "tdd": "required", "verifier": "plan-verifier", "review": "none", "lenses": [],
                 "models": {"executor": "sonnet", "verifier": "sonnet"}, "effort": "medium"},
    "provenance": {"mode": "preset:standard", "models.executor": "prompt"},
    "prompt": "reports/sso-20261010/tracks/A.prompt.md", "report": "reports/sso-20261010/A.md",
    "status": "planned", "run_id": null, "fix_cycle": 0, "collected": false,
    "dispatched_at": null, "returned_at": null, "summary": null
  }],
  "reviews": [{"cycle": 1, "scope": "team", "master": "review/cycle-1/master.json", "verdict": "CHANGES_REQUESTED",
               "counts": {"blocker": 0, "major": 2, "medium": 3, "minor": 9}}],
  "checkpoints": [{"id": "2026-10-10-0944-S1", "label": "S1", "manifest": "...", "sha256": "..."}],
  "commits": [{"hash": "ba6a8066", "tracks": ["A", "B"], "files": 67}]
}
```

Track status machine: `planned → dispatched → returned → verifying → reviewing → done | done_with_concerns`;
any state `→ blocked | needs_context | cancelled`; `reviewing → fixing → returned` (bounded: `fix_cycle` at `team.review.max_cycles` → `stop_human fix-cycles:<id>`).
`verifying` and `reviewing` mean "in progress": `next` answers `wait` for them, and the orchestrator moves the track on
(after a passed verifier to `reviewing` or `done`; after the review to `done`, `done_with_concerns` or `fixing`, re-dispatching the track itself).
`done | done_with_concerns → fixing` is allowed for a team-review fix.
Ids match `^[A-Za-z][A-Za-z0-9_-]{0,15}$`. Paths are bank-relative in the file, absolute when rendered; `--source`
and `--plan` take a bank-relative or absolute path, `team.checkpoint.dir` is bank-relative. `track add` refuses a dep
that is not yet a track, so dependencies are added before the tracks that depend on them.

Optional fields added during implementation (readers treat them as absent when missing):
- team: `title`, `host` (model-profile host, default `claude-code`), `team_attrs` (the `init` pipeline layer),
  `team_review` (`init --team-review`), `brief_sha256` (last rendered brief; the tracks table is redrawn only while the
  brief is unchanged), `closed`;
- track: `title`, `dod` (list, required by the renderer), `layers` (the per-layer attribute values behind provenance);
- review: `actions` (from `mb-team-review.sh gate`), `at` (time of the gate). `reviews[]` is written only by
  `mb-team.sh review gate` (same cycle overwritten); `next` reads it and stays stateless.

### C2. Pipeline resolver

`python3 mb_team_pipeline.py resolve --mb <bank> --size <s> [--team k=v]… [--attr k=v]… [--prompt k=v]… [--host H] --json`

Keys: `mode work tdd verifier review lenses models.executor models.verifier models.reviewer models.lead models.lenses
models.lens.<name> effort`. Output: `{"pipeline": {...}, "provenance": {...}, "warnings": [...]}`; exit 2 on an unknown
key or value, naming it. `review=lenses:logic,security` is shorthand for `review=lenses` + `lenses=[logic,security]`. `mode=work:light` is shorthand for `mode=work` + `work=light`.
Lens names are the `focus` values of `review_ensemble.reviewers` (`logic tests code_rules security scalability`) plus
the alias `quality` → `code_rules`.

### C3. Resource JSON

`python3 mb_team_config.py resource <name> --mb <bank> --json` → exit 0 / 3 unknown / 2 invalid:

```json
{"name": "build", "kind": "mutex", "scope": "host", "path": "/tmp/mb-locks/build",
 "preconditions": {"free_disk_gb": 25, "disk_path": "/System/Volumes/Data", "check": "test -x ./ya"},
 "stop_threshold": {"free_disk_gb": 12, "check": null}, "maintenance": "./ya gc cache",
 "watch_interval_s": 30, "poll_s": 5}
```

Check polarity: `preconditions.check` exit 0 = ok; `stop_threshold.check` non-zero exit = the stop threshold is
breached (same polarity: exit 0 = ok).
`scope: host` → `${MB_LOCK_DIR:-${TMPDIR:-/tmp}/mb-locks}/<name>`; `scope: bank` → `<bank>/.locks/res/<name>`.
`mb-lock.sh` also accepts `--resource-json <file>` so it is testable without a pipeline.

### C4. Lock status JSON

`mb-lock.sh status [<name>] --json` →
`{"resources":[{"name","held","holder":{"owner","pid","child","host","since","age_s","cmd","alive","lease_until"},
"queue":[{"owner","pid","since","wait_s","position"}],"free_disk_gb","preconditions_ok","stop_breached"}]}`.
`cmd` is the program name only (no arguments: they may carry secrets, and holder details reach the board).

### C5. Board grammar extension

| Heading | Cancelled by |
|---|---|
| `## BLOCKED · <date> · <scope>` | a later `## ACK ·` with the same scope |
| `## COMMIT · <date> · <scope>` | — (informational: hash + scoped files in the body) |

`append --track D3 --type STATUS --title 'disk 12 GiB'` writes `## STATUS · 2026-10-10 · D3: disk 12 GiB`.
`mb-coord.sh tracks --json` → `{"tracks":{"D3":{"type","date","title","open"}},"open_blocked":[…],"open_handover":[…]}`.
Track attribution is the `<ID>:` prefix of the scope; legacy entries without it are ignored by `tracks`.

### C6. VCS seam

`mb_vcs.sh <op> --tree <dir>` with ops `kind root head diff <base> changed <base> untracked add -- <files>
commit -m <msg> -- <path>... show <rev>:<path>`. `commit` commits only the listed paths (git: `git commit --only -m <msg>
-- <paths>`; arc: path-limited `arc commit`), so a file a parallel session staged stays staged and out of the commit;
no paths → exit 2 (no whole-index commits from mb-team).
`changed` and `untracked` print NUL-separated raw paths (git: `-c core.quotePath=false diff --name-only -z
--no-renames`, so a rename lists both sides); `untracked` excludes ignored files. Detection: `git -C <dir> rev-parse --show-toplevel`,
else `arc root` in `<dir>`; `team.vcs` / `MB_VCS` override. Arc mapping (`arc diff`, `arc status --short -u all`,
`arc add`, `arc commit -m <msg> <paths>`, `arc rev-parse HEAD`) is verified against the real `arc` in Stage T-VCS and covered in CI
by a PATH shim. No other script calls git or arc directly for team operations.

## 4. Track pipeline

**Presets by size** (bundled; a project replaces any of them in `pipeline.yaml` `team.presets`):

| Size (effort tier) | mode | tdd | verifier | review | executor | effort | Why |
|---|---|---|---|---|---|---|---|
| trivial | direct | optional | none | none | mid | low | one-command check |
| small | direct | required | none | none | mid | medium | one test per behavior, self-check |
| standard | direct | required | plan-verifier | none | mid | medium | the `medium` depth (one verifier) without driving `/mb work` |
| large | work | required | plan-verifier | lenses (all five) | premium | high | AGR-097 (Anton): same depth as `extra`; judge stays a `/mb work` option |
| extra | work | required | plan-verifier | lenses (all five) | premium | high | the `governed` depth; judge stays a `/mb work` option |

Both `mode: work` presets set `work: orchestrated`; a track may pick `work: light` (`--mode work:light`).

Default size when none is given: the orchestrator estimates it per `effort-tiers.md` and states it in one line; a task
touching security, money, user data or reliability is `extra` (tier rule 4). `standard` is open question Q1.

**Layers** (later wins, provenance recorded): preset(size) → `team.overrides` → `init` attributes → `track` attributes →
`--layer prompt`. A prompt value that lowers a field below the size preset is accepted (an explicit user request beats
the estimate, tier rule 2) and shown as a warning in `/mb team plan`.

**Prompt vocabulary** (the orchestrator maps explicit phrases only; everything else is asked):

| Phrase (ru / en) | Key = value |
|---|---|
| «через /mb work», «по движку», "via mb work" | `mode=work` |
| «без work», «напрямую», "direct" | `mode=direct` |
| «облегчённо», "light" · «оркестратор ведёт», "orchestrated" | `mode=work` + `work=light` · `mode=work` + `work=orchestrated` |
| «без TDD», «тесты не обязательны» | `tdd=optional` |
| «с верификатором» / «без верификатора» | `verifier=plan-verifier` / `none` |
| «без ревью» / «одним ревьюером» / «линзами [logic, security]» | `review=none` / `single` / `lenses[:…]` |
| «на opus», «исполнитель sonnet», «ревью на opus» | `models.executor=opus`, `models.reviewer=opus` |
| «трек маленький / стандартный / крупный» | `size=small|standard|large` |
| «effort high», «думай глубже» | `effort=high` |

**`mode: work` reuses the engine** (open question Q4 confirms the orchestrator-driven variant):

| Track pipeline | `mb-workflow.sh` flags |
|---|---|
| verifier none, review none | `--workflow simple` |
| verifier plan-verifier, review none | `--workflow medium` |
| review single | `--workflow complex` (+ `--verify off` when verifier none) |
| review lenses | `--workflow governed --no-judge --lenses <csv>` (+ `--judge` only when the prompt asks) |

Models go through `mb-work-plan.sh --model <executor> --step-model verifier=… --step-model reviewer=…`. The orchestrator
exports `MB_WORK_PARALLEL=1`, mints a run id per track (`mb-work-state.sh new-run-id`), stores it in `team.json`, and
follows `commands/work.md` unchanged. Claim refusal (exit 4) maps to `stop_human claim:<track>`.

**`mode: direct` post-steps.** The track prompt file is a single-stage plan (`<!-- mb-stage:1 -->` around task + DoD), so
`plan-verifier` takes it as `Source file` with `Source kind: plan`. The diff is
`mb-work-diff.sh --run-id team-<topic>-<id> --baseline <team baseline> --files "<changed ∩ track globs>"`. Review uses
the same diff; the severity gate gets `--gate` from `team.review.clean_when` for lens review or the pipeline
`review.severity_gate` for single review.

**Effort.** Claude Code takes effort from the agent's `effort:` frontmatter; when the resolved effort differs,
`/mb team plan` prints the mismatch (REQ-TEAM-018). Codex and Pi pass it as `thinking`.

## 5. Resources and `mb-lock.sh`

**On disk** (`<path>` from C3):

```
<path>.lock/meta.json   holder: owner, token, pid, pid_start, child, child_start, host, since, cmd, lease_until
<path>.queue/<seq>-<pid> ticket: owner, pid, pid_start, since
<path>.seq + <path>.qmutex   ticket counter under the existing mb_lock_acquire (short critical section)
```

**`run <res> --owner <id> [--wait S] [--no-maintenance] -- <cmd…>`**

1. Take a ticket. Trap EXIT/INT/TERM/HUP: remove the ticket, forward TERM to the child, release only an own lock
   (token check) — the `with-build-lock.sh` behaviour.
2. Poll every `poll_s`: prune tickets whose pid is gone or whose `ps -o lstart=` no longer matches; when this ticket is
   the oldest live one and `mkdir <path>.lock` succeeds, write `meta.json` and drop the ticket. Every 12 polls print
   `waiting #2 behind D3; held by R since 12:56 (43m): ./ya make …`. `--wait 0` (default) waits while alive; `--wait S`
   gives up with exit 75 and the command is not run.
3. Check `preconditions`. On failure run `maintenance` (unless `--no-maintenance`), re-check; still failing → release, exit 77.
4. Start the command in the background, record `child` + `child_start`, poll `stop_threshold` every `watch_interval_s`. On breach:
   TERM the child, wait, release, `mb-coord.sh append --type BLOCKED --track <owner> --title 'resource <res>: stop condition'`,
   exit 76. Otherwise exit with the child's status.

**Liveness and reclaim.** A holder is alive while `pid` or `child` is alive with a matching start time (EPERM counts as
alive, `mb_pid_alive`). Nobody removes a live holder's lock. A provably dead holder (both processes gone, same host) is
reclaimed by the queue head with a board STATUS entry — open question Q2; under option A only `break` removes it.

**`acquire <res> --owner <id> --lease S` / `release <res> --token T`** for multi-command holds: no pid liveness, the
lease bounds the hold; an expired lease is shown red in `status` and never auto-reclaimed — the orchestrator runs
`break`. `maint <res> --token T` runs the maintenance command for a lease holder only.

**`watch <res> [--interval S]`** — the background disk guard: edge-triggered board STATUS entries when `preconditions` turn
false or `stop_threshold` is breached, and when they recover. **`break <res> --reason R`** — orchestrator only; refuses a live
holder; posts a board entry.

**Exit codes** 0 / child status · 1 corrupt lock or refused release · 2 usage or config · 75 wait timeout ·
76 stop condition · 77 start preconditions unmet. Free disk: `df -Pk <disk_path>` (POSIX), parsed in Python.

**The abandoned-wait race** came from polling without order (a lock freed after R went to whoever polled first, T515,
not to D3 who had waited longest) and from a foreground wait that the agent gave up. The queue fixes the order; the
brief tells tracks to start `mb-lock.sh run` in the background (`run_in_background` in Claude Code) and keep writing
code and tests; `status` shows every wait time, so the orchestrator sees starvation.

## 6. Coordination

- Tracks write only to: their files, their report, the board (`STATUS` on start and finish, `BLOCKED`, `HANDOVER → ORCH`
  for contract changes or findings that affect others). They never message other tracks.
- The orchestrator reads `mb-team.sh next` / `status` after every track return and on every board change it is told
  about, then relays (`SendMessage` to the running track with the finding and the decision), redirects (new instruction),
  or ACKs a BLOCKED/HANDOVER. Hosts without mid-flight messaging relay at the track boundary: the next dispatch of the
  affected track carries the addendum.
- The inter-track contract lives in the brief and is published as `FREEZE · contract:<topic>` at `init`; a change is a
  HANDOVER from a track, a decision by the orchestrator (with the user when it changes an agreement), a new brief section
  and `LIFT` + new `FREEZE`.

## 7. Checkpoints and commits

`/mb team checkpoint [label]` writes into `team.checkpoint.dir` (bank-relative, default `backups/team`):
`<YYYY-MM-DD-HHMM>-<topic>-<label>.diff` (binary-safe diff from baseline), `…-untracked.tar.gz` (untracked, not
ignored, under `max_untracked_mb`), `…-manifest.json` (tree, vcs, head, baseline, files, sizes, skipped_large),
`…sha256` (sha256sum format, computed with hashlib). It warns when the directory is tracked by the bank repository.
`checkpoint.extra` (optional) runs after it, e.g. a stand snapshot. `--verify <id>` recomputes hashes; restore commands
are printed, never run.

`/mb team commit --tracks A,B -m <msg> [--yes]`: files = changed ∩ globs of the selected tracks; refuses unfinished
tracks, open BLOCKED/HANDOVER for them, and files co-owned by an unfinished unselected track; lists excluded foreign
files; asks y/N (default No; `--yes` for non-interactive); commits exactly that list through the seam (`commit -m <msg> -- <paths>`); appends a
`COMMIT` board entry with hash and files. No push path exists.

## 8. Review

**Team review cycle** — opt-in (`team.review.enabled`, default false in the bundled block; `init --team-review` turns it on for one run), because five lenses plus a lead per cycle is the most expensive path (design principle 7).
`mb-team-review.sh start --cycle N [--lenses …] [--range <base>..<rev>]` creates
`review/cycle-N/brief.md` (object, diff command, decisions to check, known open items, format). The orchestrator
dispatches the lens reviewers in parallel and then `mb-reviewer-lead` with the previous master (closure check first),
saves `master.json` / `master.md`. `gate --cycle N` → 0 clean (`clean_when`, default blocker 0, major 0, medium 0),
1 fixes needed (issues grouped by owner track → `fix <track>` actions), 2 broken input; `mb-team.sh review gate`
records the result in `team.json` `reviews[]`. `max_cycles` (default 5)
exhausted → `stop_human review-cycles`.

**External reviewer.** `external --name astra --cycle N` renders `review/external-astra-cycle-N/prompt.md`: role
("independent auditor, does not edit code"), object (commit, mirror vs working tree, read committed versions with
`show`), what to read, lenses, prior-closure duty, output files `findings.json` + `prior-closure.json` with the schema.
The user runs it; `ingest --name astra --cycle N` validates both files and adds them as an aspect report to the next
lead cycle.

**Severity.** The skill scale is blocker/major/minor; the practice used medium too (open question Q3).

## 9. `next` actions and stop

`next` prints one action per line, in priority order:
`stop_human <why>` (blocked/needs_context track, claim refused, review or fix cycles exhausted, budget stop, brief
unfilled) · `fix <track>` (a gate-routed fix or a rejected light report; not for a track already `fixing`) · `verify <track>` · `review <track>` · `dispatch <track>` (ready: planned, deps finished, no glob
overlap with running tracks, under `max_parallel`) · `collect` (returned, uncollected) · `team_review <N>` (all tracks
finished, team review enabled, last cycle not clean) · `stop_success` (REQ-TEAM-081) · `wait` (also for tracks in
`fixing` / `verifying` / `reviewing`).

## 10. Subcommands

| Subcommand | Attributes |
|---|---|
| `init <topic>` | `--goal G-NNN \| --no-goal`, `--plan P`, `--tree DIR`, `--mirror DIR`, `--max-parallel N`, `--budget TOK`, `--team-review`, `--title T`, `--host H`, team pipeline attributes |
| `track add <id>` | `--task T \| --task-file F`, `--dod D` (repeatable, required), `--title T`, `--role R`, `--size S`, `--files g1,g2`, `--deps A,B`, `--resources r1`, `--source <plan\|spec>`, pipeline attributes, `--layer attr\|prompt` |
| `track set <id>` | pipeline attributes with `--layer`, or `--status S [--summary-file F]` |
| `plan` | `--json`; table, provenance, waves, mismatches, readiness errors |
| `prompt <id>` | renders `tracks/<id>.prompt.md`, prints the path |
| `next` | `--json` |
| `status` | `--json` |
| `checkpoint [label]` | `--verify <id>` |
| `review start\|gate\|external\|ingest` | `--cycle N`, `--lenses`, `--range`, `--name` |
| `collect` | `--dry-run` |
| `commit` | `--tracks A,B`, `-m MSG`, `--yes` |
| `known-red add\|list` | `<test-id> --reason R` |
| `close` | `--pause`; final STATUS, LIFT of the contract freeze |

Pipeline attributes: `--size --mode --tdd --verifier --review none|single|lenses[:a,b] --model key=value (repeatable)
--effort`. `mb-lock.sh` is separate and used by tracks directly.

## 11. Decisions (ADR candidates, recorded with `/mb adr` when the plan starts)

- **D1 — Shared tree, not worktrees.** File ownership + locks + one integrator matched the real process and avoids merge
  work; worktrees stay in `parallel-team-execution`.
- **D2 — Stateless brain + single writer.** `next` computes, the orchestrator executes, `team.json` has one writer; same
  pattern as `/mb drive`, resumable after compaction from files alone.
- **D3 — Track prompt is a one-stage plan.** Lets `plan-verifier`, `mb-work-diff.sh` and review payloads run unchanged.
- **D4 — Size presets live in `pipeline.yaml` `team.presets`.** The project default is the preset table; `team.overrides`
  forces fields for every size.
- **D5 — FIFO tickets with process-start liveness.** Fixes the observed race without a daemon or `flock`.
- **D6 — Nested block mappings only in `team:`.** The stdlib YAML fallback cannot parse nested inline maps or lists of
  maps; the schema uses nested mappings and scalar inline lists so PyYAML and stdlib agree.
- **D7 — Team artefacts under `reports/<topic>/`.** Same place the practice used; `team.json` sits next to the brief.

## 12. Tests

| Area | Kind | Key cases |
|---|---|---|
| `mb-lock.sh` | bats | FIFO order with three background waiters; dead waiter pruned; waiter killed → ticket gone; live child after SIGKILL of wrapper keeps the lock; foreign lock never removed; 75/76/77; maintenance only under the lock; `--resource-json`; macOS/Linux `df -Pk` parsing |
| queue / liveness | pytest | start-time mismatch = dead; EPERM = alive; status JSON schema |
| pipeline resolver | pytest | layer matrix per key; provenance; unknown key/value exit 2; `lenses:` shorthand; `mode: work` without source refused; slot → host model; prompt below preset warns |
| `team:` validation | pytest | PyYAML and stdlib paths return the same dict and errors (review [18] pattern) |
| state + `next` | pytest | status machine; deps; glob overlap; `max_parallel`; budget stop; stop_success needs all four conditions |
| render | pytest | golden brief/prompt: absolute paths, `--mb`, TDD line per pipeline, resource commands, no unfilled hints after render; unfilled hint → not ready |
| board | bats | BLOCKED/ACK, COMMIT, `--track`, `tracks --json`, legacy untouched |
| checkpoint / VCS | bats | git fixture: diff + tar + sha256 verify, large untracked skipped and listed; arc via PATH shim; refuses outside a tree |
| commit | bats | only owned files staged, foreign listed, co-owned refused, COMMIT entry, no push call (shim asserts) |
| collect / status | bats | progress via the locked helper, idempotent `collected`, status merges board + reports + locks |
| command docs | pytest | `commands/team.md` frontmatter; documented bash blocks run from a path with spaces (`test_audit_command_contracts.py` pattern); router row and SKILL index |
| nested bank | bats | cwd = bank → resolves to it, nothing created |
| e2e | bats | init → 2 tracks → next → returns → collect → checkpoint → commit (git) → status, no model calls |

## 13. Risks

| Risk | P | Mitigation |
|---|---|---|
| Orchestrator context grows with many work-mode tracks | M | `max_parallel`; work mode only for large/extra; `status` instead of rereading reports |
| `plan-verifier`/`mb-review.sh` reject the track prompt as a plan source | M | Stage T-STATE checks it first; fallback is a plain payload (diff + DoD + rubric) |
| arc CLI differs from git in flags | M | one seam, verified against real arc, shim tests |
| PID reuse misreads liveness | L | start-time match; same-host check |
| A track writes outside its globs | M | `commit` stages only owned files and lists the rest; review sees the foreign list |
| Board entry is not a proof of identity | L | coordination, not authority (existing rule); orchestrator fact-checks claims |

## 14. Open questions for Anton (block building)

**Q1. Default pipeline of a `standard` track.**
- A. `direct` + `plan-verifier` at track end, no per-track review — **recommended**: keeps the `medium` depth of
  effort-tiers without driving `/mb work`; the harness project overrides `verifier: none` per AGR-147 in its pipeline.yaml.
- B. `mode: work`, preset `medium`, literally as effort-tiers says.
- C. `direct`, no verifier, quality from the team review only (the AGR-147 practice as the skill default).

**Q2. A lock whose holder is provably dead.**
- A. Never removed automatically; only `mb-lock.sh break` by the orchestrator (the `with-build-lock.sh` rule).
- B. The queue head reclaims it when the wrapper and the child are both gone with matching start times on the same host,
  and posts a board entry — **recommended**: no wait on a crashed holder, and a live build is never touched.
- C. Reclaim after a TTL.

**Q3. Severity `medium`.**
- A. Add an optional `medium` level to the review vocabulary (parser, gate, lead schema), default limit 0, existing
  configs unchanged — **recommended**: matches the practice "until no blocker/major/medium".
- B. Keep three levels; reviewers fold medium into major.
- C. Four levels only inside team review.

**Q4. What `mode: work` means in Claude Code, where a subagent cannot dispatch subagents.**
- A. The orchestrator runs the real `/mb work` loop for the track (per-run slot, eval gates, checkbox flips) —
  **recommended**: one engine, all gates; costs orchestrator context, bounded by `max_parallel`.
- B. "Work-lite": the track agent walks the plan stages itself; the orchestrator runs verifier/review after.
- C. Both, selectable.
