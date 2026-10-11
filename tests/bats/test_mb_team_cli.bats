#!/usr/bin/env bats
# mb-team.sh — init, track, next, status, collect, checkpoint (specs/mb-team design §7, §9, §10).
# shellcheck disable=SC2016  # single-quoted bash -c bodies take positional args on purpose

load lib/team_fixture
bats_require_minimum_version 1.5.0

setup() { team_fixture_setup; }

teardown() {
  [ -n "${WAITER:-}" ] && { pkill -TERM -P "$WAITER" 2>/dev/null; kill -TERM "$WAITER" 2>/dev/null; }
  return 0
}

@test "team: cwd inside the bank is refused and no nested bank appears" {
  run bash -c 'cd "$1" && bash "$2" status' _ "$BANK" "$TEAM"
  [ "$status" -eq 2 ]
  [[ "$output" == *"inside a Memory Bank"* ]] || false
  [ ! -e "$BANK/.memory-bank" ]
}

@test "team: init writes team.json and brief, freezes the contract on the board" {
  run team init demo --no-goal --tree "$PROJ" --max-parallel 2
  [ "$status" -eq 0 ]
  run python3 -c "import json,sys; t=json.load(open(sys.argv[1])); assert t['vcs']=='git' and t['max_parallel']==2 and len(t['baseline'])==40, t" "$BANK/reports/demo/team.json"
  [ "$status" -eq 0 ]
  grep -q '<!-- fill:' "$BANK/reports/demo/brief.md"
  grep -q '^## FREEZE · .* · contract:demo$' "$BANK/COORDINATION.md"
}

@test "team: the tracks table of an untouched brief follows track add; an edited brief is kept" {
  team_two_tracks
  grep -q '| A | developer |' "$BANK/reports/demo/brief.md"
  grep -q '| B | developer |' "$BANK/reports/demo/brief.md"
  team_fill_brief demo
  run team track add C --task "c" --dod "c done" --files "c/**" --size small
  [ "$status" -eq 0 ]
  [[ "$output" == *"brief was edited"* ]] || false
  run ! grep -q '| C |' "$BANK/reports/demo/brief.md"
}

@test "team: next waits for the brief, then dispatches; prints only" {
  team_two_tracks
  run team next
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human brief-unfilled" ]
  team_fill_brief demo
  run team next
  [ "$output" = "$(printf 'dispatch A\ndispatch B')" ]
  run team next --json
  [[ "$output" == *'"actions": ["dispatch A", "dispatch B"]'* ]] || false
  run python3 -c "import json,sys; assert all(t['status']=='planned' for t in json.load(open(sys.argv[1]))['tracks'])" "$BANK/reports/demo/team.json"
  [ "$status" -eq 0 ]
}

@test "team: collect appends one progress entry per newly returned track; a second run appends nothing" {
  team_two_tracks; team_fill_brief demo
  team_return A
  run team collect
  [ "$status" -eq 0 ]
  [[ "$output" == *"mb-agree.sh question 'ask about A'"* ]] || false
  [[ "$output" == *"mb-idea.sh"*"idea from A"* ]] || false
  [ "$(grep -c 'team demo · track A' "$BANK/progress.md")" -eq 1 ]
  run team collect
  [ "$(grep -c 'team demo · track' "$BANK/progress.md")" -eq 1 ]
  team_return B DONE_WITH_CONCERNS
  team collect >/dev/null
  [ "$(grep -c 'team demo · track' "$BANK/progress.md")" -eq 2 ]
  run python3 -c "import json,sys; t={x['id']:x for x in json.load(open(sys.argv[1]))['tracks']}; assert (t['A']['status'],t['B']['status'])==('done','done_with_concerns') and t['B']['collected'], t" "$BANK/reports/demo/team.json"
  [ "$status" -eq 0 ]
}

@test "team: collect lists goal criteria next to the collected reports" {
  printf -- '---\nprogress_source: checklist\n---\n# Goal\n\n## Acceptance criteria\n- [ ] login works\n- [x] build green\n' >"$BANK/goal.md"
  team init demo --goal G-001 --tree "$PROJ" >/dev/null
  team track add A --task "a" --dod "a done" --files "a/**" --size small >/dev/null
  team_return A
  run team collect --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"criterion": "login works", "checked": false'* ]] || false
  [[ "$output" == *'"evidence": ['*'A.md'* ]]
}

@test "team: status --json reports a held lock, a queued waiter and an open BLOCKED" {
  team_two_tracks
  token=$(bash "$REPO/scripts/mb-lock.sh" acquire build --owner A --lease 600 --mb "$BANK")
  bash "$REPO/scripts/mb-lock.sh" run build --owner B --mb "$BANK" -- true 2>/dev/null &
  WAITER=$!
  for _ in $(seq 1 50); do ls "$BANK/.locks/res/build.queue/"* >/dev/null 2>&1 && break; sleep 0.1; done
  bash "$REPO/scripts/mb-coord.sh" append --mb "$BANK" --track B --type BLOCKED --title 'disk 12 GiB' >/dev/null
  run team status --json
  [ "$status" -eq 0 ]
  run python3 -c "
import json,sys
s=json.loads(sys.argv[1])
r={x['name']:x for x in s['resources']}['build']
assert r['held'] and r['holder']['owner']=='A', r
assert [q['owner'] for q in r['queue']]==['B'], r
assert [b['track'] for b in s['open_blocked']]==['B'], s['open_blocked']
assert {t['id']:t['board']['type'] for t in s['tracks'] if t['board']}=={'B':'BLOCKED'}
assert 'stop_human blocked:B' in s['next']
" "$output"
  [ "$status" -eq 0 ]
  bash "$REPO/scripts/mb-lock.sh" release build --token "$token" --mb "$BANK"
}

@test "team: checkpoint writes into team.checkpoint.dir, records it, verify passes" {
  team_two_tracks
  echo changed >>"$PROJ/a/x.txt"
  run team checkpoint s1
  [ "$status" -eq 0 ]
  id=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['checkpoints'][0]['id'])" "$BANK/reports/demo/team.json")
  [ -f "$PROJ/backups-out/$id.diff" ]
  run team checkpoint --verify "$id"
  [ "$status" -eq 0 ]
}

@test "team: end to end — init, two tracks, next, returns, collect, checkpoint, commit" {
  team_two_tracks; team_fill_brief demo
  run team next
  [ "$output" = "$(printf 'dispatch A\ndispatch B')" ]
  echo a2 >>"$PROJ/a/x.txt"; echo b2 >>"$PROJ/b/y.txt"; echo new >"$PROJ/a/new.txt"
  team_return A; team_return B
  run team next
  [ "$output" = "collect" ]
  team collect >/dev/null
  run team checkpoint pre-commit
  [ "$status" -eq 0 ]
  run team commit --tracks A,B -m "feat: a and b" --yes
  [ "$status" -eq 0 ]
  [ "$(git -C "$PROJ" log --format=%s -1)" = "feat: a and b" ]
  [ "$(git -C "$PROJ" show --name-only --format= HEAD | sort | tr '\n' ' ')" = "a/new.txt a/x.txt b/y.txt " ]
  grep -q '^## COMMIT · .* · team demo: ' "$BANK/COORDINATION.md"
  run team next
  [ "$output" = "stop_success" ]
  run team status
  [ "$status" -eq 0 ]
  [[ "$output" == *"team demo"* ]]
}

@test "team: review gate is recorded in reviews[] and next routes the fix to the owner track" {
  team_two_tracks; team_fill_brief demo
  python3 - "$BANK/reports/demo/team.json" <<'PY'
import json, sys
p = sys.argv[1]; t = json.load(open(p)); t["team_review"] = True
json.dump(t, open(p, "w"))
PY
  team_return A; team_return B; team collect >/dev/null
  run team --topic demo next
  [ "$output" = "team_review 1" ]
  mkdir -p "$BANK/reports/demo/review/cycle-1"
  cat >"$BANK/reports/demo/review/cycle-1/master.json" <<'JSON'
{"verdict": "CHANGES_REQUESTED", "counts": {"blocker": 0, "major": 1, "minor": 0},
 "issues": [{"id": "M-1", "severity": "major", "category": "logic", "file": "a/x.txt", "line": 1, "message": "wrong", "owner": "A"}],
 "previous_issues": []}
JSON
  run team review gate --cycle 1
  [ "$status" -eq 1 ]
  run python3 -c "import json,sys; r=json.load(open(sys.argv[1]))['reviews']; assert [(x['cycle'],x['verdict'],x['actions']) for x in r]==[(1,'fixes_needed',['fix A'])], r" "$BANK/reports/demo/team.json"
  [ "$status" -eq 0 ]
  run team next
  [ "$output" = "fix A" ]
}

@test "team: an accepted work:light track without verifier or review is collected, not left waiting" {
  printf -- '---\ntype: feature\ntopic: t\n---\n# L\n\n<!-- mb-stage:1 -->\n### Stage 1: one\n\n**DoD:**\n- [ ] bit\n' >"$BANK/light.md"
  team init demo --no-goal --tree "$PROJ" >/dev/null
  team track add L --task "light" --dod "bit" --files "a/**" --size small --mode work:light \
    --verifier none --review none --source "$BANK/light.md" >/dev/null
  team_fill_brief demo
  printf 'STATUS: DONE\n\n## Stages\n- 1: done\n' >"$BANK/reports/demo/L.md"
  team track set L --status dispatched >/dev/null
  team track set L --status returned >/dev/null
  run team next
  [ "$output" = "collect" ]
  run team collect
  [ "$status" -eq 0 ]
  [[ "$output" == *"collected: L"* ]] || false
  run team next
  [ "$output" = "stop_success" ]
}

@test "team: collect prints report questions as inert shell words (no command substitution)" {
  team_two_tracks; team_fill_brief demo
  team_return A
  printf 'STATUS: DONE\n\n## Questions\n- Should `touch %s/pwned1` run? $(touch %s/pwned2) it'"'"'s fine\n' \
    "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" >"$BANK/reports/demo/A.md"
  run team collect
  [ "$status" -eq 0 ]
  qline="$(grep '^question: ' <<<"$output")"
  eval "set -- ${qline#*mb-agree.sh}"
  [ "$1" = question ]
  [ "$2" = "Should \`touch $BATS_TEST_TMPDIR/pwned1\` run? \$(touch $BATS_TEST_TMPDIR/pwned2) it's fine" ]
  [ ! -e "$BATS_TEST_TMPDIR/pwned1" ]
  [ ! -e "$BATS_TEST_TMPDIR/pwned2" ]
}
