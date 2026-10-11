# Track D (T-VCS) report

STATUS: DONE

## Files
- scripts/mb_vcs.sh (seam C6: kind root head diff changed untracked add commit show; no push/rebase/reset path; exit 2 outside a tree or on unknown op)
- scripts/mb-team-checkpoint.sh (create / verify; hashlib sha256 via python3; restore commands printed only)
- tests/bats/test_mb_vcs.bats (9 tests), tests/bats/test_mb_team_checkpoint.bats (7 tests)
- tests/fixtures/arc-shim/arc (git-backed shim of the probed arc subset)

## Red -> green
Checkpoint tests before the script existed: all failed (BW01 exit 127 "Command not found").
After: `bats tests/bats/test_mb_vcs.bats tests/bats/test_mb_team_checkpoint.bats` -> 16/16 ok
(git fixture, shim arc, 2 MiB file with cap 1 MiB -> skipped_large + absent from tar, ignored file absent,
one-byte tar corruption -> verify exit 1, unpack-and-compare restore, outside tree -> exit 2). shellcheck -x: clean.

## Real arc probes (read-only, ~/arcadia3 and ~/arcadia-int; mounts ~/arcadia, arcadia2 are unmounted)
- `arc root` -> /Users/anton-one/arcadia-int
- `arc rev-parse HEAD` -> 40-hex (a24e0fb3...)
- `arc status --short -u all` -> lines ` M path`, ` D path`, `?? path` (untracked; clean tree prints nothing)
- `arc diff --git --binary HEAD` -> git-format diff; `arc diff --name-only HEAD` -> paths
- `arc show HEAD:<path>` works
- `arc ls-files -o` lists ignored files too (.ruff_cache), has no --exclude-standard, so the seam uses
  `arc status --short -u all` for untracked (matches C6).
- Full end-to-end: checkpoint create+verify with the real arc on arcadia-int: vcs=arc, 187 tracked changes, 79 untracked, verify exit 0.
- add/commit for arc are mapped (`arc add`, `arc commit -m`) but NOT executed against the real arc (forbidden); shimmed only.

## Notes / left
- Manifest fields: id, tree, vcs, head, baseline, tracked_changed, files, sizes, diff_bytes, skipped_large[{path,size,reason}]; .sha256 covers diff, tar, manifest.
- `checkpoint.extra` and reading `team.checkpoint.dir` from config are the dispatcher's job (Stage 8); this script takes explicit flags.
- Arc paths with spaces/quotes in `status --short` are not unquoted (ceiling).
- The shim treats arc as git underneath, so shim tests cover the seam logic, not arc output drift; the real-arc bats test skips when no mount.
