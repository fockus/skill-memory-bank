STATUS: DONE_WITH_CONCERNS

# /mb team: fixes for the verify.md FAIL (DoD 8.6, 11.3)

The plan now has 45 of 45 DoD items ticked for stages 1–11. Stage 12 (2 items) is still deferred under AGR-155.

## Files

| File | Change | Defect |
|---|---|---|
| `tests/bats/test_mb_team_cli.bats` | line 61 pattern is now `*'mb-agree.sh" question "ask about A"'*` with `\|\| false`; lines 18, 38, 51, 62, 80 get `\|\| false` | D1, D2 |
| `tests/bats/test_mb_lock_resource.bats` | lines 112, 128, 146, 160, 196 get `\|\| false` | D2 |
| `tests/bats/test_mb_coord.bats` | lines 294, 295 get `\|\| false` | D2 |
| `tests/bats/test_mb_team_commit.bats` | lines 27, 28, 46, 56, 62, 72 get `\|\| false` | D2 |
| `tests/bats/test_mb_team_review.bats` | lines 44, 149, 257 get `\|\| false` | D2 |
| `scripts/_lib.sh` | the `mb_resolve_path` precedence comment gains step 3, "cwd inside a bank" (now 7 steps) | D5 |
| `tests/bats/test_{codex,cursor,opencode}_adapter.bats`, `test_mb_config_hosts.bats`, `test_proportional_full_suite_once.bats` | `PYTHONUSERBASE="$(python3 -m site --user-base \|\| true)"` | D3, a pre-existing fix outside the plan |
| `scripts/mb_team_status.py`, `scripts/mb_team_ops.py`, `tests/pytest/test_mb_team_state.py` | a pending team-review fix is now keyed on `fix_cycle`, not on second-resolution timestamps | D4, root cause |

The idiom `[[ … ]] || false` is already used 22 times in the repo, for example in `test_upgrade.bats` and `test_mb_freshness.bats`.

## D1: false-green collect assertion

- **Before:** the whole file was green, 10/10. The verifier's `|| false` copy turned test 5 red.
- **After:** `bats tests/bats/test_mb_team_cli.bats` gives `1..10`, 0 not ok.
- **Mutation proof:** in a temp copy I changed the expected text to `ask about Z`:
  ```
  not ok 1 team: collect appends one progress entry per newly returned track; a second run appends nothing
  #   `[[ "$output" == *'mb-agree.sh" question "ask about Z"'* ]] || false' failed
  ```
  With the real text the test is `ok 1`.

## D2: 21 non-final `[[ … ]]` assertions

**Mutation sweep.** For each of the 22 lines (D1 plus D2) I made a copy of the file, flipped `==`/`!=` on that one line, and ran it.
- 20 of 22 failed at the mutated line.
- `lock_resource:128` and `:146` also failed, but bats named the wrong line: 120 and 138, the last failed `eval` inside `wait_for`. This is a bats quirk with `|| false` after a polling helper. To prove which line failed, I put an `echo MARK` right before the mutated line and another right after it. The output had `MARK reached line 128` and `MARK reached line 146`, and the "passed" marker never printed. So the mutated assertion is the one that fails.
- **Result:** all 22 assertions now really check under bash 3.2.

**Affected files after the fix, all with 0 not ok:**

| File | Tests |
|---|---|
| lock_resource | 14 |
| coord | 18 |
| team_cli | 10 |
| team_commit | 4 |
| team_review | 16 |
| resolve_nested_bank + lib | 78 |

## D5

The comment in `_lib.sh` now matches the code. `shellcheck -x scripts/_lib.sh` is clean.

## D3: venv `site --user-base` exit 1 (pre-existing, outside the plan)

- **Cause:** with a venv's `python3`, `python3 -m site --user-base` prints the path but exits 1. Under bats `set -e` that kills `setup`. Adding `|| true` keeps the printed value, so `PYTHONUSERBASE` is byte-identical. Outside a venv the exit code is 0, so nothing changes there.
- **Venv exit code:** `.venv/bin/python3 -m site --user-base` prints `/Users/anton-one/Library/Python/3.14` and exits with `rc=1`.
- **Before** (HEAD copy, venv first in PATH):
  - `test_mb_config_hosts`: `1..30 not_ok=30`, with ``PYTHONUSERBASE="$(python3 -m site --user-base)"' failed``;
  - `test_proportional_full_suite_once`: `1..8 not_ok=8`.
- **After** (venv first in PATH), 0 not ok in every file:

  | File | Tests |
  |---|---|
  | codex | 50 |
  | cursor | 28 |
  | opencode | 51 |
  | config_hosts | 30 |
  | full_suite_once | 8 |

  Without the venv, config_hosts is also 30/30 with 0 not ok.

## D4: team e2e flake, root cause and fix

D4 did not recur in the full run: both `team e2e` tests were ok (#3992 and #3993). I root-caused it anyway, from the code and a repro.

**Root cause.**
- `review_actions` kept a `fix X` action pending while `track.returned_at < gate.at`. Both fields come from `now()`, which has one-second resolution.
- In e2e test 2, A's first return and the cycle-1 gate are about 6 CLI calls apart. When both land in the same second, `returned_at == at`, the fix is dropped, and `next` prints `team_review 2` instead of `fix A`. That is the assertion `[ "$output" = "fix A" ]`.
- `<=` would just move the bug: a fixed track returning within the gate's second would re-open its fix.

**Repro with the real CLI** (fixture from `team_fixture.bash`, scratch dir, A's `returned_at` forced to `gate.at`):
```
before fix: next (as recorded): fix A   |  next (returned_at == gate.at): team_review 2
after fix:  next (as recorded): fix A   |  next (returned_at == gate.at): fix A
```

**Fix.**
- `review gate` now stores a `fix_cycles` snapshot (track id → `fix_cycle`) in the review entry, taken under the team lock.
- A fix stays pending while the track's `fix_cycle <= snapshot`. `track set --status fixing` already increments `fix_cycle`, so "the track went through fixing after the gate" is now exact.
- The old test step that moved `returned_at` now bumps `fix_cycle`. The new test `test_fix_is_pending_until_the_track_goes_through_fixing_even_within_the_gate_second` failed on the first assert before the fix (RED) and passes after it.

**Evidence after the fix.**

| Check | Result |
|---|---|
| `pytest test_mb_team_state.py` | 40 passed |
| bats team_review | 16/16 |
| bats team_cli | 10/10 |
| bats team_commit | 4/4 |
| bats `tests/e2e/test_mb_team_e2e.bats` | 2/2 |
| ruff | clean |
| file lengths | `mb_team_status.py` 272 lines, `mb_team_ops.py` 274 lines |

## Lint

- `shellcheck -x scripts/_lib.sh scripts/mb-team.sh`: clean.
- `shellcheck -S warning` on the 10 touched bats files: only pre-existing warnings, none on a touched line. These are SC2088 in cursor 358–365, plus SC2034 and SC2010 in opencode.
- `ruff check scripts/mb_team_state.py scripts/mb_team_status.py scripts/mb_team_ops.py tests/pytest/test_mb_team_state.py`: no issues.

## Full suite

- **Command:** `PATH="$PWD/.venv/bin:$PATH" bash scripts/mb-test-run.sh --dir . --out json`, run from `/Users/anton-one/Apps/skill-memory-bank`.
- **Time:** 01:35 to 05:20, 13502 s. Load average was about 44 because of parallel sessions.
- **Result:** `stack=bats+python, tests_total=8609, tests_failed=17, runner_error=false`. The verifier's run had 188 failures.

| Failures | Count | Class (verify.md row) |
|---|---|---|
| `test_mb_flow_closure_guard_budget` (6), `_cache` (4) | 10 | done-gates session, `hooks/mb-flow-closure-guard.sh` |
| `hooks/tests/recall-disclosure.bats`: per-chunk, id ×2, id-collision | 4 | pre-existing on f050443 |
| `hooks/tests/spawn-discipline.bats` #4184, "pi adapter marks the index dirty" | 1 | pre-existing on f050443 |
| `test_audit_command_contracts::test_done_global_bank_supplies_gate_configuration` | 1 | done-gates session (`IndexError`: the `commands/done.md` section is missing) |
| `test_skill_naming_v2::test_no_v1_plan_md[*.py]` | 1 | done-gates session (only offender is `tests/pytest/test_mb_done_scope.py`) |
| codex, cursor, opencode, config_hosts, full_suite_once | 0 | D3 fixed (was 167) |
| team e2e | 0 | D4 did not recur, root cause fixed |
| flakes from verify.md (recall «fusion», audit_install_roundtrip) | 0 | did not recur |

None of the 17 is ours. The bats log was kept by a hardlink on the runner's mktemp file. Since D4 did not recur, I did not copy it into the repo.

**Mid-run edit.** The D4 fix landed about 10 minutes after an earlier run started. I killed that run, see the next section. The counted run started at 01:35, after all edits. The team files were also rerun separately on the final code; results are in the D4 section.

## Concerns

- **Low: TMPDIR artefact.** My first full run used a custom `TMPDIR` to catch the runner's log. Under any non-default TMPDIR, `test_bats_test_names.bats` fails at `line 0` (bats-internal); it passes with the default TMPDIR. That run was discarded, and the counted run used the verifier's exact command. Possible follow-up outside the plan: bats suite fragility under a custom TMPDIR.
- **Low: design sketch.** The C1 `reviews` sketch in `specs/mb-team/design.md` does not show `actions`, `at` or the new `fix_cycles`. It was already incomplete, so I left it. T-DOCS or the owner can sync it if C1 is meant to be exhaustive.
- **Info: wording of DoD 11.3.** The item says "classified as pre-existing". 5 of the 17 failures are pre-existing on f050443. The other 12 come from the parallel done-gates session's uncommitted edits, which verify.md already accepted as a class.
- **Follow-up outside the plan:** bats reports the wrong failure line for `[[ … ]] || false` after a polling helper. This is cosmetic.

Nothing committed; install.sh was not run; no done-gates files were touched.

## Review fixes (review.md: 5 major, 3 minor)

STATUS: DONE_WITH_CONCERNS. Each fix started from a test that failed first, and the failure was for the stated reason.

| Id | Fix | RED test, then green |
|---|---|---|
| M1 | `mb_team_status.decide`: the `fixing → fix <id>` rule is removed. `fixing` is already in `ACTIVE`, so `next` answers `wait` for it. `fix <id>` now comes only from a gate-routed fix or a rejected light report. `commands/team.md` (the `fix`/`wait` rows and §5) and design §3/§9 now say: set `--status fixing`, then re-dispatch yourself. | `test_next_waits_for_a_track_already_fixing_instead_of_a_second_dispatch`. It returned `['fix A']`, now `['wait']`. `test_next_post_steps_follow_the_track_pipeline` no longer expects `fix D`. |
| M2 | `post_steps(track, accepted)` and `collectable(track, rs, accepted)`: an accepted light track with no verifier and no review owes nothing. New `light_acceptance(bank, team)` is shared by `gather()` (next) and `cmd_collect` (ops). | pytest `test_next_collects_an_accepted_light_track_without_verifier_or_review`. bats `team: an accepted work:light track without verifier or review is collected` failed with `collected: none` after `next` had already said `collect`. |
| M3 | `proc_start` runs `ps` with `LC_ALL=C TZ=UTC`. | `test_alive_does_not_depend_on_the_callers_time_zone_or_locale` recorded `воскресенье, 11 октября 2026 г. 09:26:26` and judged a live pid dead. |
| M4 | `mb_vcs.sh changed`:<br>• git: `git -c core.quotePath=false diff --name-only -z --no-renames <base>`, NUL-separated like `untracked`, and a rename lists both sides;<br>• arc: there is no `-z` or quotePath in `arc diff --help`, so `arc diff --name-only | tr '\n' '\0'`.<br>Consumers split on NUL: `mb_team_ops._owned` and the checkpoint manifest. `add` skips a path gone from both tree and index (the old side of a staged rename, where `git add` died with "pathspec did not match"). `add` and `commit` use `--literal-pathspecs`. C6 in design.md is updated. | • `git: changed is NUL-separated, keeps non-ASCII and space paths raw, lists both sides of a rename`;<br>• `git: add and commit take both sides of a staged rename` (exit 128 before);<br>• `commit: an owned file with a cyrillic name and a space is staged` (exit != 0 before). |
| M5 | `collect` prints `shlex.quote` words for the script path and the text. | Line 61 now pins `mb-agree.sh question 'ask about A'`. New test `collect prints report questions as inert shell words`: a question with backticks, `$( )` and `'`. The test `eval`s the printed words and checks the literal text, with no `pwned` files created. Before the fix it failed at the `eval`. |
| m8 | `mb-lock.sh run` starts the child in its own process group (`set -m` for that one fork only). The stop watcher and `on_signal` send TERM to `-$CHILD`. | `lock: a stop condition terminates the whole command process group, grandchildren included`. rc was 76 but the grandchild `sleep` survived. |
| m9 | `decide`: a fix at `fix_cycle >= team.review.max_cycles` (default 5) becomes `stop_human fix-cycles:<id>`. A `fixing` track past the cap also stops. Documented in team.md (stop reasons) and design §3. | `test_next_stops_for_the_human_when_a_track_used_up_its_fix_cycles` |
| m5 | `mb-lock.sh run` records only the program name (`${1##*/}`) as `cmd`. The C4 note is in design.md. | `lock: the holder's command arguments never reach meta, status or the board`. `cmd` held the whole `bash -c … token=SECRET-123`. |

Also, in `test_mb_vcs.bats`, which I touched: the two non-final `[[ … ]]` at line 22 (the verifier's list missed them) now end in `|| false`.

**Evidence.** All runs are on the final code from the physical path.
- `pytest test_mb_team_state test_mb_lock_queue test_mb_team_command test_mb_team_render test_mb_team_pipeline test_mb_work_light test_doc_counts test_command_descriptions`: 303 passed. After a trim, `test_mb_team_state` alone: 43 passed.
- bats, all with 0 not ok:

  | File | Tests |
  |---|---|
  | lock_resource | 16 |
  | vcs | 14 |
  | team_cli | 12 |
  | team_commit | 5 |
  | team_review | 16 |
  | team_checkpoint | 7 |
  | e2e team | 2 |
  | lock_corruption | 9 |
  | lock_helper | 21 |
  | bats_test_names | 1 |
- `ruff check` (touched .py): clean.
- `shellcheck -x mb-lock.sh mb_vcs.sh mb-team-checkpoint.sh`: clean.
- `shellcheck -S warning` (touched bats): clean.
- Sizes:

  | File | Lines |
  |---|---|
  | `mb_team_status.py` | 287 |
  | `mb_team_ops.py` | 276 |
  | `mb_lock_queue.py` | 299 |
  | `test_mb_team_state.py` | 298 |
  | `mb-lock.sh` | 228 |

  All are still under 300, so DoD 8.6 holds.
- The 4-hour full suite was not rerun, as instructed.

**Concerns.**
- **Low.** The arc `changed` path for non-ASCII names is unproven against the real arc (only the git shim was tested). It belongs with m7: probe `arc diff --name-only` once on a scratch arc branch.
- **Low.** `set -m` in `mb-lock.sh` turns job control on for one fork in a non-interactive shell. bash 3.2 and 5 both give the job its own process group. Exit 76 and the SIGKILL-wrapper tests are green.

**Left as follow-ups:**
- m1: glob routing differs between review and commit, and the mirror prefix is not stripped;
- m2: a traceback in `review gate` is read as exit 1;
- m3: checkpoint ids collide at minute resolution, and `--label` is not validated;
- m4: unquoted copy-paste commands in render and the restore hint;
- m6: the host-scope lock root comes from `TMPDIR`;
- m7: a probe of path-scoped `arc commit`;
- the nits: no-push grep scope, the vacuous `*"id"*` assertion, board BLOCKED ids not scoped to a team.
