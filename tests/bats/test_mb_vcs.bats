#!/usr/bin/env bats
# mb_vcs.sh seam (C6): git on a temp repo, arc through the PATH shim.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  VCS="$REPO_ROOT/scripts/mb_vcs.sh"
  T="$(mktemp -d)"; export T
  git -C "$T" init -q . && git -C "$T" config user.email t@t && git -C "$T" config user.name t
  echo a >"$T/a.txt"; printf 'ign.log\n' >"$T/.gitignore"
  git -C "$T" add -A && git -C "$T" commit -qm init
  echo b >>"$T/a.txt"; echo n >"$T/new.txt"; echo x >"$T/ign.log"
}
teardown() { rm -rf "$T"; }

@test "git: kind, root and head" {
  run "$VCS" kind --tree "$T"; [ "$status" -eq 0 ]; [ "$output" = git ]
  run "$VCS" root --tree "$T/"; [ "$status" -eq 0 ]; [ "$(cd "$output" && pwd -P)" = "$(cd "$T" && pwd -P)" ]
  run "$VCS" head --tree "$T"; [ "$output" = "$(git -C "$T" rev-parse HEAD)" ]
}

@test "git: diff and changed see tracked edits only" {
  run "$VCS" diff --tree "$T" HEAD; [[ "$output" == *"+b"* ]] || false; [[ "$output" != *new.txt* ]] || false
  run bash -c "'$VCS' changed --tree '$T' HEAD | tr '\\0' '\\n'"; [ "$output" = "a.txt" ]
}

@test "git: changed is NUL-separated, keeps non-ASCII and space paths raw, lists both sides of a rename" {
  mkdir -p "$T/docs"; echo v1 >"$T/docs/файл с пробелом.md"; echo o >"$T/old.txt"
  git -C "$T" add docs old.txt && git -C "$T" commit -qm more
  echo v2 >>"$T/docs/файл с пробелом.md"; git -C "$T" mv old.txt renamed.txt
  run bash -c "'$VCS' changed --tree '$T' HEAD | tr '\\0' '\\n' | sort"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'a.txt\ndocs/файл с пробелом.md\nold.txt\nrenamed.txt')" ]
}

@test "git: add and commit take both sides of a staged rename from changed" {
  echo o >"$T/old.txt"; git -C "$T" add -A && git -C "$T" commit -qm more
  git -C "$T" mv old.txt renamed.txt
  run "$VCS" add --tree "$T" -- old.txt renamed.txt
  [ "$status" -eq 0 ]
  run "$VCS" commit --tree "$T" -m mv -- old.txt renamed.txt
  [ "$status" -eq 0 ]
  [ "$(git -C "$T" show --name-status --format= HEAD | tr '\t' ' ')" = "R100 old.txt renamed.txt" ]
}

@test "git: untracked is NUL-separated and excludes ignored files" {
  run bash -c "'$VCS' untracked --tree '$T' | tr '\\0' '\\n'"
  [ "$output" = "new.txt" ]
}

@test "git: add and commit act on the given list" {
  "$VCS" add --tree "$T" -- a.txt
  run "$VCS" commit --tree "$T" -m two -- a.txt; [ "$status" -eq 0 ]
  [ "$(git -C "$T" log --format=%s -1)" = two ]
  [ -n "$(git -C "$T" ls-files --others --exclude-standard)" ]
}

# A foreign session staged new.txt; a path-scoped commit of a.txt leaves it staged and out of the commit.
scoped_commit_keeps_foreign_index() {
  git -C "$T" add new.txt
  "$VCS" add --tree "$T" -- a.txt
  run "$VCS" commit --tree "$T" -m scoped -- a.txt; [ "$status" -eq 0 ]
  [ "$(git -C "$T" show --name-only --format= HEAD)" = a.txt ]
  [ "$(git -C "$T" diff --cached --name-only)" = new.txt ]
}

@test "git: commit is path-scoped; a foreign staged file stays staged and out of the commit" {
  scoped_commit_keeps_foreign_index
}

@test "arc via shim: commit is path-scoped; a foreign staged file stays staged" {
  export PATH="$REPO_ROOT/tests/fixtures/arc-shim:$PATH" MB_VCS=arc
  scoped_commit_keeps_foreign_index
}

@test "commit without paths or without a message exits 2 and commits nothing" {
  git -C "$T" add a.txt
  run "$VCS" commit --tree "$T" -m nopaths; [ "$status" -eq 2 ]
  run "$VCS" commit --tree "$T" -m nopaths --; [ "$status" -eq 2 ]
  run "$VCS" commit --tree "$T" -- a.txt; [ "$status" -eq 2 ]
  [ "$(git -C "$T" log --format=%s -1)" = init ]
}

@test "show returns a file at a revision" {
  run "$VCS" show --tree "$T" HEAD:a.txt; [ "$output" = a ]
}

@test "directory outside any tree exits 2" {
  O="$(mktemp -d)"
  run env PATH="$REPO_ROOT/tests/fixtures/arc-shim:$PATH" "$VCS" kind --tree "$O"
  rm -rf "$O"; [ "$status" -eq 2 ]
}

@test "unknown op exits 2" {
  run "$VCS" push --tree "$T"; [ "$status" -eq 2 ]
}

@test "arc via shim: same answers as git" {
  export PATH="$REPO_ROOT/tests/fixtures/arc-shim:$PATH" MB_VCS=arc
  run "$VCS" kind --tree "$T"; [ "$output" = arc ]
  run "$VCS" diff --tree "$T" HEAD; [[ "$output" == *"+b"* ]] || false
  run bash -c "'$VCS' changed --tree '$T' HEAD | tr '\\0' '\\n'"; [ "$output" = "a.txt" ]
  run bash -c "'$VCS' untracked --tree '$T' | tr '\\0' '\\n'"; [ "$output" = "new.txt" ]
}

@test "arc: real binary answers root and head when a mount exists" {
  command -v arc >/dev/null || skip "no arc"
  A="$(ls -d "$HOME"/arcadia3 2>/dev/null | head -1)"; [ -n "$A" ] || skip "no arc mount"
  run env MB_VCS=arc "$VCS" head --tree "$A"; [ "$status" -eq 0 ]; [[ "$output" =~ ^[0-9a-f]{40}$ ]]
}
