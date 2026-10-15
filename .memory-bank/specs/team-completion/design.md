# Design: team-completion

> Slice S2 of `[SPEC:autopilot]`. Fixes over the shipped `/mb team` contract (`specs/mb-team/`), no new
> subsystem: every change lands in an existing team script, `scripts/mb_vcs.sh` or `commands/team.md`.
> Lightweight mode (NFR-001, AGR-075/078): three implementation tasks cut at owner/risk boundaries, plus the
> two rendered test layers.

## Architecture

`/mb team` stays a stateless brain (`team next` prints actions, changes nothing) plus the single writer of
`reports/<topic>/team.json`. The orchestrator executes the actions with host tools. What changes:

| Area | Today | After this spec |
|---|---|---|
| Track execution | `mode: direct` for trivial..standard (team runs the verifier/review post-steps itself), `work: light` (agent walks stages, team runs post-steps), `work: orchestrated` for large/extra | every track is `mode: work`, `work: orchestrated`: the orchestrator runs the `/mb work` per-item loop on the track source; team owns no post-step (REQ-001/002) |
| Track source | required only for `mode: work` (`--source`) | defaults to the track prompt `reports/<topic>/tracks/<id>.prompt.md`, already a one-stage plan with `<!-- mb-stage:1 -->` (REQ-001) |
| Dead ends in `next` | cancelled dep → endless `wait` (`scripts/mb_team_status.py:157`); all done + red goal/flow → `wait` (`:171-173`) | `stop_human blocked:dep-cancelled:<id>`, `stop_human goal-red`, `stop_human flow-red:<check>` (REQ-003/004) |
| Action list | `stop_human` printed next to `dispatch`/`collect` (`:163`) | any `stop_human` → only the `stop_human` lines (REQ-005) |
| Report STATUS | first non-empty line only (`:180-182`) | last line carrying a STATUS value (REQ-006) |
| `team commit` failure | files stay staged (`scripts/mb_team_ops.py:169-170`) | index entries of the staged paths restored (REQ-007) |
| Ownership | review: `fnmatch` (`scripts/mb_team_review_core.py:80`); commit: `mb_team_state.owns` | both `mb_team_state.owns` (REQ-008) |
| Review gate crash | `json.loads("")` traceback (`scripts/mb_team_ops.py:233`) | exit 2, `reviews[]` unchanged (REQ-009) |
| Checkpoint id | per minute, label unchecked (`scripts/mb-team-checkpoint.sh:27`) | per second, existing id refused, label validated (REQ-010/011) |
| Host lock root | `TMPDIR`-based, duplicated (`scripts/mb_team_config.py:125`, `scripts/mb_lock_resource.py:47`) | one function, `MB_LOCK_DIR` or `/tmp/mb-locks-<uid>` (REQ-012) |
| Hosts | `commands/team.md` §9: Claude Code, Codex, Pi; OpenCode absent | §9 links the four-host table in `SKILL.md` § Invocation and adds the team deltas (REQ-013) |

Dependency direction is unchanged: `mb_team_status.py` / `mb_team_ops.py` / `mb_team_review_core.py` →
`mb_team_state.py` → `mb_team_pipeline.py` / `mb_team_config.py`; shell helpers are called through `run()`.

## Interfaces

### C1. `team next` action lines (contract of `scripts/mb_team_status.py decide`)

Vocabulary after the change (one action per line, priority order):

```text
stop_human <why>   why ∈ brief-unfilled | no-tracks | budget | blocked:<id> | needs_context:<id> | no-report:<id>
                         | claim:<id> | review-cycles | review-unowned | fix-cycles:<id>
                         | blocked:dep-cancelled:<dep id>            (new, REQ-003)
                         | goal-red | flow-red:<check>[,<check>…]    (new, REQ-004)
fix <id> · dispatch <id> · collect · team_review <N> · stop_success · wait
```

- `verify <id>` and `review <id>` leave the vocabulary: a track's verifier and review run inside its `/mb work`
  loop (REQ-002). The `verifying`/`reviewing` statuses stay in the status machine (harmless, no reader change).
- **REQ-003.** For every cancelled track that is in the `deps` of a `planned` track, one line
  `stop_human blocked:dep-cancelled:<cancelled id>` (deduplicated, in track order). `team status` prints such a
  dependent's STATUS column as `blocked:dep-cancelled:<cancelled id>`; this is display only — `next` and `status`
  stay read-only, `team.json` is not written.
- **REQ-004.** After `all_done and all_collected` and a clean/off team review: `goal_ok()` false →
  `stop_human goal-red` (flow not run); else `flow_red()` non-empty → `stop_human flow-red:<names>`; else
  `stop_success`. `wait` is returned only while something is still running.
- **REQ-005.** `decide` returns the deduplicated `stop` list alone when it is non-empty; `fix`, `dispatch`,
  `collect` and `team_review` are withheld until the human resolves the stop.

### C2. Track pipeline (`mb_team_pipeline.py`, `mb_pipeline_validate_team.py`, `mb_team_tracks.py`)

- Enums: `mode ∈ {work}`, `work ∈ {orchestrated}`. `direct` and `light` are refused with a message naming
  REQ-001 ("every track runs through /mb work"). The keys stay so existing `mode: work` configs keep validating.
- Bundled presets (`references/pipeline.default.yaml` `team.presets`): every size `mode: work`,
  `work: orchestrated`; `tdd`, `verifier`, `review`, models and effort unchanged (AGR-097 costs kept).
- `resolve()` no longer raises "mode: work needs a source"; `track add` stores
  `source = --source or reports/<topic>/tracks/<id>.prompt.md`.
- Workflow per track — the existing `commands/team.md` §5 mapping, now for every track: verifier none and review
  none → `--workflow simple`; verifier only → `medium`; review single → `complex` (`--verify off` without a
  verifier); lenses → `governed --no-judge --lenses <csv>`. Models via
  `mb-work-plan.sh --model <executor> --step-model verifier=… --step-model reviewer=…`.
- Claim key: the orchestrator passes the track source **path** as the positional `<source>` of
  `mb-work-state.sh init` (together with `--source-path`/`--source-topic`), so two parallel tracks hold two
  path-keyed claims instead of colliding on the `plan` category claim (`commands/work.md:46,80`).
- Prompt vocabulary (`mb_team_vocab.py`): the `direct` and `light` rows are removed; `orchestrated` stays.
- Track prompt (`mb_team_render.pipeline_lines`): one line for every track — "This track runs through /mb work on
  <source>, driven by the orchestrator …".

### C3. Report STATUS (`report_status`)

```python
STATUS_RE = re.compile(r"^\s*\**STATUS:?\**:?\s*(DONE_WITH_CONCERNS|DONE|BLOCKED|NEEDS_CONTEXT)\b")
# last matching line of the report wins; no match -> None (stop_human no-report:<id>)
```

`templates/team/brief.md` § Report says "a STATUS line; the last one counts" instead of "first line".

### C4. Flow check of `team next`

`gather()` replaces `flow_ok` with `flow_red() -> list[str]`: runs
`mb-flow-verify.sh <bank> --skip acceptance` (cwd = tree) and returns the names of checks whose `status` is
`fail` or `broke` from the summary JSON on stdout; exit 0 → `[]`; non-zero with no parsable name → `["broke"]`.
Goal acceptance is judged once, by `goal_ok()` (team goal) — `--skip acceptance` keeps goal-red and flow-red
disjoint and is what lets a team under drive end (see *Drive interplay*).

### C5. `scripts/mb_vcs.sh` index snapshot (REQ-007)

```text
mb_vcs.sh index-save    --tree <dir> -- <paths…>   # stdout: NUL-separated `git ls-files -s -z` records of <paths>
mb_vcs.sh index-restore --tree <dir> -- <paths…>   # stdin: that snapshot; force-removes <paths> from the index,
                                                   #  then `git update-index -z --index-info` re-adds the saved entries
# arc: both exit 3 (unsupported) — team commit then names the paths left staged on stderr
```

`cmd_commit`: `snapshot = index-save -- owned` before `add`; `add` + `commit` inside `try`; on failure
`index-restore` with the snapshot, then re-raise ("commit failed; index restored"). Only the owned paths are
touched, so a foreign session's staging in the same tree survives.

### C6. Ownership (REQ-008)

`Ctx.owner(issue)` strips the `team.tree` **or** `team.mirror` prefix and then uses `mb_team_state.owns(track, path)`
— the `_glob_re` rule (`**/` = zero or more directories, `*` stays inside a segment) commit already uses.

### C7. Review gate (REQ-009)

`cmd_review_gate`: when the gate exits 0/1 but stdout is not a JSON object, print
`[team] review gate: output is not a JSON verdict` to stderr and return 2 without touching `reviews[]`.

### C8. Checkpoint (REQ-010/011)

`mb-team-checkpoint.sh create`: `--label` must match `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$` (the `TOPIC_RE` rule)
else exit 2; id `$(date +%Y-%m-%d-%H%M%S)-<topic>-<label>`; when `<dir>/<id>.diff` or `<id>-manifest.json` exists,
exit 1 before writing anything.

### C9. Host lock root (REQ-012)

`mb_team_config.host_lock_root() -> str`: `MB_LOCK_DIR` if set, else `/tmp/mb-locks-<uid>`; created mode 0700;
a path that is a symlink or not owned by the current user is refused (exit 2 through the existing `ConfigError`
path). `mb_lock_resource.lock_root()` calls it; the `TMPDIR` code goes.

### C10. Hosts (`commands/team.md` §9, REQ-013)

§9 links `SKILL.md` § Invocation (the four-host dispatch table, `SKILL.md:177-182`) and keeps only the team deltas:

| Host | Parallel tracks | Mid-flight relay |
|---|---|---|
| Claude Code | `run_in_background: true`, several in one message | `SendMessage` |
| Codex | several `spawn_agent` calls in one turn | at the track boundary (next dispatch carries the addendum) |
| OpenCode | several `task` calls in one turn | at the track boundary |
| Pi | several `mb_dispatch_subagent` calls in one turn | at the track boundary (`SendMessage` is dropped on Pi) |

A host that runs dispatches one at a time runs the tracks serially with a one-line notice.

## Contract

The single seam is the existing team CLI; every requirement is observable through it (and through the
`commands/team.md` text it documents).

**Seams:**
- `scripts/mb-team.sh` — the `/mb team` CLI: `next`/`status` action lines, `track add`, `commit`, `checkpoint`, `review gate`

## Drive interplay (design point, S3 owns drive)

- Under `/mb drive`, drive starts the team with `--no-goal`: the goal check is drive's. With C4's
  `--skip acceptance`, a team under drive ends with `stop_success` once its tracks are collected and the flow
  (minus acceptance) is green — "team just ends", no drive flag inside team.
- Every team `stop_human` (dep-cancelled, flow-red, claim, …) returns to drive, which counts it as a stall
  (context D-08/D-09). Team adds nothing for this.

## Decisions

- **D-1 Retire `direct` and `light` instead of keeping them as opt-outs.** REQ-001 says *every* track; an opt-out
  re-opens the second pipeline that D-03 removes. Cost stays: standard = implementer + one plan verifier
  (`/mb work --workflow medium`, plan cadence) = AGR-097's "executor with TDD + plan-verifier". Rejected: keep
  `direct` as an explicit attribute.
- **D-2 Keep the `mode`/`work` keys with one value each.** Smallest diff; existing `mode: work` configs and stored
  `team.json` files keep loading. Dropping the keys is a later cleanup.
- **D-3 Default work source = the track prompt.** It already is a one-stage plan; `mb-work-plan.sh --target
  <prompt>` resolves it as `kind: stage` (checked on a temp bank). Rejected: generate a separate plan file per track.
- **D-4 `stop_human` per cancelled dependency, display-only marking.** `next`/`status` stay read-only (mb-team
  design §9); the dependents are shown, not rewritten. Rejected: auto-cancel dependents (D-09 rejected it).
- **D-5 `--skip acceptance` in team's flow call.** One owner per check: goal acceptance → `goal_ok`, the rest →
  `mb-flow-verify.sh`.
- **D-6 Per-path index snapshot, not a copy of `.git/index`.** A whole-index copy would drop a parallel session's
  staging made while hooks run.
- **D-7 No change to `commands/work.md`.** It is a 399-line zone file and S1 edits it; the four-host table already
  lives in `SKILL.md` § Invocation, which team links.
- **D-8 Test files.** Each implementation task gets one new focused test file for its Eval; the integration layer
  puts the six scenario tests in one `tests/pytest/test_mb_team_scenarios.py`; the e2e layer extends
  `tests/e2e/test_mb_team_e2e.bats` (fixture `tests/bats/lib/team_fixture.bash`), no new harness.

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

Each Eval names a new focused test file (absent now → `pending_materialization` at generation; `/mb work` 5a0
writes it first and observes the red). Anchors are the runner's own failure line.

- **T1** — every track through /mb work
  **Eval:** python3 -m pytest -q tests/pytest/test_mb_team_work_tracks.py tests/pytest/test_mb_team_pipeline.py tests/pytest/test_mb_team_render.py tests/pytest/test_mb_team_state.py — red: presets still resolve mode direct and a track added without --source has no work source; exit: 1; output~: FAILED tests/pytest/test_mb_team_work_tracks.py
- **T2** — next stops, STATUS, hosts
  **Eval:** python3 -m pytest -q tests/pytest/test_mb_team_next.py tests/pytest/test_mb_team_state.py tests/pytest/test_mb_team_command.py — red: a cancelled dependency and a red flow still give wait, STATUS is read from the first line only; exit: 1; output~: FAILED tests/pytest/test_mb_team_next.py
- **T3** — commit, review, checkpoint and lock hardening
  **Eval:** bats tests/bats/test_mb_team_hardening.bats — red: a failed commit leaves files staged, the review gate crashes on non-JSON, checkpoint ids collide; exit: 1; output~: not ok [0-9]+

## Risks & mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Retiring `direct`/`light` breaks a project `pipeline.yaml` that sets them | L | M | the validator names the key, the value and REQ-001; CHANGELOG line |
| Two tracks with the same `--source` spec collide on the path claim | M | L | existing `stop_human claim:<id>`; such tracks get `--deps` or their own wrapper plans |
| Flow check runs the full suite on every `next` once all tracks are done | M | L | unchanged from today; the stop now ends the loop instead of repeating it |
| `index-restore` on arc is not available | M | L | exit 3 → stderr lists the paths left staged; arc commit is already unproven (review m7) |
| `/tmp/mb-locks-<uid>` pre-created by another user | L | H | 0700 + owner and symlink check, refuse otherwise |
| S1 edits `commands/work.md` / `mb-work-plan.sh` in parallel | M | L | this spec touches neither (D-7) |

## Open questions

- AGR-097 says the standard track is "direct executor + TDD + plan-verifier" and keeps both `work` variants
  (orchestrated, light). D-03 (2026-10-15) makes every track `/mb work`; D-1 retires `direct` and `light` at the
  same cost. Needs an agreement that supersedes that part of AGR-097 before Task 1 runs.
