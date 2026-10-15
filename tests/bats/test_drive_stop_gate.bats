#!/usr/bin/env bats
# drive-autopilot Task 3 — the stop record and the resume gate on the drive
# run files <bank>/.drive/<run_id>.json (design C4; REQ-045, REQ-028, REQ-043).
#
# The gate decides from run files, the hook input's session_id and goal ticks
# only: never from MB_WORK_RUN_ID, a `check:` command or the firewall.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  GATE="$REPO_ROOT/hooks/mb-drive-resume-gate.sh"
  STOP="$REPO_ROOT/scripts/mb-drive-stop.sh"
  PROJECT="$BATS_TEST_TMPDIR/proj"
  BANK="$PROJECT/.memory-bank"
  mkdir -p "$BANK/.drive"
  printf '# Status\n\nWorking.\n' > "$BANK/status.md"
  printf '# Progress\n\n' > "$BANK/progress.md"
  unset MB_WORK_PARALLEL MB_WORK_RUN_ID MB_DRIVE_RESUME_GATE MB_SESSION_ID CLAUDE_CODE_SESSION_ID
}

# write_goal <file> <box> [extra lines] — one acceptance criterion.
write_goal() {
  printf '# Goal\n\nShip it.\n\n## Acceptance criteria\n\n- [%s] the only criterion\n%s' \
    "$2" "${3:-}" > "$1"
}

# write_run <run_id> <phase> <session|""> <goal path>
write_run() {
  python3 - "$BANK" "$1" "$2" "$3" "$4" <<'PY'
import json, sys
bank, run_id, phase, session, goal = sys.argv[1:]
doc = {"run_id": run_id, "bank": bank, "goal": goal, "session": session or None,
       "phase": phase, "parallel": True, "parallel_reason": "default", "approved": [],
       "steps": 0, "waits": 0, "items": {}, "final_qa": "pending", "final_qa_blocked": 0,
       "final_qa_cycle": 0, "stop_reason": "", "started": "2026-10-15T00:00:00+00:00"}
open(f"{bank}/.drive/{run_id}.json", "w", encoding="utf-8").write(json.dumps(doc))
PY
}

field() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' \
    "$BANK/.drive/$1.json" "$2"
}

# gate <session_id|""> [stop_hook_active] — Stop event JSON on stdin.
gate() {
  local sid=""
  [ -n "$1" ] && sid=",\"session_id\":\"$1\""
  run --separate-stderr bash -c 'printf "%s" "$1" | bash "$2"' _ \
    "{\"cwd\":\"$PROJECT\",\"stop_hook_active\":${2:-false}$sid}" "$GATE"
}

blocked() { [ "$status" -eq 0 ] && [[ "$output" == *'"decision":"block"'* ]]; }
allowed() { [ "$status" -eq 0 ] && [[ "$output" != *'"decision":"block"'* ]]; }

# ---- stop record -------------------------------------------------------------

@test "drive_gate: record writes phase stopped and the reason into the selected run file, the fence and one progress line" {
  write_goal "$BANK/goal.md" ' '
  write_run R1 execution S1 "$BANK/goal.md"
  write_run R2 execution S2 "$BANK/goal.md"
  run bash "$STOP" record --bank "$BANK" --run-id R1 --action "stop_human stall"
  [ "$status" -eq 0 ]
  [ "$(field R1 phase)" = "stopped" ]
  [ "$(field R1 stop_reason)" = "human:stall" ]
  [ "$(field R2 phase)" = "execution" ]
  grep -q '^stop_reason: human:stall$' "$BANK/status.md"
  [ "$(grep -c 'human:stall' "$BANK/progress.md")" = "1" ]
  grep -q 'run=`R1`' "$BANK/progress.md"
}

@test "drive_gate: record accepts every new stop reason" {
  for action in "stop_human stall" "stop_human acceptance-red:2" "stop_human flow-red:tests,lint" \
    "stop_human qa-blocked:no-browser" "stop_human qa-red" "stop_human owned-elsewhere:20261015-ab"; do
    write_run R1 execution S1 "$BANK/goal.md"
    run bash "$STOP" record --bank "$BANK" --run-id R1 --action "$action"
    [ "$status" -eq 0 ]
    [ "$(field R1 stop_reason)" = "human:${action#stop_human }" ]
  done
}

@test "drive_gate: record refuses an unknown reason with exit 2 and leaves the run live" {
  write_run R1 execution S1 "$BANK/goal.md"
  run bash "$STOP" record --bank "$BANK" --run-id R1 --reason "human:whatever"
  [ "$status" -eq 2 ]
  [ "$(field R1 phase)" = "execution" ]
}

@test "drive_gate: record without --run-id and two live runs exits 2" {
  write_run R1 execution S1 "$BANK/goal.md"
  write_run R2 planning S2 "$BANK/goal.md"
  run bash "$STOP" record --bank "$BANK" --reason success
  [ "$status" -eq 2 ]
  [ "$(field R1 phase)" = "execution" ]
  [ "$(field R2 phase)" = "planning" ]
}

@test "drive_gate: record without --run-id stops the only live run" {
  write_run R1 execution S1 "$BANK/goal.md"
  run bash "$STOP" record --bank "$BANK" --reason budget
  [ "$status" -eq 0 ]
  [ "$(field R1 stop_reason)" = "budget" ]
}

@test "drive_gate: path and state print the selected run file" {
  write_run R1 execution S1 "$BANK/goal.md"
  run bash "$STOP" path --bank "$BANK"
  [ "$output" = "$BANK/.drive/R1.json" ]
  run bash "$STOP" state --bank "$BANK" --run-id R1
  [[ "$output" == *'"run_id": "R1"'* ]]
}

# ---- resume gate ---------------------------------------------------------------

@test "drive_gate: blocks in phase execution with an unmet goal for the run of its session, without MB_WORK_RUN_ID" {
  write_goal "$BANK/goal.md" ' '
  write_run R1 execution S1 "$BANK/goal.md"
  gate S1
  blocked
  [[ "$output" == *"R1"* ]]
}

@test "drive_gate: allows for another session's run, whatever MB_WORK_RUN_ID says" {
  write_goal "$BANK/goal.md" ' '
  write_run R1 execution S1 "$BANK/goal.md"
  export MB_WORK_PARALLEL=1 MB_WORK_RUN_ID=R1
  gate S2
  allowed
}

@test "drive_gate: blocks for the single sessionless run when the host gives no session" {
  write_goal "$BANK/goal.md" ' '
  write_run R1 execution "" "$BANK/goal.md"
  gate ""
  blocked
}

@test "drive_gate: allows with one warning when two sessionless runs are live" {
  write_goal "$BANK/g1.md" ' '
  write_goal "$BANK/g2.md" ' '
  write_run R1 execution "" "$BANK/g1.md"
  write_run R2 execution "" "$BANK/g2.md"
  gate ""
  allowed
  [[ "$stderr" == *"R1"* && "$stderr" == *"R2"* ]]
  [ "$(printf '%s\n' "$stderr" | grep -c .)" = "1" ]
}

@test "drive_gate: allows in phase planning" {
  write_goal "$BANK/goal.md" ' '
  write_run R1 planning S1 "$BANK/goal.md"
  gate S1
  allowed
}

@test "drive_gate: allows after a recorded stop" {
  write_goal "$BANK/goal.md" ' '
  write_run R1 execution S1 "$BANK/goal.md"
  bash "$STOP" record --bank "$BANK" --run-id R1 --action "stop_human stall"
  gate S1
  allowed
}

@test "drive_gate: allows with a met goal" {
  write_goal "$BANK/goal.md" 'x'
  write_run R1 execution S1 "$BANK/goal.md"
  gate S1
  allowed
}

@test "drive_gate: allows without run files" {
  write_goal "$BANK/goal.md" ' '
  gate S1
  allowed
}

@test "drive_gate: allows on stop_hook_active" {
  write_goal "$BANK/goal.md" ' '
  write_run R1 execution S1 "$BANK/goal.md"
  gate S1 true
  allowed
}

@test "drive_gate: a poisoned check command is never run by the gate" {
  poison="$BATS_TEST_TMPDIR/check-ran"
  write_goal "$BANK/goal.md" ' ' "  - check: touch $poison"$'\n'
  write_run R1 execution S1 "$BANK/goal.md"
  gate S1
  blocked
  [ ! -e "$poison" ]
}

@test "drive_gate: a poisoned firewall is never run by the gate" {
  poison="$BATS_TEST_TMPDIR/firewall-ran"
  printf '#!/usr/bin/env bash\ntouch %s\nsleep 30\n' "$poison" > "$BATS_TEST_TMPDIR/verify.sh"
  chmod +x "$BATS_TEST_TMPDIR/verify.sh"
  write_goal "$BANK/goal.md" ' '
  write_run R1 execution S1 "$BANK/goal.md"
  export MB_FLOW_VERIFY_BIN="$BATS_TEST_TMPDIR/verify.sh"
  gate S1
  blocked
  [ ! -e "$poison" ]
}
