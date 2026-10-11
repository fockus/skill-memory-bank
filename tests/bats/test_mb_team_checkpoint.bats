#!/usr/bin/env bats
# mb-team-checkpoint.sh: create / verify checkpoints (design §7).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CP="$REPO_ROOT/scripts/mb-team-checkpoint.sh"
  T="$(mktemp -d)"; D="$(mktemp -d)"
  git -C "$T" init -q . && git -C "$T" config user.email t@t && git -C "$T" config user.name t
  echo a >"$T/a.txt"; printf 'ign.log\n' >"$T/.gitignore"
  git -C "$T" add -A && git -C "$T" commit -qm init
  echo b >>"$T/a.txt"; echo n >"$T/new.txt"; echo x >"$T/ign.log"
  head -c 2097152 /dev/zero >"$T/big.bin"
}
teardown() { rm -rf "$T" "$D"; }

mk() { "$CP" create --tree "$T" --baseline HEAD --topic demo --dir "$D" --label s1 "$@"; }

@test "create writes diff, tar, manifest and sha256; verify passes" {
  run mk; [ "$status" -eq 0 ]
  ls "$D"/*-demo-s1.diff "$D"/*-demo-s1-untracked.tar.gz "$D"/*-demo-s1-manifest.json "$D"/*-demo-s1.sha256 >/dev/null
  id="$(basename "$(ls "$D"/*-demo-s1.diff)" .diff)"
  run "$CP" verify --dir "$D" "$id"; [ "$status" -eq 0 ]
}

@test "verify fails after one byte of the tar changes" {
  mk >/dev/null; id="$(basename "$(ls "$D"/*-demo-s1.diff)" .diff)"
  printf 'Z' | dd of="$D/$id-untracked.tar.gz" bs=1 seek=20 conv=notrunc 2>/dev/null
  run "$CP" verify --dir "$D" "$id"; [ "$status" -eq 1 ]
}

@test "untracked file over the cap is skipped and listed; ignored never enters the tar" {
  run mk --max-untracked-mb 1; [ "$status" -eq 0 ]
  id="$(basename "$(ls "$D"/*-demo-s1.diff)" .diff)"
  run python3 -c "
import json,sys,tarfile
m=json.load(open('$D/$id-manifest.json'))
assert [s['path'] for s in m['skipped_large']]==['big.bin'], m['skipped_large']
assert 'reason' in m['skipped_large'][0]
n=tarfile.open('$D/$id-untracked.tar.gz').getnames()
assert sorted(n)==['new.txt'], n
for k in ('tree','vcs','head','baseline','files','sizes','skipped_large'): assert k in m,k
"
  [ "$status" -eq 0 ]
}

@test "tar restores untracked files (verification unpack)" {
  mk --max-untracked-mb 1 >/dev/null; id="$(basename "$(ls "$D"/*-demo-s1.diff)" .diff)"
  R="$(mktemp -d)"; tar -xzf "$D/$id-untracked.tar.gz" -C "$R"
  [ "$(cat "$R/new.txt")" = n ]; rm -rf "$R"
}

@test "arc shim produces the same manifest fields" {
  export PATH="$REPO_ROOT/tests/fixtures/arc-shim:$PATH" MB_VCS=arc
  run mk --max-untracked-mb 1; [ "$status" -eq 0 ]
  id="$(basename "$(ls "$D"/*-demo-s1.diff)" .diff)"
  run python3 -c "
import json
m=json.load(open('$D/$id-manifest.json')); assert m['vcs']=='arc'
for k in ('tree','vcs','head','baseline','files','sizes','skipped_large'): assert k in m,k
"
  [ "$status" -eq 0 ]
}

@test "directory outside any tree exits 2" {
  O="$(mktemp -d)"
  run env PATH="$REPO_ROOT/tests/fixtures/arc-shim:$PATH" "$CP" create --tree "$O" --baseline HEAD --topic demo --dir "$D"
  rm -rf "$O"; [ "$status" -eq 2 ]
}

@test "no push anywhere in the scripts" {
  ! grep -nE '(^|[^a-z_])push([^a-z_]|$)' "$REPO_ROOT/scripts/mb-team-checkpoint.sh" | grep -v '^[0-9]*:#'
}
