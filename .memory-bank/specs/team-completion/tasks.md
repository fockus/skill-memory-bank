# Tasks: team-completion

> Slice S2 of `[SPEC:autopilot]`. Three implementation tasks cut at owner/risk boundaries (AGR-078), then the two
> rendered test layers. Order: Task 1 and Task 3 in parallel (disjoint Scope), Task 2 after Task 1 (same files),
> layers last. Eval first (red) → implementation (green); full suite once at the end of the spec.

<!-- mb-task:1 -->
## Task 1: Every track runs through /mb work

**Stage:** 1
**Covers:** REQ-001, REQ-002
**Role:** backend
**Blocked-by:** none
**Scope:** scripts/mb_team_pipeline.py, scripts/mb_pipeline_validate_team.py, scripts/mb_team_vocab.py, scripts/mb_team_render.py, scripts/mb_team_tracks.py, scripts/mb_team_status.py, references/pipeline.default.yaml, docs/pipeline-yaml.md, commands/team.md, tests/pytest/test_mb_team_work_tracks.py, tests/pytest/test_mb_team_pipeline.py, tests/pytest/test_mb_team_render.py, tests/pytest/test_mb_team_state.py, tests/bats/test_mb_team_cli.bats
**Budget:** 70000
**Eval:** python3 -m pytest -q tests/pytest/test_mb_team_work_tracks.py tests/pytest/test_mb_team_pipeline.py tests/pytest/test_mb_team_render.py tests/pytest/test_mb_team_state.py — red: presets still resolve mode direct and a track added without --source has no work source; exit: 1; output~: FAILED tests/pytest/test_mb_team_work_tracks.py

**What to do:**
- Design C2: enums `mode ∈ {work}`, `work ∈ {orchestrated}` in `mb_pipeline_validate_team.py`; `direct`/`light`
  refused with a message naming REQ-001; bundled presets in `references/pipeline.default.yaml` all
  `mode: work`, `work: orchestrated` (tdd/verifier/review/models/effort unchanged).
- `mb_team_pipeline.resolve()`: drop the "mode: work needs a source" error and the `direct` default;
  `mb_team_tracks.py track add`: `source` defaults to the track prompt path.
- `mb_team_vocab.py`: remove the `direct` and `light` phrase rows.
- `mb_team_render.pipeline_lines`: one "runs through /mb work on <source>, driven by the orchestrator" line.
- `mb_team_status.py`: delete `_light`, `post_steps`, `light_acceptance` and the verify/review/light branches of
  `decide` (REQ-002); `collectable` = finished, or returned with a DONE/DONE_WITH_CONCERNS report; `words()` prints
  the workflow. `mb_team_ops.py` imports only `collectable`/`report_status` afterwards (no edit expected there:
  if one is needed, coordinate with Task 3, which owns that file).
- Docs: `commands/team.md` §2 presets table and prompt vocabulary, §5 (one execution path: the orchestrated
  `/mb work` loop, workflow mapping, path-keyed claim — design C2); `docs/pipeline-yaml.md` team block.
- Remove the `work:light` tests (`tests/bats/test_mb_team_cli.bats:165`, `tests/pytest/test_mb_team_state.py`
  light/post-step tests) and the `direct`/`light` layering pairs in `tests/pytest/test_mb_team_pipeline.py`.

**Testing (TDD — tests BEFORE implementation):**
- `tests/pytest/test_mb_team_work_tracks.py`: every bundled size resolves `mode: work`/`orchestrated` with the
  AGR-097 verifier/review values; `mode=direct` and `work=light` are refused naming REQ-001; a track added without
  `--source` stores its prompt path as source; a returned standard track with `STATUS: DONE` gives `collect`, never
  `verify`/`review`.

**DoD:**
- [x] every bundled preset resolves to `mode: work`, `work: orchestrated`; `direct`/`light` refused with exit 2
- [x] a track without `--source` runs on its own prompt (`mb-work-plan.sh --target <prompt>` yields one stage item)
- [x] `team next` never prints `verify <id>` or `review <id>`
- [x] tests pass (were red); ruff clean on touched Python files; touched files < 400 lines
<!-- /mb-task:1 -->

<!-- mb-task:2 -->
## Task 2: Team stops, last STATUS line and host dispatch

**Stage:** 2
**Covers:** REQ-003, REQ-004, REQ-005, REQ-006, REQ-013
**Role:** backend
**Blocked-by:** 1
**Scope:** scripts/mb_team_status.py, templates/team/brief.md, commands/team.md, tests/pytest/test_mb_team_next.py, tests/pytest/test_mb_team_state.py, tests/pytest/test_mb_team_command.py
**Budget:** 50000
**Eval:** python3 -m pytest -q tests/pytest/test_mb_team_next.py tests/pytest/test_mb_team_state.py tests/pytest/test_mb_team_command.py — red: a cancelled dependency and a red flow still give wait, STATUS is read from the first line only; exit: 1; output~: FAILED tests/pytest/test_mb_team_next.py

**What to do:**
- Design C1 in `decide`: `stop_human blocked:dep-cancelled:<dep>` per cancelled dependency of a planned track;
  after all done + collected + review clean/off: `goal-red`, then `flow-red:<names>`, else `stop_success`;
  a non-empty stop list is returned alone (deduplicated).
- Design C4: `gather()` → `flow_red()` with `mb-flow-verify.sh <bank> --skip acceptance`, names from the summary
  JSON (`status` fail/broke), `["broke"]` when unparsable.
- Design C3: `report_status` takes the last STATUS line; `templates/team/brief.md` § Report wording.
- `status`: dependents of a cancelled track show `blocked:dep-cancelled:<dep>`.
- `commands/team.md`: §4 table (new stop reasons, "a stop_human is printed alone", `verify`/`review` rows gone),
  §9 Hosts per design C10 linking `SKILL.md` § Invocation; one line on drive interplay (design *Drive interplay*).

**Testing (TDD — tests BEFORE implementation):**
- `tests/pytest/test_mb_team_next.py` on `decide()` with fact fixtures: cancelled dep → exactly the stop line, no
  `dispatch` of another ready track; all collected + goal red → `stop_human goal-red`; flow red → `flow-red:tests`;
  stop plus collectable → only the stop; a report ending in `STATUS: DONE` after other text → `DONE`; `**STATUS:**
  BLOCKED` as the last STATUS line wins over an earlier one.
- `flow_red` against a stub `mb-flow-verify.sh` summary (fail, broke, unparsable) — the stub is the only mock.
- `tests/pytest/test_mb_team_command.py`: §9 names the four hosts and links `SKILL.md` § Invocation, whose table has
  the four rows.
- Update the `wait`-expecting case of `test_next_no_stop_success_when_one_condition_fails` in
  `tests/pytest/test_mb_team_state.py`.

**DoD:**
- [x] cancelled dep, goal red and flow red each end in one `stop_human` line, never `wait`
- [x] any `stop_human` is printed alone
- [x] STATUS read from the last STATUS line
- [x] `commands/team.md` §9 covers Claude Code, Codex, OpenCode, Pi through the `SKILL.md` table
- [x] tests pass (were red); ruff clean; `scripts/mb_team_status.py` < 400 lines
<!-- /mb-task:2 -->

<!-- mb-task:3 -->
## Task 3: Commit, review, checkpoint and lock hardening

**Stage:** 1
**Covers:** REQ-007, REQ-008, REQ-009, REQ-010, REQ-011, REQ-012
**Role:** backend
**Blocked-by:** none
**Scope:** scripts/mb_vcs.sh, scripts/mb_team_ops.py, scripts/mb_team_review_core.py, scripts/mb-team-checkpoint.sh, scripts/mb_team_config.py, scripts/mb_lock_resource.py, tests/bats/test_mb_team_hardening.bats
**Budget:** 60000
**Eval:** bats tests/bats/test_mb_team_hardening.bats — red: a failed commit leaves files staged, the review gate crashes on non-JSON, checkpoint ids collide; exit: 1; output~: not ok [0-9]+

**What to do:**
- Design C5: `mb_vcs.sh index-save` / `index-restore` (git; arc exits 3); `mb_team_ops.cmd_commit` snapshots the
  owned paths before `add`, restores them when `add` or `commit` fails, then re-raises with "index restored"
  (on arc: the staged paths on stderr).
- Design C6: `mb_team_review_core.Ctx.owner` strips tree or mirror prefix and uses `mb_team_state.owns`.
- Design C7: `cmd_review_gate` returns 2 on non-JSON gate output, `reviews[]` untouched.
- Design C8: checkpoint label check (exit 2), per-second id, existing id refused (exit 1, nothing written).
- Design C9: `mb_team_config.host_lock_root()` (MB_LOCK_DIR or `/tmp/mb-locks-<uid>`, 0700, owner/symlink check);
  `mb_lock_resource.lock_root` calls it; the `TMPDIR` code goes.

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_mb_team_hardening.bats` on the team fixture (`tests/bats/lib/team_fixture.bash`): failing
  pre-commit hook → `team commit --yes` exits 1 and `git diff --cached --name-only` equals the pre-run list (a
  foreign staged file included); `src/**/*.py` routes `src/x.py` to its committer and `src/*.py` does not route
  `src/sub/y.py`; a gate stub printing no JSON → exit 2, no `Traceback`, `reviews[]` unchanged; two checkpoints
  with one label in one second → the second refused, files intact; label `../x` → exit 2; host lock root equal
  under two `TMPDIR` values with `MB_LOCK_DIR` unset.

**DoD:**
- [x] failed commit restores the index of the staged paths; foreign staging untouched
- [x] review routing and commit agree on ownership
- [x] review gate, checkpoint label and duplicate id fail cleanly with the documented exit codes
- [x] host lock root computed in one function, independent of `TMPDIR`
- [x] tests pass (were red); ruff and shellcheck clean on touched files; touched files < 400 lines
<!-- /mb-task:3 -->

<!-- mb-task:4 -->
## Task 4: Integration tests

**Stage:** 4
**Layer:** integration
**Covers:** REQ-001, REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010, REQ-011, REQ-012, REQ-013
**Role:** qa
**Scope:** tests/**
**Budget:** 100000

**What to do:**
- Integration tests over the real wiring; mock only external boundaries.
- Test function names follow the C4 mapping rule: `test_` + the scenario's `test_id` with `-` replaced by `_`.

**Testing (TDD — tests BEFORE implementation):**
- The success scenario plus the spec's main edge scenarios.

**DoD:**
- [x] Covers scenario test ids: `test_REQ_001__track_runs_through_the_work_loop`, `test_REQ_003__cancelled_dependency_stops_the_team`, `test_REQ_004__red_flow_after_the_last_collect_stops_the_team`, `test_REQ_007__failed_commit_leaves_the_index_as_it_was`, `test_REQ_009__broken_inputs_are_refused_cleanly`, `test_REQ_013__track_dispatch_is_described_for_four_hosts`; green (were red)
- [x] External mocks ≤5 (Testing Trophy)
<!-- /mb-task:4 -->

<!-- mb-task:5 -->
## Task 5: E2E tests

**Stage:** 4
**Layer:** e2e
**Covers:** REQ-001, REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010, REQ-011, REQ-012, REQ-013
**Role:** qa
**Scope:** tests/e2e/**
**Budget:** 100000

**What to do:**
- E2E tests over the real wiring; mock only external boundaries.
- Test function names follow the C4 mapping rule: `test_` + the scenario's `test_id` with `-` replaced by `_`.

**Testing (TDD — tests BEFORE implementation):**
- The success scenario plus the spec's main edge scenarios.

**DoD:**
- [x] Covers scenario test ids: `test_REQ_001__track_runs_through_the_work_loop`, `test_REQ_003__cancelled_dependency_stops_the_team`, `test_REQ_004__red_flow_after_the_last_collect_stops_the_team`, `test_REQ_007__failed_commit_leaves_the_index_as_it_was`, `test_REQ_009__broken_inputs_are_refused_cleanly`, `test_REQ_013__track_dispatch_is_described_for_four_hosts`; green (were red)
- [x] External mocks ≤5 (Testing Trophy)
<!-- /mb-task:5 -->
