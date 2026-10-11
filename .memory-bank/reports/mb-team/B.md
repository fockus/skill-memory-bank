STATUS: DONE_WITH_CONCERNS

# Track B — Stage 2 T-LOCK: `mb-lock.sh` with a fair queue

## Files

- `scripts/mb-lock.sh` (new, 224 lines): the CLI. Handles signals, the child process, the stop watchdog, maintenance under the lock and board posts (real `mb-coord.sh`, fail-open).
- `scripts/mb_lock_queue.py` (new, 297 lines): ticket queue, liveness (pid + `ps -o lstart=`), lock take and remove, `wait` with AGR-097 reclaim, C4 status.
- `scripts/mb_lock_resource.py` (new, 133 lines, **not in the plan's Files line**): loads C3 from `--resource-json` or `mb_team_config.py resource`, resolves the path from `scope`, evaluates preconditions and the stop threshold (`df -Pk` parsed in Python, check command), renders holder and status text.
- `tests/bats/test_mb_lock_resource.bats` (new, 14 cases).
- `tests/pytest/test_mb_lock_queue.py` (new, 12 cases).

Commands: `run | acquire | release | maint | status | watch | break`. Exit codes: 0 or the child's status · 1 refused or corrupt · 2 usage or config · 75 wait timeout · 76 stop condition · 77 preconditions unmet.

## How it works (short)

- The lock is `P.lock/meta.json`. To take it, the waiter renames a prepared directory onto `P.lock`; the rename is atomic and the meta file is always there.
- Each waiter gets a ticket `P.queue/<seq>`. The ticket is published with `link(2)`, which fails if that seq already exists. The lowest live seq goes next. This needs no mutex and no `flock`.
- Liveness: the pid exists (EPERM counts as alive) and its `lstart` matches the recorded start time. On another host a holder is always treated as alive.
- AGR-097: the queue head reclaims a `run` holder only when the wrapper and the child are both dead, the host matches, and pid + start time match the record. It posts `STATUS · <track>: resource <res>: reclaimed dead lock of …`. A live holder is never removed. A lease (`acquire --lease`) never expires on its own; only `break` removes it.
- The child records its own pid in meta (`setchild`) before `exec`, so the command never runs unrecorded. If the wrapper gets SIGKILL, the child keeps the lock.

## Tests: before (Red) → after (Green)

Before (new tests, no implementation yet):
```
$ bats tests/bats/test_mb_lock_resource.bats
not ok 1 lock: three queued waiters acquire in ticket order (10 runs)
not ok 2 lock: a waiter cancelled with TERM or KILL leaves no ticket and frees its place
… (all 14 not ok)
$ .venv/bin/pytest -q tests/pytest/test_mb_lock_queue.py
ERROR tests/pytest/test_mb_lock_queue.py - FileNotFoundError: [Errno 2] No su...
1 error in 0.12s
```

After:
```
$ bats tests/bats/test_mb_lock_resource.bats
1..14
ok 1 lock: three queued waiters acquire in ticket order (10 runs)
ok 2 lock: a waiter cancelled with TERM or KILL leaves no ticket and frees its place
ok 3 lock: a ticket of a dead process is skipped
ok 4 lock: a live holder is never removed by run, acquire or break
ok 5 lock: SIGKILLed wrapper keeps the lock while its child runs; the queue head reclaims it after
ok 6 lock: a recorded pid reused by another process counts as dead
ok 7 lock: break removes a dead holder and posts a board entry
ok 8 lock: exit 77 when preconditions still fail after maintenance; the command is not run
ok 9 lock: maintenance that restores the preconditions lets the command run
ok 10 lock: free disk below the start threshold exits 77 (real df)
ok 11 lock: stop condition mid-run terminates the child, posts BLOCKED, exits 76
ok 12 lock: maintenance and release refuse a caller that does not hold the lock
ok 13 lock: watch posts edge-triggered board entries when a precondition turns false and recovers
ok 14 lock: usage errors exit 2
(whole file ≈ 50 s; FIFO case alone: 16 s for 10 runs)

$ .venv/bin/pytest -q tests/pytest/test_mb_lock_queue.py
12 passed in 0.79s

$ ruff check scripts/mb_lock_queue.py scripts/mb_lock_resource.py tests/pytest/test_mb_lock_queue.py
All checks passed!
$ shellcheck -x scripts/mb-lock.sh        # no output = clean
```

Live check against T-CFG's `mb_team_config.py` (no `--resource-json`): `run build` → `free 20.5 GiB`, `acquired`, child status 0; `status --json` matches C4; an unknown resource → exit 2 with the config error.

## DoD

- [x] Three background waiters get the lock in ticket order in 10 of 10 runs; 16 s, under 60 s.
- [x] A waiter killed while queued (TERM and KILL) leaves no ticket. A dead ticket is skipped. If the wrapper gets SIGKILL while its child runs, the lock stays until the child exits.
- [x] `run`, `acquire` and `break` never remove a lock held by another live process. `break` on a dead holder posts a board entry.
- [x] Exit 77 when preconditions still fail after maintenance (the command is not run). Exit 76 and the child terminated when the stop check trips mid-run. Exit 75 when `--wait` expires.
- [x] Maintenance never runs for a foreign token (`maint` with a foreign token → 1, nothing runs).
- [x] `status --json` matches C4 (pytest schema check). Free disk is parsed from `df -Pk` fixtures for macOS, Linux and a filesystem/mount with spaces.
- [x] bats and pytest green; shellcheck and ruff clean; every file under 300 lines.

## Deviations from the plan and design (orchestrator decision)

1. **Third file `scripts/mb_lock_resource.py`.** With everything in one module, `mb_lock_queue.py` came to about 400 lines, against the 300-line DoD. The split follows responsibility: queue and liveness in one module, resource config and conditions in the other. **Stage 11 T-WIRE and the plan's Files line** need to include it (installer manifest).
2. **No `.seq` and `.qmutex`, no reuse of `mb_lock_acquire`.** `link(2)` gives a unique seq without a mutex, and order is preserved: a ticket created after another one's creation always gets a higher number. Ticket file name is `<seq>` (12 digits); the pid is inside the JSON, not `<seq>-<pid>`. `mb_pid_alive` is not reused either: liveness with start time lives in Python. `_lib.sh` is unchanged.
3. **Board assertions use a real fixture bank and the real `mb-coord.sh`**, not a PATH shim. This is an integration test and needs no env override in the code.
4. **`stop_threshold.check`:** a non-zero exit means the stop condition is breached (same polarity as `preconditions.check`: exit 0 = ok). C3 does not spell this out.
5. **`break` also removes an expired lease and an unreadable meta.** That is the orchestrator's explicit decision; automatic reclaim covers only a dead `run` holder.
6. **`status` without a name** scans `${MB_LOCK_DIR:-$TMPDIR/mb-locks}` and `<bank>/.locks/res`, because C3 has no "list of resources" operation. Preconditions are not computed in that mode (no config). With a name, everything is computed.
7. A condition block counts only if it has a threshold or a check: `mb_team_config.py` emits `stop_threshold` with null fields.

## Concerns

- **Low.** `remove()` has an ABA corner case. If `break` races the queue head, it can move a fresh lock aside; the code puts it back, and logs if the restore fails. Marked `ponytail:`. If this is ever observed, the fix is a generation counter.
- **Low.** Bats quirk seen while debugging: when an `eval` inside `until` fails, bats remembers that line, so a later failure is reported at the wrong place. Tests are not affected; it only makes debugging harder.
- **Info.** This machine has 20.5 GiB free on `/`. Typical presets (25 GiB) will trigger maintenance.

## Remaining

Nothing in scope. For the next stages: T-WIRE adds `mb_lock_resource.py` to the manifest, and T-DOCS adds the `mb-lock.sh` row to `references/scripts.md`.
