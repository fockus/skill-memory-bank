#!/usr/bin/env bats
# mb-lock.sh — named resource locks with a fair ticket queue (specs/mb-team design §5, C3/C4).
#
# Contract under test:
#   * a released lock goes to the oldest live waiter (ticket order);
#   * a waiter that exits (TERM or KILL) leaves no ticket; dead tickets are skipped;
#   * a lock whose holder or holder child is alive is never removed (run, acquire, break);
#   * a provably dead holder (wrapper and child gone, same host, pid + start time) is
#     reclaimed by the queue head with a board entry (AGR-097);
#   * exit 75 wait timeout · 76 stop condition · 77 preconditions unmet after maintenance;
#   * maintenance runs only for the lock holder.
# Board entries are asserted on a real fixture bank through the real mb-coord.sh.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LOCK="$REPO/scripts/mb-lock.sh"
  T="$BATS_TEST_TMPDIR"
  BANK="$T/proj/.memory-bank"
  mkdir -p "$BANK"
  printf '# Coordination board\n' >"$BANK/COORDINATION.md"
  PIDS=()
}

teardown() {
  local p
  for p in "${PIDS[@]:-}"; do
    [ -n "$p" ] || continue
    pkill -KILL -P "$p" 2>/dev/null
    kill -KILL "$p" 2>/dev/null
  done
  pkill -KILL -f "$T/" 2>/dev/null
  return 0
}

# res <name> [extra JSON members] → writes $T/<name>.json
res() {
  printf '{"name": "%s", "kind": "mutex", "scope": "host", "path": "%s/locks/%s", "poll_s": 0.1, "watch_interval_s": 0.2%s}\n' \
    "$1" "$T" "$1" "${2:-}" >"$T/$1.json"
}

# lk <sub> <res> [args…] — --mb goes before the args so it never lands after `--`.
lk() { bash "$LOCK" "$1" "$2" --mb "$BANK" "${@:3}"; }
# Background waiters call `bash "$LOCK"` directly so $! is the wrapper itself: `lk … &` would put a
# subshell in between, and killing that subshell would leave the wrapper running.

# wait_for <seconds> <bash condition>
wait_for() {
  local deadline=$((SECONDS + $1))
  until eval "$2"; do
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep 0.05
  done
}

queue_len() { find "$T/locks/$1.queue" -type f -name '[0-9]*' 2>/dev/null | wc -l | tr -d ' '; }

hold() { # hold <res> → token of a lease holder
  lk acquire "$1" --owner H --lease 120 --resource-json "$T/$1.json"
}

@test "lock: three queued waiters acquire in ticket order (10 runs)" {
  res build
  local i
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    : >"$T/order"
    tok="$(hold build)"
    for i in 1 2 3; do
      bash "$LOCK" run build --mb "$BANK" --owner "W$i" --resource-json "$T/build.json" -- \
        bash -c "echo W$i >>'$T/order'; sleep 0.05" &
      PIDS+=("$!")
      wait_for 10 "[ \"\$(queue_len build)\" = $i ]"
    done
    lk release build --token "$tok" --resource-json "$T/build.json"
    wait_for 20 "[ \"\$(wc -l <'$T/order' | tr -d ' ')\" = 3 ]"
    wait
    [ "$(tr '\n' ' ' <"$T/order")" = "W1 W2 W3 " ]
  done
}

@test "lock: a waiter cancelled with TERM or KILL leaves no ticket and frees its place" {
  res build
  tok="$(hold build)"
  bash "$LOCK" run build --mb "$BANK" --owner W1 --resource-json "$T/build.json" -- true &
  w1=$!
  PIDS+=("$w1")
  wait_for 10 '[ "$(queue_len build)" = 1 ]'
  bash "$LOCK" run build --mb "$BANK" --owner W2 --resource-json "$T/build.json" -- bash -c "echo W2 >'$T/ran'" &
  w2=$!
  PIDS+=("$w2")
  wait_for 10 '[ "$(queue_len build)" = 2 ]'
  kill -TERM "$w1"
  wait_for 10 '[ "$(queue_len build)" = 1 ]'
  bash "$LOCK" run build --mb "$BANK" --owner W3 --resource-json "$T/build.json" -- true &
  w3=$!
  PIDS+=("$w3")
  wait_for 10 '[ "$(queue_len build)" = 2 ]'
  kill -KILL "$w3"
  wait_for 10 '[ "$(queue_len build)" = 1 ]'
  lk release build --token "$tok" --resource-json "$T/build.json"
  wait "$w2"
  [ "$(cat "$T/ran")" = W2 ]
  [ "$(queue_len build)" = 0 ]
}

@test "lock: a ticket of a dead process is skipped" {
  res build
  mkdir -p "$T/locks/build.queue"
  printf '{"owner": "ghost", "pid": 999999, "pid_start": "x", "host": "%s", "since": 1}\n' \
    "$(python3 -c 'import socket; print(socket.gethostname())')" >"$T/locks/build.queue/000000000001"
  run lk run build --owner W1 --wait 5 --resource-json "$T/build.json" -- echo ran
  [ "$status" -eq 0 ]
  [[ "$output" == *ran* ]] || false
  [ "$(queue_len build)" = 0 ]
}

@test "lock: a live holder is never removed by run, acquire or break" {
  res build
  bash "$LOCK" run build --mb "$BANK" --owner R --resource-json "$T/build.json" -- bash -c "touch '$T/started'; sleep 30" &
  PIDS+=("$!")
  wait_for 10 "[ -f '$T/started' ]"
  before="$(cat "$T/locks/build.lock/meta.json")"
  run lk break build --reason test --resource-json "$T/build.json"
  [ "$status" -eq 1 ]
  run lk acquire build --owner A --lease 10 --wait 1 --resource-json "$T/build.json"
  [ "$status" -eq 75 ]
  run lk run build --owner B --wait 1 --resource-json "$T/build.json" -- echo never
  [ "$status" -eq 75 ]
  [[ "$output" != *never* ]] || false
  [ "$(cat "$T/locks/build.lock/meta.json")" = "$before" ]
}

@test "lock: SIGKILLed wrapper keeps the lock while its child runs; the queue head reclaims it after" {
  res build
  bash "$LOCK" run build --mb "$BANK" --owner R --resource-json "$T/build.json" -- \
    bash -c "touch '$T/started'; while [ ! -f '$T/go' ]; do sleep 0.05; done" &
  wrapper=$!
  PIDS+=("$wrapper")
  wait_for 10 "[ -f '$T/started' ]"
  wait_for 10 "grep -q '\"child\": [0-9]' '$T/locks/build.lock/meta.json'"
  kill -KILL "$wrapper"
  run lk run build --owner B --wait 1 --resource-json "$T/build.json" -- echo early
  [ "$status" -eq 75 ]
  touch "$T/go"
  run lk run build --owner B --wait 10 --resource-json "$T/build.json" -- echo late
  [ "$status" -eq 0 ]
  [[ "$output" == *late* ]] || false
  grep -q '^## STATUS · .* · B: resource build: reclaimed dead lock of R' "$BANK/COORDINATION.md"
}

@test "lock: a recorded pid reused by another process counts as dead" {
  res build
  sleep 30 &
  other=$!
  PIDS+=("$other")
  mkdir -p "$T/locks/build.lock"
  printf '{"owner": "R", "token": "t", "pid": %s, "pid_start": "Mon Jan  1 00:00:00 2001", "child": null, "child_start": null, "host": "%s", "since": 1, "cmd": "make", "lease_until": null}\n' \
    "$other" "$(python3 -c 'import socket; print(socket.gethostname())')" >"$T/locks/build.lock/meta.json"
  run lk run build --owner B --wait 5 --resource-json "$T/build.json" -- echo ran
  [ "$status" -eq 0 ]
  [[ "$output" == *ran* ]] || false
  kill -0 "$other"
}

@test "lock: break removes a dead holder and posts a board entry" {
  res build
  mkdir -p "$T/locks/build.lock"
  printf '{"owner": "R", "token": "t", "pid": 999999, "pid_start": "x", "child": null, "child_start": null, "host": "%s", "since": 1, "cmd": "make", "lease_until": null}\n' \
    "$(python3 -c 'import socket; print(socket.gethostname())')" >"$T/locks/build.lock/meta.json"
  run lk break build --reason 'crashed build' --resource-json "$T/build.json"
  [ "$status" -eq 0 ]
  [ ! -e "$T/locks/build.lock" ]
  grep -q '^## STATUS · .* · resource build: broke dead lock of R' "$BANK/COORDINATION.md"
  grep -q 'crashed build' "$BANK/COORDINATION.md"
}

@test "lock: exit 77 when preconditions still fail after maintenance; the command is not run" {
  res build ", \"preconditions\": {\"check\": \"test -f '$T/ok'\"}, \"maintenance\": \"echo m >>'$T/maint'\""
  run lk run build --owner D3 --resource-json "$T/build.json" -- touch "$T/ran"
  [ "$status" -eq 77 ]
  [ "$(cat "$T/maint")" = m ]
  [ ! -e "$T/ran" ]
  [ ! -e "$T/locks/build.lock" ]
}

@test "lock: maintenance that restores the preconditions lets the command run" {
  res build ", \"preconditions\": {\"check\": \"test -f '$T/ok'\"}, \"maintenance\": \"touch '$T/ok'\""
  run lk run build --owner D3 --resource-json "$T/build.json" -- touch "$T/ran"
  [ "$status" -eq 0 ]
  [ -e "$T/ran" ]
}

@test "lock: free disk below the start threshold exits 77 (real df)" {
  res build ', "preconditions": {"free_disk_gb": 999999999, "disk_path": "/"}'
  run lk run build --owner D3 --no-maintenance --resource-json "$T/build.json" -- touch "$T/ran"
  [ "$status" -eq 77 ]
  [[ "$output" == *"GiB"* ]] || false
  [ ! -e "$T/ran" ]
}

@test "lock: stop condition mid-run terminates the child, posts BLOCKED, exits 76" {
  res build ", \"stop_threshold\": {\"check\": \"test ! -f '$T/stop'\"}"
  bash "$LOCK" run build --mb "$BANK" --owner D3 --resource-json "$T/build.json" -- \
    bash -c "echo \$\$ >'$T/child.pid'; exec sleep 30" &
  w=$!
  PIDS+=("$w")
  wait_for 10 "[ -s '$T/child.pid' ]"
  touch "$T/stop"
  rc=0
  wait "$w" || rc=$?
  [ "$rc" -eq 76 ]
  run kill -0 "$(cat "$T/child.pid")"
  [ "$status" -ne 0 ]
  [ ! -e "$T/locks/build.lock" ]
  grep -q '^## BLOCKED · .* · D3: resource build: stop condition' "$BANK/COORDINATION.md"
}

@test "lock: a stop condition terminates the whole command process group, grandchildren included" {
  res build ", \"stop_threshold\": {\"check\": \"test ! -f '$T/stop'\"}"
  bash "$LOCK" run build --mb "$BANK" --owner D3 --resource-json "$T/build.json" -- \
    bash -c "sleep 30 & echo \$! >'$T/grandchild.pid'; wait" &
  w=$!
  PIDS+=("$w")
  wait_for 10 "[ -s '$T/grandchild.pid' ]"
  touch "$T/stop"
  rc=0
  wait "$w" || rc=$?
  [ "$rc" -eq 76 ]
  wait_for 5 "! kill -0 $(cat "$T/grandchild.pid") 2>/dev/null"
}

@test "lock: maintenance and release refuse a caller that does not hold the lock" {
  res build ", \"maintenance\": \"touch '$T/maint'\""
  tok="$(hold build)"
  run lk maint build --token bogus --resource-json "$T/build.json"
  [ "$status" -eq 1 ]
  [ ! -e "$T/maint" ]
  run lk release build --token bogus --resource-json "$T/build.json"
  [ "$status" -eq 1 ]
  [ -e "$T/locks/build.lock" ]
  run lk maint build --token "$tok" --resource-json "$T/build.json"
  [ "$status" -eq 0 ]
  [ -e "$T/maint" ]
  run lk release build --token "$tok" --resource-json "$T/build.json"
  [ "$status" -eq 0 ]
  [ ! -e "$T/locks/build.lock" ]
}

@test "lock: watch posts edge-triggered board entries when a precondition turns false and recovers" {
  res build ", \"preconditions\": {\"check\": \"test ! -f '$T/bad'\"}"
  bash "$LOCK" watch build --interval 0.2 --mb "$BANK" --resource-json "$T/build.json" &
  PIDS+=("$!")
  sleep 0.5
  touch "$T/bad"
  wait_for 10 "grep -q 'preconditions false' '$BANK/COORDINATION.md'"
  rm "$T/bad"
  wait_for 10 "grep -q 'preconditions recovered' '$BANK/COORDINATION.md'"
  [ "$(grep -c 'resource build: preconditions' "$BANK/COORDINATION.md")" -eq 2 ]
}

@test "lock: usage errors exit 2" {
  run bash "$LOCK" run build --owner X
  [ "$status" -eq 2 ]
  run bash "$LOCK" nonsense
  [ "$status" -eq 2 ]
  res build
  run lk acquire build --owner X --resource-json "$T/build.json"
  [ "$status" -eq 2 ]
}

@test "lock: the holder's command arguments never reach meta, status or the board (secrets)" {
  res build
  bash "$LOCK" run build --mb "$BANK" --owner R --resource-json "$T/build.json" -- \
    bash -c "touch '$T/started'; sleep 30" token=SECRET-123 &
  PIDS+=("$!")
  wait_for 10 "[ -f '$T/started' ]"
  run lk status --json --resource-json "$T/build.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"cmd": "bash"'* ]] || false
  [[ "$output" != *SECRET* ]] || false
  run grep -rq SECRET "$T/locks" "$BANK/COORDINATION.md"
  [ "$status" -eq 1 ]
}
