# Track C — mb-team review until clean (master-completion Stage 11, implementer step)

STATUS: DONE_WITH_CONCERNS

## Findings triage (fix-verify.md:198-205)

| id | Reproduces on current tree? | Verdict | Action |
|---|---|---|---|
| m1 glob routing / mirror prefix | No. `Ctx.owner` (`scripts/mb_team_review_core.py:73-87`) routes through `st.owns` and strips both `tree` and `mirror` | already fixed | Covered by `test_mb_team_hardening.bats:23`. Nothing to do. |
| m2 traceback read as exit 1 | No. `cmd_review_gate` (`scripts/mb_team_ops.py:153-173`) parses defensively and returns 2 without writing `reviews[]` | already fixed | Covered by `test_mb_team_hardening.bats:41`. Nothing to do. |
| m3 checkpoint id collision, unchecked label | No in code: seconds in the id, refuse an existing id, label regex (`mb-team-checkpoint.sh:26-30`). Correction (review C1-n3): `test_mb_team_hardening.bats` already tested both; I missed that | already fixed, tested | Added 2 regression tests (duplicates of the hardening ones) (label `../x` refused with nothing written; a same-second id refused with the first checkpoint intact, using a pinned `date` shim) |
| m4 unquoted copy-paste commands | **Yes**, in render (`_resource_block`, `lock`, `coord`, brief `bank` slot, `--mb` line, contract command) and in the checkpoint restore hint (which also was not runnable at all: the `(arc trees: …)` part sits inside the command) | real defect (medium) | **Fixed** with failing tests first: `shlex.quote` in `mb_team_render.py`; the restore hint is now `printf %q` and split into a git line and a separate `restore (arc trees):` line |
| m6 lock root from TMPDIR | No in code: one `host_lock_root()` in `mb_team_config.py:44`, `MB_LOCK_DIR` or `/tmp/mb-locks-<uid>`, also used by `mb_lock_resource.py` | already fixed in code; doc drift | Added a regression test (two different `TMPDIR` give one path). Fixed `design.md` §C3, which still said `${TMPDIR:-/tmp}/mb-locks` |
| m7 path-scoped `arc commit` unproven | Yes. `arc` is not installed on this host, so the probe cannot run here | minor (needs a real arc client) | Caveat added to `commands/team.md` §7 and the `mb_vcs.sh` header. Backlog line below |
| nit: no-push grep scope | Yes | trivial | Fixed: the test now also greps `mb_vcs.sh` and `mb_team_ops.py` (a docstring "No push." is excluded) |
| nit: vacuous `*"id"*` assertion | Yes | trivial | Fixed: asserts `issues [0] have no string id` |
| nit: board BLOCKED not scoped to a team | Yes (`mb_team_status.py:101`, `mb_team_ops.py:48` match by track id only) | minor | Backlog. The fix would touch `mb_team_status.py`, which is 296 lines and close to the SRP limit |

## Files
- `/Users/fockus/Apps/skill-memory-bank/scripts/mb_team_render.py`: `shlex.quote` on every path in a copy-paste command
- `/Users/fockus/Apps/skill-memory-bank/scripts/mb-team-checkpoint.sh`: restore hint uses `%q`, git and arc on separate lines
- `/Users/fockus/Apps/skill-memory-bank/scripts/mb_vcs.sh`: one header comment line (arc scoping is checked only against the shim)
- `/Users/fockus/Apps/skill-memory-bank/commands/team.md`: §7 commit, arc caveat (2 lines)
- `/Users/fockus/Apps/skill-memory-bank/.memory-bank/specs/mb-team/design.md`: §C3 lock root, and the example path
- `/Users/fockus/Apps/skill-memory-bank/tests/pytest/test_mb_team_render.py`: +1 test
- `/Users/fockus/Apps/skill-memory-bank/tests/pytest/test_mb_team_config.py`: +1 test (see the concern about the formatter)
- `/Users/fockus/Apps/skill-memory-bank/tests/bats/test_mb_team_checkpoint.bats`: +3 tests, no-push scope widened
- `/Users/fockus/Apps/skill-memory-bank/tests/bats/test_mb_team_review.bats`: one assertion tightened

## Tests (failing before, passing after)

m4 render (new test, red before the fix):
```
$ PYTHONPATH=. python3 -m pytest -q tests/pytest/test_mb_team_render.py -k spaces
E                     - survi0/bank dir
E                     + survi0/bank
FAILED tests/pytest/test_mb_team_render.py::test_copy_paste_commands_survive_paths_with_spaces
1 failed, 12 deselected
# after:
$ PYTHONPATH=. python3 -m pytest -q tests/pytest/test_mb_team_render.py
13 passed in 7.66s
```

m4 restore hint (new test, red before the fix):
```
$ bats tests/bats/test_mb_team_checkpoint.bats
not ok 10 restore hint is a runnable command for paths with spaces
#   `eval "$cmd"' failed with status 2
#   eval: syntax error near unexpected token «(»
# after:
ok 1 … ok 10 (10/10), shellcheck clean
```

m3 and m6 regression tests (new tests, green on arrival because the code was already fixed):
`ok 8 label with a path separator is refused and nothing is written`,
`ok 9 second checkpoint with the same id is refused and the first stays intact`,
`test_host_lock_root_ignores_tmpdir_so_every_shell_shares_one_lock`: 1 passed.

DoD suites:
```
$ PYTHONPATH=. python3 -m pytest -q tests/pytest/test_mb_team_*.py tests/pytest/test_mb_lock_queue.py
1 failed, 266 passed in 116.83s
FAILED test_mb_team_command.py::test_router_index_and_counts_list_team   (not this track, see Questions)
$ bats tests/bats/test_mb_team_*.bats tests/bats/test_mb_lock_*.bats
1..107, ok 107, no "not ok", bats-rc=0
$ ruff check (changed .py): All checks passed · shellcheck mb-team-checkpoint.sh mb_vcs.sh: clean
```

## Remaining
- DoD "lens review 0 blocker/major/medium" is the orchestrator's gate after this step.

## Questions for the orchestrator
- `test_router_index_and_counts_list_team` is red only because of Track D's in-flight split of `commands/mb.md`
  (HEAD has the `| \`team …commands/team.md` row; the working copy moved it to `references/mb/team.md`). I posted
  HANDOVER on the board with the exact edit: read through `mb_corpus.read_mb_corpus()` and match
  `^(\| |- )\`team .*commands/team\.md`. I did not apply it, because it would import Track D's untracked
  `tests/pytest/mb_corpus.py` and break if C is committed before D.

## Concerns
- Low: a PostToolUse formatter hook reformatted all of `tests/pytest/test_mb_team_config.py` when I added one test
  through Edit (the diff shows about 97 lines, almost all formatting, with no behaviour change). Restoring the HEAD
  formatting was blocked by the auto-mode classifier. If you want a minimal diff, before you commit, keep only
  the new `test_host_lock_root_ignores_tmpdir_so_every_shell_shares_one_lock` hunk.

## Follow-ups (backlog lines)
- m7: probe `arc commit -m … -- <paths>` and `arc diff --name-only` (non-ASCII names) once on a scratch arc branch with
  a foreign staged file; until then, path-scoped arc commit stays documented as unproven (minor: needs a real arc
  client, not reproducible on this host).
- nit board scope: board BLOCKED/HANDOVER entries match a team track by id alone, so an old team's open BLOCKED for `A`
  stops `A` of a new team. Scope them by date ≥ `team.created` or by topic (minor: a stale entry needs a manual ACK
  to clear; it does no harm to data).

## Fix cycle 1 (review C-review/cycle-1: 0 blocker · 0 major · 7 medium)

| id | Fix | Test (red → green) | Files |
|---|---|---|---|
| C1-M1 | `init` refuses an existing team before `mb-work-budget.sh init` (which resets spent to 0) | `test_mb_team_cli.bats` "a refused re-init with --budget keeps the live team's spent budget": red `[[ "$output" == *"spent=400"* ]] failed` → ok | `scripts/mb_team_tracks.py`, `tests/bats/test_mb_team_cli.bats` |
| C1-M2 | `create`: `umask 077`, `chmod 700` on the dir, `.gitignore` with `*` when there is none; the Python block drops untracked paths whose realpath is under realpath(dir) (arc, or a kept `.gitignore`) | `test_mb_team_checkpoint.bats` "checkpoint dir inside the tree is private, git-ignored and never tars itself": red on the mode-700 check → ok. "checkpoint dir the VCS still lists (own .gitignore kept) is left out of the tar": green with the fix, and red with the filter mutated out (`[ "$output" = "new.txt" ]` failed), so it pins the realpath filter | `scripts/mb-team-checkpoint.sh`, `tests/bats/test_mb_team_checkpoint.bats` |
| C1-M3 | Liveness split into the new `scripts/mb_lock_liveness.py` (`HOST`, `proc_start`, `alive`, `holder_alive`). An unknown start time counts as alive, and `proc_start` returns None on `OSError` (no `ps`). `mb_lock_queue.py` imports them: 299 → 261 lines (C1-m19) | `test_mb_lock_queue.py::test_live_pid_with_unknown_start_time_is_alive_and_never_reclaimed[no-lstart, no-ps]`: red 2 failed → green. It patches `subprocess.run`, so it does not depend on module layout | `scripts/mb_lock_liveness.py` (new), `scripts/mb_lock_queue.py`, `tests/pytest/test_mb_lock_queue.py` |
| C1-M4 | Every `[ ] && [ ]` assertion in `test_mb_team_checkpoint.bats` is split into separate lines; `[[ ]]` gets `\|\| false`. The other `&&` lines in `test_mb_lock_*.bats` are teardown guards and wait loops, not assertions | 12/12 ok | `tests/bats/test_mb_team_checkpoint.bats` |
| C1-M5 | Test-only: commit gate with a contract | `test_mb_team_gate.py`: a failing frozen item → rc 1, `contract spec REQ-001`, A to fixing, HEAD and index unchanged; unfrozen → rc 1 `not frozen`, HEAD unchanged; frozen and passing → committed, A done. 3 passed (a test-only gap, so green on arrival) | `tests/pytest/test_mb_team_gate.py` |
| C1-M6 | Test-only: fix-cycle cap boundaries | `test_mb_team_state.py`: gate-routed fix at 4 → `fix A`, at 5 → `stop_human fix-cycles:A`; fixing track at 5 → `wait`, at 6 → stop. 5 passed (green on arrival; `>=`→`>` in `route_fix` would fail the 5 case) | `tests/pytest/test_mb_team_state.py` |
| C1-M7 | Test-only: AGR-097 lease | `test_mb_lock_resource.bats` "a waiter never takes an expired lease…": an expired lease with a live pid → `run --wait 1` exits 75, meta unchanged; `break` → 0, lock gone, `broke dead lock of L` on the board; a live lease → `break` exits 1. ok, and red when the `not meta.get("lease_until")` guard is mutated out (`[ "$status" -eq 75 ]` failed) | `tests/bats/test_mb_lock_resource.bats` |

Suites after fix cycle 1:
```
$ PYTHONPATH=. python3 -m pytest -q tests/pytest/test_mb_team_*.py tests/pytest/test_mb_lock_queue.py
276 passed, rc=0          (the router test is green again: Track D's mb.md change has settled)
$ bats tests/bats/test_mb_team_*.bats tests/bats/test_mb_lock_*.bats
1..111, ok 111, bats-rc=0
$ ruff check (changed .py): All checks passed · shellcheck scripts/mb-team-checkpoint.sh: clean
```

Minors and nits fixed along the way: C1-m19 (the liveness split). The others are untouched.

HANDOVER posted (outside my files): the new `scripts/mb_lock_liveness.py` needs a row in `references/scripts.md`,
or `tests/pytest/test_doc_counts.py::test_skill_md_script_table_lists_all_scripts` stays red (verified red). The exact
row is on the board. Optionally, add `mb_lock_liveness` to the installed-module list in `tests/e2e/test_install_uninstall.bats:545`.

STATUS: DONE_WITH_CONCERNS

## Fix cycle 2 (review C-review/cycle-2: C1-M1..M7 resolved, new C2-M1)

| id | Fix | Test (red → green) | Files |
|---|---|---|---|
| C2-M1 | `create` resolves realpath(--dir) and realpath(tree root). When --dir equals the root or contains it, it exits 2 with `--dir … contains the tree …` before writing anything. `chmod 700` and the `*` .gitignore apply only to a dir this call created or one strictly inside the tree; an existing dir outside the tree is left alone. The default `<bank>/backups/team` sits inside the tree and behaves as before | New bats tests "checkpoint dir equal to the tree root is refused and nothing is written" and "…an ancestor of the tree is refused…": both checked rc 2, the dir listing unchanged, the tree mode unchanged, `new.txt` still in `git status --porcelain`, and no root `.gitignore`. Before: `not ok 13/14 … refuse_dir failed`; after: ok | `scripts/mb-team-checkpoint.sh`, `tests/bats/test_mb_team_checkpoint.bats` |
| C2-n2 | The restore-hint test builds `W` under `$BATS_TEST_TMPDIR`, so bats cleans it up even when an assertion fails | ok | `tests/bats/test_mb_team_checkpoint.bats` |

```
$ bats tests/bats/test_mb_team_checkpoint.bats
before: not ok 2 checkpoint dir equal to the tree root … / not ok 3 … ancestor of the tree …   (`refuse_dir` failed)
after:  1..14, ok 1 … ok 14
$ bats tests/bats/test_mb_team_cli.bats tests/bats/test_mb_team_hardening.bats
1..19, ok 19, exit 0
$ shellcheck -x --source-path=SCRIPTDIR scripts/mb-team-checkpoint.sh: clean
```

STATUS: DONE

## Fix cycle 3 (review C-review/cycle-3: C2-M1 and C2-n2 resolved, new C3-M1)

| id | Fix | Test (red → green) | Files |
|---|---|---|---|
| C3-M1 | An existing --dir strictly inside the tree must hold only checkpoint artifacts: `.gitignore`, `*.diff`, `*-manifest.json`, `*-untracked.tar.gz`, `*.sha256`, `.<cid>.changed`, `.<cid>.untracked`. Anything else exits 2 with `--dir … is not a dedicated checkpoint dir`, before chmod, `.gitignore` or any write. A new dir and the default `backups/team` are unchanged | New bats test "an existing dir inside the tree that holds other work is refused as --dir" checks rc 2, no `.gitignore`, mode 755 kept, nothing written, `src/work.txt` still in `git status`. It failed before (`[ "$status" -eq 2 ]` failed) and passes now. The existing tests 11 and 12 (former :107 and :120) are unchanged and green | `scripts/mb-team-checkpoint.sh`, `tests/bats/test_mb_team_checkpoint.bats` |
| C3-n1 | `mkdir -p "$out" \|\| exit 2`, so a dangling-symlink --dir is a usage error | New test "a dangling symlink as --dir is a usage error (exit 2)": red (exit 1) → ok | same |
| C2-n1 | Blank-line layout fixed: `ruff --select E3 --preview` is clean on both files, and the state-test diff against HEAD is now only the new tests | — | `tests/pytest/test_mb_lock_queue.py`, `tests/pytest/test_mb_team_state.py` |

```
$ bats tests/bats/test_mb_team_checkpoint.bats -f "other work|dangling"
before: not ok 1 … refused as --dir ([ "$status" -eq 2 ] failed) · not ok 2 … dangling symlink … ([ "$status" -eq 2 ] failed)
$ bats tests/bats/test_mb_team_checkpoint.bats tests/bats/test_mb_team_cli.bats tests/bats/test_mb_team_hardening.bats
1..35, bats-rc=0 (checkpoint 16/16)
$ PYTHONPATH=. python3 -m pytest -q tests/pytest/test_mb_team_*.py tests/pytest/test_mb_lock_queue.py
276 passed, rc=0
$ shellcheck scripts/mb-team-checkpoint.sh: clean · ruff (incl. E3 preview) on changed tests: clean
```

STATUS: DONE

## Fix cycle 4 (review C-review/cycle-4: C3-M1, C3-n1 and C2-n1 resolved, new C4-M1)

C4-M1 is fixed at the root: ownership, not file names. The artifact-name allowlist is gone. `create` treats an existing
--dir as its own only when it carries `.mb-team-checkpoint` (a regular file: `-f` and `! -L`), when it is empty
(adopted, so the marker gets written), or when the caller passes `--adopt`. `mb_team_ops.py` passes `--adopt` only
when the resolved dir equals the default `<bank>/backups/team`. The script has no way to know the bank, so the
caller decides; a default dir created before this change keeps working. An owned dir gets `chmod 700`, a `*`
.gitignore (unless one exists) and the marker. Any other existing dir inside the tree exits 2 before anything is
written. A foreign existing dir outside the tree is left untouched; the self-exclusion filter matches nothing there.

| Case | Test | Before → after |
|---|---|---|
| user `fix.diff` / subdir `work.diff/` / symlink `link.diff` | 3 bats cases via `spoof_dir`: rc 2, the listing and mode 755 unchanged | not ok → ok |
| symlinked marker | "a symlinked marker does not make a dir ours" | ok before (the old allowlist refused it as well) and after; it pins `! -L` |
| empty existing dir adopted, marker written, mode 700, second call accepted | "an existing empty dir is adopted and gets the marker" | not ok → ok |
| marker-owned dir the VCS still lists (the filter case of old test 12) | "a marker-owned dir the VCS still lists is left out of the tar" | not ok → ok |
| default dir that predates the marker | `test_mb_team_cli.bats` "the default checkpoint dir is adopted even when it predates the ownership marker" (via `team checkpoint`) | not ok (rc 2) → ok |
| `--adopt` on a populated dir | "--adopt takes over an existing populated dir…" | not ok → ok |

**Behaviour change (orchestrator decision):** old test 12, a dir holding only a user `.gitignore`, was accepted
before and is now refused with exit 2 ("an existing dir holding only a user .gitignore is not ours and is
refused"). A dir with pre-marker checkpoint artifacts at a **non-default** path is also refused (probe p3); the
fix is to add `.mb-team-checkpoint` or use a new dir. One line in `commands/team.md` §7 states the rule.

The reviewer's probes (`scratchpad/c4r/run2.sh`): p1, an empty dir, gives rc 0; p2 to p13 all give rc 2 with
"not a dedicated checkpoint dir", spoofs p9 to p13 included.

```
$ bats tests/bats/test_mb_team_checkpoint.bats tests/bats/test_mb_team_cli.bats tests/bats/test_mb_team_hardening.bats
1..43, bats-rc=0 (checkpoint 23/23)
$ PYTHONPATH=. python3 -m pytest -q tests/pytest/test_mb_team_*.py tests/pytest/test_mb_lock_queue.py
276 passed, rc=0
$ shellcheck scripts/mb-team-checkpoint.sh: clean · ruff scripts/mb_team_ops.py: clean
```
Files: `scripts/mb-team-checkpoint.sh`, `scripts/mb_team_ops.py`, `commands/team.md`,
`tests/bats/test_mb_team_checkpoint.bats`, `tests/bats/test_mb_team_cli.bats`.

STATUS: DONE
