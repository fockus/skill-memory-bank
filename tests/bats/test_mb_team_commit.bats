#!/usr/bin/env bats
# mb-team.sh commit — scoped staging of finished tracks, y/N, COMMIT entry, no push (design §7, REQ-TEAM-063..065).
# shellcheck disable=SC2016  # single-quoted bash -c bodies take positional args on purpose

load lib/team_fixture
bats_require_minimum_version 1.5.0

setup() {
  team_fixture_setup
  # PATH shim: logs every git call, then runs the real git.
  REAL_GIT="$(command -v git)"
  SHIM="$BATS_TEST_TMPDIR/shim"; GITLOG="$BATS_TEST_TMPDIR/git.log"
  mkdir -p "$SHIM"
  printf '#!/bin/sh\necho "$*" >>"%s"\nexec "%s" "$@"\n' "$GITLOG" "$REAL_GIT" >"$SHIM/git"
  chmod +x "$SHIM/git"
}

head_subject() { git -C "$PROJ" log --format=%s -1; }

@test "commit: stages only owned changed files, lists foreign ones, writes COMMIT, never pushes" {
  team_two_tracks; team_fill_brief demo
  echo a2 >>"$PROJ/a/x.txt"; echo b2 >>"$PROJ/b/y.txt"; echo stray >"$PROJ/stray.txt"
  team_return A; team_return B; team collect >/dev/null
  git -C "$PROJ" add stray.txt  # a parallel session staged it
  run env PATH="$SHIM:$PATH" bash -c 'cd "$1" && bash "$2" --mb "$3" commit --tracks A -m "feat: a" --yes' _ "$PROJ" "$TEAM" "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"foreign"*"b/y.txt"* ]] || false
  [[ "$output" == *"stray.txt"* ]] || false
  [ "$(git -C "$PROJ" show --name-only --format= HEAD)" = "a/x.txt" ]
  [ "$(head_subject)" = "feat: a" ]
  git -C "$PROJ" status --short | grep -q '^ M b/y.txt'
  [ "$(git -C "$PROJ" diff --cached --name-only)" = stray.txt ]
  grep -q '^## COMMIT · .* · team demo: [0-9a-f]\{8\} A$' "$BANK/COORDINATION.md"
  grep -q '^- a/x.txt$' "$BANK/COORDINATION.md"
  run ! grep -q push "$GITLOG"
  run python3 -c "import json,sys; c=json.load(open(sys.argv[1]))['commits']; assert c[0]['tracks']==['A'] and c[0]['files']==1, c" "$BANK/reports/demo/team.json"
  [ "$status" -eq 0 ]
}

@test "commit: a file co-owned by an unfinished unselected track is refused and named" {
  team_two_tracks coowned; team_fill_brief demo
  echo a2 >>"$PROJ/a/x.txt"; echo s2 >>"$PROJ/shared/z.txt"
  team_return A; team collect >/dev/null
  run team commit --tracks A -m "feat: a" --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"shared/z.txt"*"B"* ]] || false
  [ "$(head_subject)" = "init" ]
}

@test "commit: an unfinished track or an open BLOCKED for it is refused" {
  team_two_tracks; team_fill_brief demo
  echo a2 >>"$PROJ/a/x.txt"
  team track set A --status dispatched >/dev/null
  run team commit --tracks A -m "feat: a" --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"A"*"dispatched"* ]] || false
  team track set A --status returned >/dev/null
  printf 'STATUS: DONE\n' >"$BANK/reports/demo/A.md"; team collect >/dev/null
  bash "$REPO/scripts/mb-coord.sh" append --mb "$BANK" --track A --type BLOCKED --title 'stuck' >/dev/null
  run team commit --tracks A -m "feat: a" --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCKED"* ]] || false
  [ "$(head_subject)" = "init" ]
}

@test "commit: without --yes and without a TTY nothing is staged or committed" {
  team_two_tracks; team_fill_brief demo
  echo a2 >>"$PROJ/a/x.txt"
  team_return A; team collect >/dev/null
  run bash -c 'cd "$1" && bash "$2" --mb "$3" commit --tracks A -m "feat: a" </dev/null' _ "$PROJ" "$TEAM" "$BANK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--yes"* ]] || false
  [ "$(head_subject)" = "init" ]
  [ -z "$(git -C "$PROJ" diff --cached --name-only)" ]
  run ! grep -q '^## COMMIT' "$BANK/COORDINATION.md"
}

@test "commit: an owned file with a cyrillic name and a space is staged, not listed as foreign" {
  team_two_tracks; team_fill_brief demo
  echo v1 >"$PROJ/a/файл с пробелом.md"; git -C "$PROJ" add -A; git -C "$PROJ" commit -qm cyr
  echo v2 >>"$PROJ/a/файл с пробелом.md"; echo b2 >>"$PROJ/b/y.txt"
  team_return A; team_return B; team collect >/dev/null
  run team commit --tracks A -m "feat: cyr" --yes
  [ "$status" -eq 0 ]
  [ "$(git -C "$PROJ" -c core.quotePath=false show --name-only --format= HEAD)" = "a/файл с пробелом.md" ]
  [[ "$output" != *"foreign"*"файл"* ]] || false
}
