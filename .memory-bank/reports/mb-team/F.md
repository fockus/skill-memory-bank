STATUS: DONE_WITH_CONCERNS

# Track F: Stage 8 T-STATE (`mb-team.sh`, state, `next`, status, collect, checkpoint, commit)

## Files
New:
- `scripts/mb-team.sh` (63 lines). The dispatcher. It refuses to run when cwd is inside `*/.memory-bank/*`; `--mb` and `--topic` are accepted anywhere on the line. Routing:
  - `init | track | plan | prompt | known-red` → `mb_team_tracks.py`;
  - `next | status` → `mb_team_status.py`;
  - `collect | commit | checkpoint | close` → `mb_team_ops.py`;
  - `review gate` → `mb_team_ops.py review-gate`;
  - `review start | external | ingest` → `mb-team-review.sh` with `--team` and `--mb`.
- `scripts/mb_team_state.py` (207 lines). Holds team.json and is its single writer: `locked()` takes `fcntl.flock` on `reports/<topic>/.team.lock`, writes a temp file, fsyncs it, then `os.replace`. Also here:
  - the status machine (`can_move`);
  - path-aware globs (`glob_match`, conservative `globs_overlap`, `owns`);
  - `resolve_track` through `mb_team_pipeline.resolve`;
  - rendering of the brief and track prompts through `mb_team_render`.
- `scripts/mb_team_tracks.py` (289 lines, **not in the plan's Files line**). Commands: `init`, `track add/set`, `prompt`, `known-red add/list`, `plan`. The original single state module was 415 lines, so I split it to stay under the 300-line limit.
- `scripts/mb_team_status.py` (267 lines). `decide(team, facts)` is the pure rule for design §9. `gather()` collects the facts. `status` produces text and `--json`.
- `scripts/mb_team_ops.py` (273 lines). `collect`, `commit`, `checkpoint`, `close`, `review-gate`.
- `tests/pytest/test_mb_team_state.py` (39 tests), `tests/bats/test_mb_team_cli.bats` (10), `tests/bats/test_mb_team_commit.bats` (4).
- `tests/bats/lib/team_fixture.bash` (**not in the Files line**). A shared temp git project with a space in its path, used by both bats files.

## How the requirements are covered
- **`init`**:
  - Without `--no-goal`, `mb-goal-validate.sh <bank>/goal.md <bank>` must pass, otherwise exit 2 and nothing is created.
  - Records the root, kind and HEAD of `--tree` through `mb_vcs.sh`.
  - `--budget N` runs `mb-work-budget.sh init --run-id team-<topic>` (with `MB_WORK_PARALLEL=1`).
  - `--team-review` sets `"team_review": true`.
  - Renders the brief and posts `FREEZE · contract:<topic>`.
  - A second `init` of the same topic is refused.
- **`track add`**:
  - Stores `title` and `dod`. `--dod` is required and repeatable.
  - The agent is `mb-<role>` and must exist in `agents/`.
  - deps must name existing tracks; resources must be declared in `team.resources`.
  - The pipeline comes from `mb_team_pipeline.resolve` with the layers team (init attributes) → track → prompt (`--layer`). Provenance and warnings come from the resolver too.
  - `mode: work` without `--source` exits 2.
  - Renders `tracks/<id>.prompt.md`.
  - The tracks table in the brief is redrawn only while the brief is still byte-identical to the last render (`brief_sha256`). If the orchestrator has edited it, the brief is left alone and a note is printed.
- **`track set`**:
  - `--status` follows the machine. `→ fixing` increments `fix_cycle`; `dispatched_at` and `returned_at` are stamped.
  - `--summary-file`.
  - Pipeline attributes are re-resolved, and the prompt and brief are re-rendered.
- **`next`** prints only (a test confirms all tracks are still `planned` after it runs). Priority order: `stop_human` (no-tracks, brief-unfilled, budget, blocked/needs_context by track status, by an open board BLOCKED, or by the report STATUS line; no-report; review-*) · `fix` · `verify` · `review` · `dispatch` · `collect` · `team_review N` · `stop_success` · `wait`.
  - `dispatch` requires: status `planned`, deps finished, no glob overlap with active tracks or with tracks already picked in the same call, and fewer than `max_parallel` active.
  - A brief with hints or a budget stop blocks dispatch.
  - A returned `light` track goes through `mb_work_light.accept`: rejected → `fix`, accepted → verify/review.
  - An orchestrated `work` track has no post-steps (the gates ran inside `/mb work`).
  - `stop_success` requires all four REQ-TEAM-081 conditions: all tracks finished or cancelled and collected; the last review clean when review is on; goal acceptance (`mb-goal-acceptance.sh`, skipped for `--no-goal`); `mb-flow-verify.sh` exit 0. The last two run only when everything else already allows stop.
- **`status`** combines team.json, `mb-coord.sh tracks --json`, `mb-lock.sh status --json`, the report STATUS lines, the goal, the last review and `next`.
- **`collect`**:
  - Takes only newly returned tracks: finished ones, or `returned` with no post-steps and a DONE/DWC report.
  - One entry per track goes through `mb-work-progress-append.sh`. If the append fails or is skipped, the track is not marked and the command exits 1.
  - Marks `collected` under the same lock, so a second run appends nothing.
  - Prints the `Questions` and `Follow-ups` sections of the reports as `mb-agree.sh question` and `mb-idea.sh` commands.
  - With a goal, lists the `## Acceptance criteria` items with `checked` next to the reports of this run (`evidence`).
  - `--dry-run` writes nothing.
- **`checkpoint`**:
  - Calls `mb-team-checkpoint.sh` with `dir` and `max_untracked_mb` from `team.checkpoint`. `dir` is bank-relative; the default is `backups/team`.
  - Records `checkpoints[]`.
  - Then runs `checkpoint.extra` in the tree; if extra fails, exit 1.
  - `--verify <id>`.
- **`commit`**:
  - Takes files changed against HEAD plus untracked files (both through `mb_vcs.sh`) that fall under the globs of the selected tracks.
  - Refuses: an unfinished track, an open BLOCKED/HANDOVER for a selected track, and a file also owned by an unfinished unselected track (the file and that track are named).
  - Lists foreign files.
  - Asks y/N. With no TTY and no `--yes` it exits 1 with nothing staged.
  - `mb_vcs.sh add -- <files>` + `commit -m`, then `## COMMIT · … · team <topic>: <hash8> A,B` with the file list in the body, then `commits[]`. There is no push path; a PATH-shim test asserts it.
- **`close [--pause]`**: STATUS on the board and LIFT of `contract:<topic>`; marks the team `closed` (pause leaves it open).

## The HANDOVER from G (T-REVIEW): accepted, ACK on the board
1. `mb-team.sh review gate --cycle N` runs `mb-team-review.sh gate` and passes its exit code through. For exit 0/1 it records `reviews[]` `{cycle, scope:"team", master, verdict, counts, actions, at}` under the team lock (the same cycle is overwritten). Adjustment: the recording happens in `review gate`, not in `next`, so that `next` stays stateless.
2. `next` reads the last recorded review: `stop_human review-unowned|review-cycles` from its `actions`, and `fix <track>` while that track has not returned after `at`. `team_review N+1` comes once those fixes are back. `clean` is the gate verdict; without a verdict it is the counts against `clean_when`. In addition, `next` emits `stop_human review-cycles` itself when the limit is reached.
3. `init --team-review` writes `"team_review": true`.
4. Status machine: `done|done_with_concerns → fixing` is allowed (a team review fix on a finished track).

## Tests: failing before, passing after
Before (tests written first, no code yet):
```
$ .venv/bin/python -m pytest -q tests/pytest/test_mb_team_state.py
ERROR tests/pytest/test_mb_team_state.py   (ModuleNotFoundError: mb_team_state)
1 error in 0.15s
$ bats tests/bats/test_mb_team_cli.bats tests/bats/test_mb_team_commit.bats
not ok 1 … not ok 13   (13 of 13, mb-team.sh missing)
```
Along the way the tests caught:
- a fixture without HEAD;
- `mb-goal-validate.sh "" <bank>` treating the bank as the goal path, so the path is now passed explicitly (also in acceptance);
- a returned track with no report, which used to stall silently and now gives `stop_human no-report:<id>`;
- `--topic` before the subcommand.

After:
```
$ bats tests/bats/test_mb_team_cli.bats tests/bats/test_mb_team_commit.bats tests/bats/test_mb_team_review.bats tests/bats/test_mb_team_checkpoint.bats
1..37   (0 not ok)
ok 9 team: end to end — init, two tracks, next, returns, collect, checkpoint, commit
ok 10 team: review gate is recorded in reviews[] and next routes the fix to the owner track
$ .venv/bin/python -m pytest -q tests/pytest/test_mb_team_state.py tests/pytest/test_mb_team_render.py tests/pytest/test_mb_team_config.py tests/pytest/test_mb_team_pipeline.py
180 passed in 16.05s
$ ruff check scripts/mb_team_{state,tracks,status,ops}.py tests/pytest/test_mb_team_state.py
All checks passed
$ shellcheck -x scripts/mb-team.sh tests/bats/test_mb_team_{cli,commit}.bats tests/bats/lib/team_fixture.bash
(clean)
```
End to end (bats 9), on a git repository in a path with spaces: `init` → two `track add` → `next` (= `dispatch A`, `dispatch B` after the brief is filled) → returns with reports → `next` = `collect` → `collect` → `checkpoint` → `commit --yes` (exactly `a/new.txt a/x.txt b/y.txt`) → COMMIT on the board → `next` = `stop_success` → `status`.

## DoD
- [x] `next` fixtures: deps, glob overlap, `max_parallel`, blocked → `stop_human`, unfilled brief → `stop_human`, `stop_success` only when all four conditions hold (parametrized with each one broken).
- [x] `collect`: one entry per new track through `mb-work-progress-append.sh`; a second run appends nothing.
- [x] `commit`: stages only owned files, lists foreign ones, refuses co-owned files and unfinished tracks (and an open BLOCKED), writes COMMIT, never calls push (shim); without `--yes` and without a TTY it does nothing.
- [x] `status --json` reports a held lock, a queued waiter and an open BLOCKED together.
- [x] Two concurrent `track set` processes (8 fixing/returned rounds each) lose nothing: `fix_cycle` = 8 for both, no temp files left.
- [x] Tests green; shellcheck and ruff clean; every file under 300 lines.

## Concerns
1. **Resolved (ORCH decision "ORCH: C6 path-scoped commit").** `commit` used to commit the whole index. It is now path-scoped; see the section "C6: path-scoped commit" below.
2. **Low: two files outside the Files line**, `scripts/mb_team_tracks.py` and `tests/bats/lib/team_fixture.bash`. T-WIRE must add `mb_team_tracks.py` (plus `mb_team_state.py`, `mb_team_status.py`, `mb_team_ops.py`, `mb-team.sh`) to the install manifest.
3. **Low: additive C1 fields.** Team: `title`, `host`, `team_attrs`, `team_review`, `brief_sha256`, `closed`. Track: `layers`. Review: `actions`, `at`. T-DOCS should list them in C1.
4. **Low: semantics for T-DOCS (`commands/team.md`).**
   - `verifying` and `reviewing` mean "in progress", and `next` answers `wait` for them. After a passed verifier the orchestrator itself moves the track to `reviewing` (and starts the review) or to `done`.
   - `--source` and `--plan` take a bank-relative or absolute path; `checkpoint.dir` is bank-relative.
   - deps must be added before the tracks that depend on them.
5. **Low: board ids are not namespaced by team.** An open BLOCKED with id `A` from an old team stops a new team's `A` until it gets an ACK.
6. **Low: `stop_success` runs `mb-flow-verify.sh` with the default checks in the tree.** On a large tree that is slow, but it happens only once all the other conditions already hold.
7. **Info:** the budget is covered by `init` and `check`. Per-track spend (`mb-work-budget.sh add --run-id team-<topic>`) is the orchestrator's job, to be described in T-DOCS.

## C6: path-scoped commit (after the ORCH decision)
- `scripts/mb_vcs.sh`: `commit -m <msg> -- <path>...`. git → `git commit --only -m <msg> -- <paths>`; arc → `arc commit -m <msg> -- <paths>`. No message, no `--` or no paths → exit 2, nothing committed. Header usage line updated.
- `scripts/mb_team_ops.py`: `commit` passes exactly the owned files collected from the tracks (`"--", *owned`).
- Real arc (read-only probe on ~/arcadia-int, like stage 5): `arc commit --help` takes `[PATH]...`. `arc commit --dry-run -m probe -- <one modified path>` listed only that path under "Changes to be committed", with exit 0. I did not stage a foreign file in the real tree (it is the shared integration tree). That arc keeps a foreign staged file out of a path-scoped commit is covered only by the shim, which runs git underneath.
- The only caller of `mb_vcs.sh commit` is `mb_team_ops.py` (grep).

Tests, written first:
```
$ bats tests/bats/test_mb_vcs.bats            # before the change
not ok 5 git: commit is path-scoped; a foreign staged file stays staged and out of the commit
not ok 6 arc via shim: commit is path-scoped; a foreign staged file stays staged
not ok 7 commit without paths or without a message exits 2 and commits nothing
$ bats tests/bats/test_mb_team_commit.bats -f "stages only"   # before: a pre-staged stray.txt went into the commit
not ok 1 … `[ "$(git -C "$PROJ" show --name-only --format= HEAD)" = "a/x.txt" ]' failed
```
After:
```
$ bats tests/bats/test_mb_vcs.bats tests/bats/test_mb_team_checkpoint.bats tests/bats/test_mb_team_commit.bats tests/bats/test_mb_team_cli.bats
1..33   (0 not ok)
$ shellcheck -x scripts/mb_vcs.sh   (clean) · ruff check scripts/mb_team_ops.py   All checks passed!
```
For T-DOCS: C6 in design.md §3 now reads `commit -m <msg> -- <paths>`.

## Remaining
Nothing in this stage's scope. Not committed. The done-gates files were not touched.
