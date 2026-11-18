# Upgrade debug: OpenCode step fails on upgrade (2026-11-19)

STATUS: DONE_WITH_CONCERNS

The two observed failures are independent:

| # | Symptom | Root cause | Product bug? | Real users |
|---|---------|------------|--------------|------------|
| 1 | first install exits 1: `[opencode-io] [Errno 1] Operation not permitted: .../before-0`, "mb-rules: OpenCode rule rewrite failed" | `adapters/opencode_install_io.py:109` (HEAD) `os.chown(image, uid, gid)` copies the original file's group onto the rollback copy. An unprivileged user cannot set a group they are not a member of. | yes, fixed | rare: only when a managed OpenCode file has a group the user is not in (HOME under `/tmp` on macOS, setgid/shared dirs, files chgrp'd by an admin) |
| 2 | upgrade exits 1: `[opencode-io] manifest HOME does not match current HOME` | harness artefact: the upgrade ran `install.sh` from the real checkout, whose co-located `.installed-manifest.json` belongs to `HOME=/Users/fockus` and records `opencode`. `install.sh:903-909` sets aside another HOME's manifest only when it has no OpenCode state. Otherwise the probe (`adapters/_framework.sh:121` -> `opencode_install_io.py:66` -> `opencode_files.py:294-295`) refuses, as 5d6116f intended. | no (by design) | no; a same-HOME upgrade is green |

## Q1: why the recovery dir is under /var/folders despite TMPDIR

`adapters/_framework.sh:113` runs `mktemp -d` with no template. On this Darwin 25, `/usr/bin/mktemp` uses `_CS_DARWIN_USER_TEMP_DIR` first and treats TMPDIR only as a fallback (man mktemp: "Fallback locations if _CS_DARWIN_USER_TEMP_DIR is not available are TMPDIR ..."). Evidence:

```
$ TMPDIR=$S/tmp bash -c 'echo $TMPDIR; mktemp -d; python3 -c "import tempfile;print(tempfile.gettempdir())"'
.../upgdbg/tmp
/var/folders/vj/d87hwmp15j1flcqptvqxymhr0000gp/T/tmp.kvq2LyHBRd   <- mktemp ignores TMPDIR
.../upgdbg/tmp                                                    <- python honours it
```

Nothing in install.sh sanitises TMPDIR or uses `env -i`. The location also did not cause the failure: this sandbox can write to `/var/folders` (touch, cp and `shutil.copy2` all succeed). Only `os.chown(file, uid, 0)` fails:

```
copy2-ok / chown(uid,20 staff)-ok / chown(uid,0 wheel): PermissionError [Errno 1]
```

## Root cause of (1)

- macOS gives a new file the group of its parent directory (BSD semantics). `/private/tmp` is `root:wheel`, so every file in the temp HOME is group `wheel`. Evidence: `stat -f %Sg $S/upg2/home/.config/opencode/AGENTS.md` -> `wheel`. The user's groups (`id`) do not include wheel(0).
- `prepare()` copies the preimage into the recovery dir. The copy gets group `staff` from `/var/folders/.../T`. `os.chown(image, before[3], before[4])` then tries to set `wheel`, and the kernel returns EPERM. `chown` to an unchanged non-member group succeeds; changing to one fails, which I confirmed by hand.
- The forward writer `opencode_files.write` (mkstemp in the target dir + `os.replace`) never preserves the group either. The rollback copy was held to a stricter rule than the install itself.

Clean A/B, with the same snapshot of the working tree and the same wheel-group HOME:
- fix reverted (HEAD `opencode_install_io.py`): `E2 control(unfixed) rc=1`, the same `[Errno 1] ... before-0` / "OpenCode rule rewrite failed" lines.
- fix applied: `E fresh-fixed rc=0`, no opencode-io lines. The rewritten `AGENTS.md` stays group `wheel`.

## Root cause of (2) and whether it depends on (1)

Scenario B: the first install from the HEAD archive succeeds (HOME chgrp'd to staff, so (1) does not fire, `i1 rc=0`). The upgrade from `/Users/fockus/Apps/skill-memory-bank` still fails:

```
i2 rc=1
[opencode-io] manifest HOME does not match current HOME; recovery: /var/folders/.../tmp.v7GgNRuwjz
```

HOME values:
- recorded: `jq .home /Users/fockus/Apps/skill-memory-bank/.installed-manifest.json` -> `/Users/fockus`, clients `[codex, opencode, pi, cursor]`.
- seen by Python: `$S/.../B/home`. Nothing strips HOME; the caller passes it unchanged. The first install's own manifest (home = temp HOME) lives in `$S/head/.installed-manifest.json` (`mb_resolve_manifest_path`, `scripts/_lib.sh:864`), so the upgrade from a different source dir never sees it ("no previous install manifest — options inferred ...").

So (2) does not depend on (1). It comes from using the real checkout as the upgrade source under a foreign HOME. It does not come from 44def21; 5d6116f deliberately keeps refusing when the other-HOME record has OpenCode state.

Real user upgrade (scenario C): install from a checkout at HEAD, overlay the working tree onto the same checkout (rsync, keeping the manifest), and re-install with the same HOME. Result: `i2 rc=0`, no opencode-io/preserved lines, installed VERSION = source VERSION, and the alias points at the upgraded checkout. Not affected.

## Fix (1): applied, minimal

`adapters/opencode_install_io.py` `prepare()`. If `chown` raises PermissionError and the file is ours (`before[3] == geteuid()`), keep the copy's own group. The race check then compares mode/uid/mtime/digest against `before` and the group against the copy's actual group. A foreign-owned file still raises. The symlink (hard-link) branch is unchanged. On rollback the restored file has the recovery dir's group; that matches what the forward writer already does.

Test (RED before the fix, then GREEN):
`tests/pytest/test_opencode_install_io.py::test_prepare_with_unsettable_group_retains_preimage_and_rolls_back`.
It emulates the kernel EPERM on `os.chown`, then runs prepare -> mutate -> mark -> abort and asserts the original bytes are restored and nothing is left pending.

```
RED : tests/pytest/test_opencode_install_io.py:30: in refuse  E PermissionError: [Errno 1] Operation not permitted   (raised from prepare)
GREEN: Pytest: 1 passed in 0.44s
ruff check adapters/opencode_install_io.py tests/pytest/test_opencode_install_io.py -> No issues found
mb-test-run.sh --files ... -> {"tests_pass":true,"tests_total":1,...}
pytest test_opencode_legacy_ownership/selective_install/resources -> 100 passed
bats test_opencode_install_durability.bats test_install_upgrade_safe.bats -> rc=0, 1..34, 34 ok, 0 not ok
```

The full suite was not run (it belongs to `/mb verify` / pre-commit). Nothing was committed or staged.

## Concerns / follow-ups (not fixed)

1. Low: the `[opencode-io] manifest HOME does not match current HOME; recovery: <dir>` message names neither the manifest path nor the way out (`MB_MANIFEST_PATH=<fresh path>`). Its "recovery:" suffix points at an empty dir that holds no recovery material. Better wording would save the next person this investigation.
2. Low: after a failed install, HEAD leaves `incomplete recovery retained` dirs in the system temp dir (`/var/folders/.../T/tmp.*`). They are execution-scoped and never reused.
3. Low, test hygiene: harnesses that install under a temp HOME must not use the real checkout as the source. Use a `git archive` snapshot or `MB_MANIFEST_PATH`, otherwise they hit (2).
4. Info: on macOS, `mktemp -d` without `-p` ignores TMPDIR. Scripts that need TMPDIR honoured (sandboxes) should pass `-p "${TMPDIR:-/tmp}"`. This is not needed for this bug.

Scratch evidence (logs): `/private/tmp/claude-502/-Users-fockus-Apps-skill-memory-bank/dc795ad2-23d2-4e73-bc4c-6c49e807e25c/scratchpad/upgdbg/{B,C,E,E2}/i*.log`, `.../upgdbg/bats-full.out`.
