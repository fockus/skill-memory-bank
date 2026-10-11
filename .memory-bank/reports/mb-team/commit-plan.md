# /mb team: commit staging plan

STATUS: DONE_WITH_CONCERNS. Nothing staged or committed in the real repo. Base: HEAD `f050443`.

## Artefacts

| File | What |
|---|---|
| `/tmp/mbteam-paths.lst` | 102 whole files, one per line (includes this report) |
| `/tmp/mbteam-partial.patch` | /mb team hunks of 3 mixed files; `git apply --cached --check` ok |
| `/tmp/mbteam/filter_hunks.py` | generator of the patch (per-file exclude regex, recounts hunk headers) |
| `/tmp/mbteam-stage.sh` | NUL-safe `git add` of the list + `git apply --cached` of the patch; refuses on a non-clean index |
| `/tmp/mbteam-commit-msg.txt` | `feat(team): add /mb team for parallel tracks in one shared tree` + Co-Authored-By |

## Counts

- `git status --short -uall`: 516 paths. Commit: 104 files (101 whole + 3 partial; this report is the 102nd whole file), 9939 insertions, 48 deletions (measured in the worktree without this report).
- Whole files: 33 tracked-modified with only /mb team hunks, 68 new (code, tests, templates, fixtures, `commands/team.md`, `specs/mb-team/*` (3), `plans/2026-10-10_feature_mb-team.md`, `reports/mb-team/*` (14)).
- Tracked-modified whole files include the D3 one-liner `site --user-base || true` in 5 adapter/host bats (done in fix-verify) and the `medium` line in all 6 `agents/mb-reviewer-*.md`.

## Mixed files

| File | Included | Excluded (other session) |
|---|---|---|
| `commands/mb.md` | router row `team <subcommand>` | `/mb done` line (done-gates) |
| `references/scripts.md` | Contents link, "Team runs and resource locks" section, 15 internal-lib rows (`mb_team_*`, `mb_lock_*`, `mb_pipeline_validate_team.py`, `mb_work_light.py`) | `mb-goal-state.sh` row; rows `_test_run_stacks.sh`, `mb_done_{gates,runtime,scope}.py`, `mb_review_cache.py` (H10 wrote them, but the scripts are done-gates and stay out of this commit) |
| `.memory-bank/agreements.md` | AGR-097 line (Anton's /mb team decision, referenced by spec, plan and code comments) | AGR-096 (Codex session) |

Left out entirely: `CLAUDE.md` (stamp + agreements block, done-gates/codex), `progress.md`, `checklist.md`, `COORDINATION.md` (chronological, mixed), all done-gates files (brief list + `mb_done_*`, `mb_review_cache.py`, `_test_run_stacks.sh`, `mb-goal-state.sh`, `mb_rules_check_lib.sh`, their tests), `.pi/**`, `reports/pi-native-integration/**`, `:memory:.ses`, other plans.

## Index is not clean (blocker for a plain commit)

The real index already holds 4 staged entries of another session: deletions of `plans/2026-05-23_feature_cost-multi-model.md`, `plans/2026-09-05_fix_mb-work-cost-diet-sprint{2,3}.md` and the move `plans/2026-06-23_SEQUENCE_codex-remediation.md` → `plans/done/`. `git commit` would sweep them in. `mb-team-stage.sh` exits 1 and prints them (checked: rc=1, nothing staged). Unstage them first (`git restore --staged`, worktree untouched; the script prints the exact command and how to re-stage), or let their owner commit first.

## Worktree check (`git worktree add /tmp/mbteam-wt HEAD`, copy list, `git add`, `git apply --index` patch)

Index in the worktree: 104 files. Python from the main repo `.venv`.

| Set | Result |
|---|---|
| pytest: doc_counts, mb_team_command, mb_team_state, lock_queue, team_render, team_pipeline, team_config, work_light, work_step_models, command_descriptions, mb_pipeline_validate, pipeline_default_yaml, mb_coord_docs, spec_corpus_battery | 431 passed |
| bats lock_resource 16, vcs 14, team_cli 12, team_commit 5, team_review 16, team_checkpoint 7, mb_coord 18, resolve_nested_bank 4, work_severity_medium 12, workflow_lenses 8, lock_corruption 9, lock_helper 21, bats_test_names 1, lib 74 | 0 not ok |
| bats codex 50, cursor 28, opencode 51, config_hosts 30, full_suite_once 8 | 0 not ok |
| bats `tests/e2e/test_mb_team_e2e.bats` | 2/2 ok |
| bats `tests/e2e/test_install_uninstall.bats` (temp HOME, own MB_MANIFEST_PATH) | 57 run, 56 ok; `ok 15 install: ships the /mb team bundle; uninstall removes it` |
| ruff (team .py + touched tests), shellcheck -x (5 team scripts, `_lib.sh`, `mb-coord.sh`) | clean |

The one red, `not ok 16 install: Claude and Codex aliases resolve to canonical skill path` (`[ "$claude_canonical" = "$REPO_ROOT" ]`), is the environment class W11 already recorded: `/tmp` is a symlink to `/private/tmp`. Rerun from the physical path `/private/tmp/mbteam-wt`: `ok 1`. Executable bits are staged (`100755` for the 5 team scripts, `mb_team_review.py`, `arc-shim/arc`). The worktree was removed with `git worktree remove --force` (it held staged changes); `git worktree list` shows only main.

## Concerns

- **Med:** the foreign staged entries above; someone has to unstage them or commit them first.
- **Low:** `CLAUDE.md` agreements block in the commit does not list AGR-097 (that file stays out); `mb-agree.sh sync` fixes it with the other session's commit.
- **Low:** the full suite was not run on the staged content (the targeted sets above cover every /mb team file and every mixed hunk).
