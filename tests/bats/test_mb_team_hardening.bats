#!/usr/bin/env bats
# mb-team.sh hardening: commit rollback, review ownership, gate JSON, checkpoint ids, host lock root (REQ-007..012).

load lib/team_fixture
bats_require_minimum_version 1.5.0

setup() { team_fixture_setup; SCRIPTS="$REPO/scripts"; }

@test "commit: a failing hook leaves the index as it was, foreign staging included" {
  team_two_tracks; team_fill_brief demo
  echo a2 >>"$PROJ/a/x.txt"; echo stray >"$PROJ/stray.txt"
  team_return A; team collect >/dev/null
  git -C "$PROJ" add stray.txt
  printf '#!/bin/sh\nexit 1\n' >"$PROJ/.git/hooks/pre-commit"; chmod +x "$PROJ/.git/hooks/pre-commit"
  before="$(git -C "$PROJ" diff --cached --name-only)"
  run team commit --tracks A -m "feat: a" --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"index restored"* ]] || false
  [ "$(git -C "$PROJ" diff --cached --name-only)" = "$before" ]
  git -C "$PROJ" status --short | grep -q '^ M a/x.txt'
}

@test "review owner: ** routes nested files, a single * stays in one segment, mirror prefix is stripped" {
  run python3 - "$SCRIPTS" "$PROJ" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from mb_team_review_core import Ctx
c = Ctx.__new__(Ctx)
c.team = {"tree": sys.argv[2], "mirror": "/mir/ror",
          "tracks": [{"id": "A", "files": ["src/**/*.py"]}, {"id": "B", "files": ["src/*.py"]}]}
assert c.owner({"file": "src/x.py"}) == "A", c.owner({"file": "src/x.py"})
assert c.owner({"file": "src/sub/y.py"}) == "A"
c.team["tracks"] = [{"id": "B", "files": ["src/*.py"]}]
assert c.owner({"file": "src/sub/y.py"}) is None
assert c.owner({"file": "/mir/ror/src/x.py"}) == "B"
assert c.owner({"file": sys.argv[2] + "/src/x.py"}) == "B"
PY
  [ "$status" -eq 0 ]
}

@test "review-gate: a gate printing no JSON exits 2 without a traceback and keeps reviews[]" {
  team_two_tracks; team_fill_brief demo
  cp -R "$SCRIPTS" "$BATS_TEST_TMPDIR/sc"
  printf '#!/bin/sh\necho not json\nexit 0\n' >"$BATS_TEST_TMPDIR/sc/mb-team-review.sh"
  run bash "$BATS_TEST_TMPDIR/sc/mb-team.sh" --mb "$BANK" review gate --cycle 1
  [ "$status" -eq 2 ]
  [[ "$output" != *Traceback* ]] || false
  run python3 -c "import json,sys; assert json.load(open(sys.argv[1]))['reviews']==[]" "$BANK/reports/demo/team.json"
  [ "$status" -eq 0 ]
}

@test "checkpoint: a label that is not a plain name exits 2" {
  team_two_tracks
  run team checkpoint '../x'
  [ "$status" -eq 2 ]
}

@test "checkpoint: a second checkpoint with the same id is refused and the first stays intact" {
  team_two_tracks
  mkdir -p "$BATS_TEST_TMPDIR/shim"
  printf '#!/bin/sh\necho 2026-01-01-000000\n' >"$BATS_TEST_TMPDIR/shim/date"; chmod +x "$BATS_TEST_TMPDIR/shim/date"
  export PATH="$BATS_TEST_TMPDIR/shim:$PATH"
  run team checkpoint same
  [ "$status" -eq 0 ]
  sum="$(cat "$PROJ/backups-out"/*.sha256)"
  run team checkpoint same
  [ "$status" -eq 1 ]
  [ "$(cat "$PROJ/backups-out"/*.sha256)" = "$sum" ]
  run bash "$SCRIPTS/mb-team-checkpoint.sh" verify --dir "$PROJ/backups-out" "$(basename "$PROJ/backups-out"/*.sha256 .sha256)"
  [ "$status" -eq 0 ]
}

@test "host lock root: the same under two TMPDIR values when MB_LOCK_DIR is unset" {
  a="$(env -u MB_LOCK_DIR TMPDIR=/var/tmp/one python3 -c "import sys; sys.path.insert(0,'$SCRIPTS'); import mb_team_config as c; print(c.host_lock_root())")"
  b="$(env -u MB_LOCK_DIR TMPDIR=/var/tmp/two python3 -c "import sys; sys.path.insert(0,'$SCRIPTS'); import mb_lock_resource as m, argparse; print(m.lock_root(argparse.Namespace(mb=''), 'host'))")"
  [ "$a" = "$b" ]
  [ "$a" = "/tmp/mb-locks-$(id -u)" ]
  [ "$(stat -f %Lp "$a" 2>/dev/null || stat -c %a "$a")" = 700 ]
}

@test "host resource from config: status lists it held under <host_lock_root> for any TMPDIR" {
  unset MB_LOCK_DIR
  res="gpu-$$-$RANDOM"
  printf 'team:\n  resources:\n    %s:\n      kind: mutex\n      scope: host\n' "$res" >"$BANK/pipeline.yaml"
  root="/tmp/mb-locks-$(id -u)"
  for t in one two; do
    tok="$(TMPDIR="$BATS_TEST_TMPDIR/tmp$t" bash "$REPO/scripts/mb-lock.sh" acquire "$res" --mb "$BANK" --owner t --lease 60)"
    out="$(TMPDIR="$BATS_TEST_TMPDIR/tmp$t" bash "$REPO/scripts/mb-lock.sh" status --mb "$BANK" --json)"
    [ -e "$root/$res.lock" ]
    TMPDIR="$BATS_TEST_TMPDIR/tmp$t" bash "$REPO/scripts/mb-lock.sh" release "$res" --mb "$BANK" --token "$tok"
    echo "$out" | grep -q "\"$res\""
  done
  rmdir "$root/$res.queue" 2>/dev/null || true
}
