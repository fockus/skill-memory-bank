STATUS: CHANGES_REQUESTED

# /mb team: final review, stages 1–11 (AGR-155, a single reviewer)

- **Scope:** the uncommitted diff of `plans/2026-10-10_feature_mb-team.md` against f050443. The done-gates files in
  `brief.md` («Чужие правки») are excluded.
- **Read:** `mb-team.sh`, `mb_team_{state,status,ops,tracks,render,config,pipeline,review,review_core,review_external}.py`,
  `mb-lock.sh`, `mb_lock_{queue,resource}.py`, `mb_vcs.sh`, `mb-team-checkpoint.sh`, the arc shim, `mb_work_light.py`,
  the `mb-coord.sh`, `_lib.sh` and engine diffs (`mb-workflow.sh`, `mb-work-plan.sh`, parse, gate), `commands/team.md`,
  the e2e and install tests, and the A–W11, verify and fix-verify reports.
- **Ran:** pytest `test_mb_team_state`, `_render`, `test_mb_lock_queue`, `test_mb_team_command`: 76 passed. bats team
  cli/commit/review, vcs, checkpoint and team e2e: 51/51 ok. `decide()` probes and shell probes are quoted below.
- **Counts:** blocker 0 · major 5 · minor 9 · nit 3.

## Major

**M1. `next` cannot tell "fix needed" from "fix running", so it asks for a second dispatch.**
- **Where:** `scripts/mb_team_status.py:111-112`: `elif st == "fixing": fix.append(f"fix {tid}")`.
- **Docs:** `commands/team.md:139` says `fix <id>` means re-dispatch the track. `:146` and design §9 give `wait` only
  for verifying and reviewing.
- **Scenario:** a review fails, so the orchestrator sets A to `fixing` and re-dispatches it. Then B returns and
  `next` runs again. It prints `fix A` again, and the orchestrator ("execute all printed actions") starts a second
  agent on A's globs while the first one is still working.
- **Probe:** `decide(team(track("A","fixing",verifier="plan-verifier"), track("B","dispatched")))` → `['fix A']`.
- **Tests:** the e2e (`tests/e2e/test_mb_team_e2e.bats:69-71`) never calls `next` while a track is `fixing`.
- **Fix:** count `fixing` as running, so `next` waits for it. Emit `fix <id>` only for a pending fix: a gate-routed
  finished track (`review_actions`) or a rejected light report. Document "set `--status fixing` when you re-dispatch".

**M2. A `work: light` track with no verifier and no review stalls forever.**
- **Where:** `scripts/mb_team_status.py:52-57` (`post_steps` is always True for light), `:113-119` and
  `collectable` `:65`.
- **What happens:** an accepted light report with `verifier: none` and `review: none` yields no action, and
  `collectable` is False because post-steps are pending. The track stays `returned` and is never collected.
- **How it is reached:** the bundled `trivial` and `small` presets plus `--mode work:light`. `commands/team.md:177`
  promises "else `verify`/`review` as configured".
- **Probe:** `decide(team(track("L","returned",mode="work",work="light")), light={"L":{"accepted":True}}, reports={"L":"DONE"})`
  → `['wait']`.
- **Fix:** let `collectable` accept a returned light track whose acceptance passed and which has no verifier or review.
  Alternatively, reject that combination in `mb_pipeline_validate_team.py`. Add the case to `test_mb_team_state.py`.

**M3. Lock liveness depends on locale and time zone, so a live holder can be judged dead.**
- **Where:** `scripts/mb_lock_queue.py:40-44`. The `ps -o lstart=` output is compared as a string (`alive`, `:58`).
- **Probe on this Mac, for the same pid:**
  - default env: `Sun Oct 11 11:36:00 2026`;
  - `TZ=UTC`: `Sun Oct 11 08:36:00 2026`;
  - `LC_ALL=ru_RU.UTF-8`: `воскресенье, 11 октября 2026 г. 11:36:00`.
- **Scenario:** track A holds `build` and runs with one env. Track B is queued with a different `LANG` or `TZ`, for
  example from another host CLI. Then:
  - `tickets()` in B unlinks A's tickets as dead (`:125-127`);
  - B at the head sees `holder_alive(meta) is False` and reclaims the live lock (`:175-177`);
  - two heavy builds run at once, and the board says "reclaimed dead lock".
- **Fix (one line):** `subprocess.run([...], env={**os.environ, "LC_ALL": "C", "TZ": "UTC"}, ...)` in `proc_start`.
  Add a test that enqueues under `TZ=UTC` and judges under another TZ.

**M4. Non-ASCII paths are quoted by git, so `commit` silently leaves owned files out.**
- **Where:**
  - `scripts/mb_vcs.sh:45`: `changed` runs `"$kind" diff --name-only` with neither `-z` nor `core.quotePath=false`;
  - consumers: `scripts/mb_team_ops.py:140` (`splitlines`) and `mb-team-checkpoint.sh:36`.
- **Probe:** with `docs/файл.md` changed, `mb_vcs.sh changed --tree . HEAD` prints `"docs/\321\204\320\260\320\271\320\273.md"`.
- **Scenario:** track A owns `docs/**` and changes a Cyrillic-named file. Usual in the harness wiki.
  - `owns()` never matches the quoted name. The file is listed as "foreign, not staged", and the commit goes out
    without it. This breaks REQ-TEAM-063: "staging exactly the changed files owned by the selected tracks".
  - With a `**` glob, `git add -- '"docs/\321…"'` fails with a pathspec error.
  - `tracked_changed` in the checkpoint manifest is mangled the same way.
- **Related:** rename detection reports only the new path of a staged rename. `commit --only <new>` then keeps the
  old file in the commit.
- **Fix:** `git -c core.quotePath=false diff --name-only -z --no-renames <base>`, then split on NUL in ops and the
  checkpoint. Add a git fixture with a Cyrillic file and a space in its name.

**M5. Shell injection through the commands that `collect` prints.**
- **Where:** `scripts/mb_team_ops.py:115-118`. The track report's question or follow-up is wrapped by `json.dumps`
  into a double-quoted bash word. `commands/team.md:202` tells the orchestrator to run these lines.
- **Probe:**
  - `echo 'echo question "Should \`echo INJECTED\` run?"' | bash` prints `question Should INJECTED run?`;
  - `$(…)` expands the same way.
- **Scenario:** Markdown code spans in a report bullet are normal, for example "- Should `make clean` run first?".
  When the orchestrator pastes the printed line, `make clean` runs in its shell. A prompt-injected report can run
  anything this way.
- **Fix:** use `shlex.quote(q)` and `shlex.quote(f)`. Update `tests/bats/test_mb_team_cli.bats:61`, which now pins
  the unsafe form, and add a backtick case.

## Minor

**m1. Review routing and commit ownership disagree on globs.**
- **Where:** `scripts/mb_team_review_core.py:80` uses `fnmatch`, where `*` crosses `/`. Commit ownership uses
  `mb_team_state.glob_match`, where `**/` is zero or more directories.
- **Mismatches:**
  - `src/**/*.py` does not route an issue in `src/x.py`, so the gate stops with `stop_human review-unowned` while
    commit says the track owns the file;
  - `src/*.py` routes `src/sub/y.py` to a track that cannot commit it.
- **External findings:** `owner()` strips the `team.tree` prefix but not the `team.mirror` prefix, though the prompt
  points the reviewer at the mirror.
- **Fix:** route through `st.owns`, and strip both prefixes.

**m2. A crash in `review gate` turns into a traceback.**
- **Where:** `scripts/mb_team_ops.py:230-231`.
- **What happens:** any exception that `mb_team_review.py` does not catch exits 1, the Python default. Ops reads 1 as
  "fixes needed" and runs `json.loads("")`, which raises another traceback. `reviews[]` is not written.
- **Fix:** in the review `main`, catch the remaining exceptions and return 2. Or parse stdout defensively in ops.

**m3. Checkpoints can overwrite each other, and the label is not checked.**
- **Where:** `scripts/mb-team-checkpoint.sh:27`, with ids at minute resolution.
- **Collision:** two checkpoints with the same label in one minute overwrite the diff, tar and sha256. `team.json`
  then gets two entries with one id.
- **Label:** `--label` is not validated, so `../x` writes outside `--dir`.
- **Fix:** add seconds to the id, refuse an id that exists, and validate the label like `TOPIC_RE`.

**m4. Copy-paste commands are not quoted, and they break in paths with spaces.**
- **Where:**
  - `scripts/mb_team_render.py`: `_resource_block` (`--mb {bank}`), `lock = f"bash {skill}/scripts/mb-lock.sh"` and the
    `coord` slot;
  - the restore hint at `mb-team-checkpoint.sh:71`.
- **Scenario:** a project path with spaces, which is the e2e fixture's own case. The track's `mb-lock.sh run` command
  splits on the space.
- **Fix:** use `shlex.quote` in the render and `%q` in the hint.

**m5. Lock holder command lines leak into the board.**
- **Where:**
  - `scripts/mb-lock.sh:140` records `$*` as `cmd`;
  - `describe()` posts it to COORDINATION.md on reclaim and break (`mb-lock.sh:127,190`);
  - `status --json` prints it.
- **Risk:** a command line with an inline token (`curl -H "Authorization: …"`, `docker login -p …`) lands in the bank.
  The bank is often committed.
- **Fix:** post owner, pid and age only, or keep only `argv[0]`.

**m6. The host-scope lock root comes from `TMPDIR`.**
- **Where:** `scripts/mb_team_config.py:125` and `scripts/mb_lock_resource.py:47`. The logic is duplicated in both.
- **Risk:** shells with a different `TMPDIR` get different lock directories. This happens with sandboxed agent
  shells or with Codex next to Claude Code. The result is no mutual exclusion, and no error.
- **Status:** this follows design §5, so it is a design risk rather than a coding slip.
- **Fix:** use a fixed per-user root, `${MB_LOCK_DIR:-/tmp/mb-locks-$UID}`, computed in one place.

**m7. Path-scoped `arc commit` is unproven.**
- **Where:** `scripts/mb_vcs.sh:2-3,55` claim `arc commit -m … -- <paths>` acts like `git commit --only`.
- **Evidence:** D.md:26 says add and commit were never run against the real arc, only the git-backed shim. For
  harness, arc is the main target.
- **Risk:** if arc commits its whole index, foreign staged files ride along, against REQ-TEAM-063.
- **Fix:** probe once on a scratch arc branch before the first team commit. Until then, `commands/team.md` should
  say so.

**m8. The stop watcher kills only the child pid.**
- **Where:** `scripts/mb-lock.sh:157`.
- **Risk:** `make`, `docker build` and gradle workers keep writing to disk after exit 76. That defeats the disk guard.
- **Fix:** run the child in its own process group (`set -m` or a `setsid` wrapper) and kill the group.

**m9. Track fix cycles have no limit.**
- **Where:** design.md:94 says "bounded by `fix_cycle`", but nothing reads `fix_cycle` as a limit.
- **Risk:** a track can loop between verify and fix with no `stop_human`.
- **Fix:** emit `stop_human fix-cycles:<id>` when `fix_cycle` exceeds a limit, for example `review.max_cycles`.

## Nits

- `tests/bats/test_mb_team_checkpoint.bats:70`: the test "no push anywhere in the scripts" greps only
  `mb-team-checkpoint.sh`. It should also cover `mb_vcs.sh` and `mb_team_ops.py`.
- `tests/bats/test_mb_team_review.bats:164`: the assertion `*"id"*` is nearly vacuous. Assert the message naming the
  issue index.
- Board BLOCKED entries are matched by track id alone. A BLOCKED for `A` from an older team stops `A` of a new team.
  verify.md recorded this as info; still unaddressed.

## Checked and correct

- **`fix_cycles` fix (fix-verify D4):** correct.
  - `review gate` snapshots `fix_cycle` under the team lock (`mb_team_ops.py:235-237`).
  - `review_actions` keeps a fix pending while `fix_cycle <= snapshot`, and `track set --status fixing` increments it.
  - Old entries without the snapshot default to 0, which is backward compatible.
  - `fixing` also resets `collected` (`mb_team_tracks.py:146`), so the fixed track is collected again and the
    `team_review N+1` path works. Probe: `fix A` → `collect` → `team_review 2`.
  - Re-running a gate for the same cycle takes a new snapshot and re-opens the fix. That is consistent with "re-gate
    re-evaluates".
- **`team.json` writer:** flock on `.team.lock`, then a temp file, `fsync` and `os.replace`. Readers never see a
  partial file. A raised body skips the write; `_DryRun` relies on this.
- **Lock primitives:**
  - the lock directory is never empty, so `rename(tmp, lock)` is atomic, and `ENOTEMPTY` makes it exclusive;
  - tickets are published with `link(2)`;
  - a wrapper killed while queued drops its ticket;
  - SIGKILL of the wrapper keeps the lock while the child lives;
  - the child records its own pid before `exec`;
  - maintenance is held to the token;
  - the `remove()` race with a concurrent `break` is a documented ponytail with its ceiling.
- **Commit:** `git commit --only -- <paths>` keeps foreign staged files out (the e2e asserts `stray.txt`). It refuses
  unfinished tracks, open BLOCKED/HANDOVER entries and co-owned files. Without `--yes` and without a TTY it does
  nothing. There is no push path.
- **Engine flags:** without the new flags the output is byte-identical (golden tests). An optional `medium` folds
  into `minor` only for gates that do not declare it.
- **Install:** the manifest test covers every new script, module, template and `team.md` on both hosts, and
  uninstall removes them.
- **Tests:** every non-final `[[ … ]]` in the plan's bats files now carries `|| false`. The remaining bare ones are
  final lines.
