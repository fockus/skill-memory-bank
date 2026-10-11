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
