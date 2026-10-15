#!/usr/bin/env bats
# End-to-end /mb team run without model calls: the orchestrator's side is simulated
# (reports written by hand, statuses moved with `track set`), every step goes through
# scripts/mb-team.sh in a temp git project whose path contains spaces.

load ../bats/lib/team_fixture

setup() { team_fixture_setup; }

@test "team e2e: init, two tracks, next, returns, collect, checkpoint, path-scoped commit, status" {
  team_two_tracks; team_fill_brief demo
  run team next
  [ "$output" = "$(printf 'dispatch A\ndispatch B')" ]

  echo a2 >>"$PROJ/a/x.txt"; echo b2 >>"$PROJ/b/y.txt"; echo new >"$PROJ/a/new.txt"
  team_return A; team_return B
  run team next
  [ "$output" = "collect" ]
  run team collect
  [ "$status" -eq 0 ]
  [ "$(grep -c 'demo' "$BANK/progress.md")" -ge 2 ]

  run team checkpoint pre-commit
  [ "$status" -eq 0 ]

  # A foreign file the user staged earlier must stay staged and out of the team commit.
  echo stray >"$PROJ/stray.txt"; git -C "$PROJ" add stray.txt
  run team commit --tracks A,B -m "feat: a and b" --yes
  [ "$status" -eq 0 ]
  [ "$(git -C "$PROJ" log --format=%s -1)" = "feat: a and b" ]
  [ "$(git -C "$PROJ" show --name-only --format= HEAD | sort | tr '\n' ' ')" = "a/new.txt a/x.txt b/y.txt " ]
  [ "$(git -C "$PROJ" diff --cached --name-only)" = "stray.txt" ]
  grep -q '^## COMMIT · .* · team demo: ' "$BANK/COORDINATION.md"

  run team next
  [ "$output" = "stop_success" ]
  run team status
  [ "$status" -eq 0 ]
  grep -qF "team demo" <<<"$output"
  [ ! -e "$PROJ/a/.memory-bank" ]
  [ ! -e "$BANK/.memory-bank" ]
}

@test "team e2e: review start, one finding, gate, fix to the owner, clean cycle, gate 0" {
  team init demo --no-goal --tree "$PROJ" --team-review >/dev/null
  team track add A --task "change a" --dod "a changed" --files "a/**" --size small >/dev/null
  team track add B --task "change b" --dod "b changed" --files "b/**" --size small >/dev/null
  team_fill_brief demo
  echo a2 >>"$PROJ/a/x.txt"; echo b2 >>"$PROJ/b/y.txt"
  team_return A; team_return B; team collect >/dev/null
  run team next
  [ "$output" = "team_review 1" ]

  run team review start --cycle 1
  [ "$status" -eq 0 ]
  [ -f "$BANK/reports/demo/review/cycle-1/brief.md" ]

  cat >"$BANK/reports/demo/review/cycle-1/master.json" <<'JSON'
{"verdict": "CHANGES_REQUESTED", "counts": {"blocker": 0, "major": 1, "medium": 0, "minor": 0},
 "issues": [{"id": "M-1", "severity": "major", "category": "logic", "file": "a/x.txt", "line": 1, "message": "wrong", "owner": "A"}],
 "previous_issues": []}
JSON
  run team review gate --cycle 1
  [ "$status" -eq 1 ]
  run team next
  [ "$output" = "fix A" ]

  # The orchestrator re-dispatches A with the finding; A fixes and returns.
  team track set A --status fixing >/dev/null
  echo a3 >>"$PROJ/a/x.txt"
  team track set A --status returned >/dev/null
  # The fix is new work: it is collected again (progress entry, back to done) before cycle 2.
  run team next
  [ "$output" = "collect" ]
  run team collect
  [ "$status" -eq 0 ]
  [ "$(python3 -c "import json,sys; print([t['status'] for t in json.load(open(sys.argv[1]))['tracks'] if t['id']=='A'][0])" "$BANK/reports/demo/team.json")" = "done" ]
  run team next
  [ "$output" = "team_review 2" ]

  run team review start --cycle 2
  [ "$status" -eq 0 ]
  grep -qF "M-1" "$BANK/reports/demo/review/cycle-2/brief.md"
  cat >"$BANK/reports/demo/review/cycle-2/master.json" <<'JSON'
{"verdict": "APPROVED", "counts": {"blocker": 0, "major": 0, "medium": 0, "minor": 0},
 "issues": [],
 "previous_issues": [{"id": "M-1", "status": "resolved", "evidence": "a/x.txt:1"}]}
JSON
  run team review gate --cycle 2
  [ "$status" -eq 0 ]
  run python3 -c "import json,sys; r=json.load(open(sys.argv[1]))['reviews']; assert [(x['cycle'],x['verdict']) for x in r]==[(1,'fixes_needed'),(2,'clean')], r" "$BANK/reports/demo/team.json"
  [ "$status" -eq 0 ]
}

@test "test_REQ_001__track_runs_through_the_work_loop" {
  team init demo --no-goal --tree "$PROJ" >/dev/null
  team track add A --task "change a" --dod "a changed" --files "a/**" --size small >/dev/null
  team track add B --task "change b" --dod "b changed" --files "b/**" --size standard >/dev/null
  run team plan --json
  [ "$status" -eq 0 ]
  python3 - "$output" "$BANK" <<'PY'
import json, sys
tracks = json.loads(sys.argv[1])["tracks"]
assert len(tracks) == 2, tracks
for t in tracks:
    assert t["pipeline"]["mode"] == "work", t
PY
  python3 - "$BANK/reports/demo/team.json" <<'PY'
import json, sys
for t in json.load(open(sys.argv[1]))["tracks"]:
    assert t["source"].endswith(f"tracks/{t['id']}.prompt.md"), t
PY
  team_fill_brief demo
  echo b2 >>"$PROJ/b/y.txt"
  team_return B
  run team next
  [ "$output" = "$(printf 'dispatch A\ncollect')" ]
  [ -z "$(grep -E 'verify|review' <<<"$output")" ]
}

@test "test_REQ_003__cancelled_dependency_stops_the_team" {
  team init demo --no-goal --tree "$PROJ" >/dev/null
  team track add A --task "a" --dod "a" --files "a/**" --size small >/dev/null
  team track add B --task "b" --dod "b" --files "b/**" --size small --deps A >/dev/null
  team track add C --task "c" --dod "c" --files "shared/**" --size small >/dev/null
  team_fill_brief demo
  team track set A --status cancelled >/dev/null
  run team next
  [ "$output" = "stop_human blocked:dep-cancelled:A" ]
  run team status
  grep -qF "blocked:dep-cancelled:A" <<<"$output"
}

@test "test_REQ_004__red_flow_after_the_last_collect_stops_the_team" {
  team_two_tracks; team_fill_brief demo
  team track set B --status cancelled >/dev/null
  echo a2 >>"$PROJ/a/x.txt"
  # The report ends with STATUS: DONE after other text.
  team_return A
  printf 'notes after the files\nSTATUS: DONE\n' >>"$BANK/reports/demo/A.md"
  run team collect
  [ "$status" -eq 0 ]
  printf '#!/usr/bin/env bash\necho "{\\"tests_pass\\": false, \\"tests_failed\\": 1}"\n' >"$BATS_TEST_TMPDIR/red-tests.sh"
  chmod +x "$BATS_TEST_TMPDIR/red-tests.sh"
  MB_TEST_RUN_BIN="$BATS_TEST_TMPDIR/red-tests.sh" run team next
  [ "$output" = "stop_human flow-red:tests" ]
}

@test "test_REQ_007__failed_commit_leaves_the_index_as_it_was" {
  team_two_tracks; team_fill_brief demo
  echo a2 >>"$PROJ/a/x.txt"; echo new >"$PROJ/a/new.txt"
  team_return A; team_return B
  team collect >/dev/null
  mkdir -p "$PROJ/.git/hooks"
  printf '#!/bin/sh\nexit 1\n' >"$PROJ/.git/hooks/pre-commit"; chmod +x "$PROJ/.git/hooks/pre-commit"
  echo stray >"$PROJ/stray.txt"; git -C "$PROJ" add stray.txt
  before="$(git -C "$PROJ" diff --cached --name-status)"
  run team commit --tracks A -m "feat: a" --yes
  [ "$status" -eq 1 ]
  [ "$(git -C "$PROJ" diff --cached --name-status)" = "$before" ]
  [ "$(git -C "$PROJ" log --format=%s -1)" = "init" ]
}

@test "test_REQ_009__broken_inputs_are_refused_cleanly" {
  team init demo --no-goal --tree "$PROJ" --team-review >/dev/null
  team track add A --task "a" --dod "a" --files "a/**" --size small >/dev/null
  team_fill_brief demo
  echo a2 >>"$PROJ/a/x.txt"; team_return A; team collect >/dev/null
  team review start --cycle 1 >/dev/null
  printf 'not json at all\n' >"$BANK/reports/demo/review/cycle-1/master.json"
  json="$BANK/reports/demo/team.json"; before="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['reviews'])" "$json")"
  run team review gate --cycle 1
  [ "$status" -eq 2 ]
  [ -z "$(grep Traceback <<<"$output")" ]
  [ "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['reviews'])" "$json")" = "$before" ]

  # A frozen clock makes the second checkpoint repeat the first id.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho 2026-01-01-000000\n' >"$BATS_TEST_TMPDIR/bin/date"; chmod +x "$BATS_TEST_TMPDIR/bin/date"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run team checkpoint first
  [ "$status" -eq 0 ]
  dir="$BANK/../backups-out"; sum="$(cat "$dir"/*.diff "$dir"/*-manifest.json | shasum)"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run team checkpoint first
  [ "$status" -eq 1 ]
  [ "$(cat "$dir"/*.diff "$dir"/*-manifest.json | shasum)" = "$sum" ]
  run team checkpoint ../x
  [ "$status" -eq 2 ]

  # Host lock root ignores TMPDIR.
  probe='import sys; sys.path.insert(0, sys.argv[1]); import mb_team_config as c; print(c.host_lock_root())'
  r1="$(env -u MB_LOCK_DIR python3 -c "$probe" "$REPO/scripts")"
  r2="$(env -u MB_LOCK_DIR TMPDIR="$BATS_TEST_TMPDIR" python3 -c "$probe" "$REPO/scripts")"
  [ "$r1" = "$r2" ]
}

@test "test_REQ_013__track_dispatch_is_described_for_four_hosts" {
  sec="$(sed -n '/^## 9. Hosts/,/^## 10\./p' "$REPO/commands/team.md")"
  for h in "Claude Code" Codex OpenCode Pi; do grep -qF "$h" <<<"$sec"; done
  grep -qF "SKILL.md" <<<"$sec"
  grep -qF "Invocation" <<<"$sec"
  grep -qi "track boundary" <<<"$sec"
}
