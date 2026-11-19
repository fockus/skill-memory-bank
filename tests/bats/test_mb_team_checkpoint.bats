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
  run bash -c "grep -hnE '(^|[^a-z_])push([^a-z_]|\$)' \"$REPO_ROOT/scripts/mb-team-checkpoint.sh\" \"$REPO_ROOT/scripts/mb_vcs.sh\" \"$REPO_ROOT/scripts/mb_team_ops.py\" | grep -v -e '^[0-9]*:#' -e '[Nn]o push'"
  [ "$status" -eq 1 ]
}

@test "label with a path separator is refused and nothing is written" {
  run "$CP" create --tree "$T" --baseline HEAD --topic demo --dir "$D/out" --label ../x
  [ "$status" -eq 2 ]
  [ ! -e "$D/out" ]
  [ -z "$(ls -A "$D")" ]
}

@test "second checkpoint with the same id is refused and the first stays intact" {
  S="$(mktemp -d)"; printf '#!/bin/sh\necho 2026-11-18-120000\n' >"$S/date"; chmod +x "$S/date"
  PATH="$S:$PATH" mk >/dev/null; id="$(basename "$(ls "$D"/*-demo-s1.diff)" .diff)"
  sum="$(cat "$D/$id.sha256")"; echo c >>"$T/a.txt"
  run env PATH="$S:$PATH" "$CP" create --tree "$T" --baseline HEAD --topic demo --dir "$D" --label s1
  rm -rf "$S"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]] || false
  [ "$(cat "$D/$id.sha256")" = "$sum" ]
  run "$CP" verify --dir "$D" "$id"; [ "$status" -eq 0 ]
}

@test "restore hint is a runnable command for paths with spaces" {
  W="$BATS_TEST_TMPDIR/w"; mkdir -p "$W"; TS="$W/tree with space"; DS="$W/cp dir"; mv "$T" "$TS"; T="$TS"
  run "$CP" create --tree "$T" --baseline HEAD --topic demo --dir "$DS" --label s1
  [ "$status" -eq 0 ]
  cmd="$(printf '%s\n' "$output" | sed -n 's/^restore: //p')"; [ -n "$cmd" ]
  git -C "$T" checkout -q -- . && git -C "$T" clean -fdq
  [ "$(cat "$T/a.txt")" = a ]
  [ ! -e "$T/new.txt" ]
  eval "$cmd"
  [ "$(cat "$T/a.txt")" = "$(printf 'a\nb')" ]
  [ "$(cat "$T/new.txt")" = n ]
}

@test "checkpoint dir inside the tree is private, git-ignored and never tars itself" {
  O="$T/backups/team"
  "$CP" create --tree "$T" --baseline HEAD --topic demo --dir "$O" --label one --max-untracked-mb 1 >/dev/null
  "$CP" create --tree "$T" --baseline HEAD --topic demo --dir "$O" --label two --max-untracked-mb 1 >/dev/null
  [ "$(stat -c %a "$O" 2>/dev/null || stat -f %Lp "$O")" = 700 ]
  run git -C "$T" status --porcelain --untracked-files=all
  [[ "$output" != *backups* ]] || false
  second="$(ls "$O"/*-demo-two-untracked.tar.gz)"
  run python3 -c "import sys,tarfile; print('\n'.join(sorted(tarfile.open(sys.argv[1]).getnames())))" "$second"
  [ "$status" -eq 0 ]
  [ "$output" = "new.txt" ]
}

@test "an existing dir holding only a user .gitignore is not ours and is refused" {
  O="$T/backups/team"; mkdir -p "$O"; : >"$O/.gitignore"
  run "$CP" create --tree "$T" --baseline HEAD --topic demo --dir "$O" --label one
  [ "$status" -eq 2 ]
  [ "$(ls -A "$O")" = .gitignore ]
}

@test "a marker-owned dir the VCS still lists is left out of the tar" {
  O="$T/backups/team"; mkdir -p "$O"; : >"$O/.gitignore"; : >"$O/.mb-team-checkpoint"
  "$CP" create --tree "$T" --baseline HEAD --topic demo --dir "$O" --label one --max-untracked-mb 1 >/dev/null
  "$CP" create --tree "$T" --baseline HEAD --topic demo --dir "$O" --label two --max-untracked-mb 1 >/dev/null
  run git -C "$T" status --porcelain --untracked-files=all
  [[ "$output" == *backups/team/.gitignore* ]] || false
  second="$(ls "$O"/*-demo-two-untracked.tar.gz)"
  run python3 -c "import sys,tarfile; print('\n'.join(sorted(tarfile.open(sys.argv[1]).getnames())))" "$second"
  [ "$status" -eq 0 ]
  [ "$output" = "new.txt" ]
}

# spoof_dir <setup> — an existing dir inside the tree, populated by <setup>, is refused with nothing written.
spoof_dir() {
  local O="$T/d" before mode; mkdir -p "$O"; chmod 755 "$O"; (cd "$O" && eval "$1")
  before="$(ls -A "$O")"
  run "$CP" create --tree "$T" --baseline HEAD --topic demo --dir "$O" --label s1
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a dedicated checkpoint dir"* ]] || false
  [ "$(ls -A "$O")" = "$before" ]
  [ "$(stat -c %a "$O" 2>/dev/null || stat -f %Lp "$O")" = 755 ]
}

@test "a user file named like an artifact (fix.diff) does not make a dir ours" { spoof_dir 'echo patch >fix.diff'; }
@test "a subdir named like an artifact (work.diff/) does not make a dir ours" { spoof_dir 'mkdir work.diff; echo u >work.diff/a.md'; }
@test "a symlink named like an artifact (link.diff) does not make a dir ours" { spoof_dir 'ln -s ../a.txt link.diff'; }
@test "a symlinked marker does not make a dir ours" { spoof_dir 'echo x >real; ln -s real .mb-team-checkpoint'; }

@test "an existing empty dir is adopted and gets the marker" {
  O="$T/d"; mkdir -p "$O"
  run "$CP" create --tree "$T" --baseline HEAD --topic demo --dir "$O" --label s1
  [ "$status" -eq 0 ]
  [ -f "$O/.mb-team-checkpoint" ]
  [ ! -L "$O/.mb-team-checkpoint" ]
  [ "$(stat -c %a "$O" 2>/dev/null || stat -f %Lp "$O")" = 700 ]
  run "$CP" create --tree "$T" --baseline HEAD --topic demo --dir "$O" --label s2
  [ "$status" -eq 0 ]
}

@test "--adopt takes over an existing populated dir (the default backups/team) and marks it" {
  O="$T/backups/team"; mkdir -p "$O"; echo old >"$O/2026-01-01-000000-demo-old.diff"
  run "$CP" create --tree "$T" --baseline HEAD --topic demo --dir "$O" --label s1 --adopt
  [ "$status" -eq 0 ]
  [ -f "$O/.mb-team-checkpoint" ]
  [ -f "$O/.gitignore" ]
}

# refuse_dir <dir> — create must exit 2, write nothing and leave the tree's untracked files visible to git.
refuse_dir() {
  local before mode; before="$(ls -A "$1")"; mode="$(stat -c %a "$T" 2>/dev/null || stat -f %Lp "$T")"
  run "$CP" create --tree "$T" --baseline HEAD --topic demo --dir "$1" --label s1
  [ "$status" -eq 2 ]
  [[ "$output" == *"contains the tree"* ]] || false
  [ "$(ls -A "$1")" = "$before" ]
  [ "$(stat -c %a "$T" 2>/dev/null || stat -f %Lp "$T")" = "$mode" ]
  run git -C "$T" status --porcelain --untracked-files=all
  [[ "$output" == *"new.txt"* ]] || false
}

@test "checkpoint dir equal to the tree root is refused and nothing is written" {
  W="$BATS_TEST_TMPDIR/w"; mkdir -p "$W"; mv "$T" "$W/tree"; T="$W/tree"; rm -f "$T/.gitignore"
  refuse_dir "$T"
  [ ! -e "$T/.gitignore" ]
}

@test "checkpoint dir that is an ancestor of the tree is refused and nothing is written" {
  W="$BATS_TEST_TMPDIR/w"; mkdir -p "$W"; mv "$T" "$W/tree"; T="$W/tree"
  refuse_dir "$W"
}

@test "an existing dir inside the tree that holds other work is refused as --dir" {
  mkdir -p "$T/src"; echo t >"$T/src/kept.txt"; git -C "$T" add src/kept.txt; git -C "$T" commit -qm src
  echo w >"$T/src/work.txt"; chmod 755 "$T/src"
  run "$CP" create --tree "$T" --baseline HEAD --topic demo --dir "$T/src" --label s1
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a dedicated checkpoint dir"* ]] || false
  [ ! -e "$T/src/.gitignore" ]
  [ "$(stat -c %a "$T/src" 2>/dev/null || stat -f %Lp "$T/src")" = 755 ]
  [ -z "$(ls "$T/src" | grep -v -e '^kept.txt$' -e '^work.txt$')" ]
  run git -C "$T" status --porcelain --untracked-files=all
  [[ "$output" == *"src/work.txt"* ]] || false
}

@test "a dangling symlink as --dir is a usage error (exit 2)" {
  ln -s "$D/missing/deeper" "$D/link"
  run "$CP" create --tree "$T" --baseline HEAD --topic demo --dir "$D/link" --label s1
  [ "$status" -eq 2 ]
}
