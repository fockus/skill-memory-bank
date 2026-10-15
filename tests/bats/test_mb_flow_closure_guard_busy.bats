#!/usr/bin/env bats
# I-288: a red flow blocks the Stop only when nobody is working. An open /mb team
# with working tracks or a fresh /mb work run defers the block (one reminder per
# interval); once the work ends the block returns, so Ralph-loop/goal still work.
# Stub firewall (always red) as in test_mb_flow_closure_guard_cache.bats.

setup() {
  command -v jq >/dev/null || skip "jq required"
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PROJ="$(mktemp -d)"
  BANK="$PROJ/.memory-bank"
  (
    cd "$PROJ" || exit 1
    git init -q; git config user.email t@t; git config user.name t
    mkdir -p .memory-bank/tmp scripts hooks
    printf '#!/usr/bin/env bash\nexit 1\n' > scripts/mb-flow-verify.sh
    cp "$REPO_ROOT/hooks/mb-flow-closure-guard.sh" hooks/
    cp "$REPO_ROOT/scripts/mb_flow_busy.py" scripts/
    : > hooks/_skill_root.sh
    echo goal > .memory-bank/goal.md
    git add -A; git commit -qm init
  )
  STDIN="$(printf '{"stop_hook_active":false,"cwd":"%s"}' "$PROJ")"
}

teardown() { [ -n "${PROJ:-}" ] && rm -rf "$PROJ"; }

guard() { run bash -c 'printf "%s" "$1" | MB_PATH="$2" bash "$3"' _ "$STDIN" "$BANK" "$PROJ/hooks/mb-flow-closure-guard.sh"; }

team() { # $1 = track status
  mkdir -p "$BANK/reports/t1"
  printf '{"topic":"t1","closed":null,"tracks":{"A":{"status":"%s"}}}\n' "$1" > "$BANK/reports/t1/team.json"
}

work_state() { # $1 = phase, $2 = ISO updated
  printf '{"run_id":"r1","phase":"%s","updated":"%s"}\n' "$1" "$2" > "$BANK/.work-state.json"
}

now_iso() { python3 -c 'import datetime as d; print(d.datetime.now(d.timezone.utc).isoformat())'; }

@test "busy: red and nobody working blocks" {
  guard
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
}

@test "busy: red with a dispatched team track defers, reminds once, then stays silent" {
  team dispatched
  guard
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .decision)" = "null" ]
  [[ "$(printf '%s' "$output" | jq -r .systemMessage)" == *"t1/A"* ]]
  guard
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "busy: block returns once the team track is done" {
  team dispatched
  guard
  [ "$(printf '%s' "$output" | jq -r .decision)" = "null" ]
  team "done"
  guard
  [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
}

@test "busy: fresh in-progress work run defers; finished or stale run blocks" {
  work_state in-progress "$(now_iso)"
  guard
  [ "$(printf '%s' "$output" | jq -r .decision)" = "null" ]
  work_state "done" "$(now_iso)"
  guard
  [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
  work_state in-progress "2020-01-01T00:00:00+00:00"
  guard
  [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
}

@test "busy: max-age 0 in .mb-config disables deferral; remind 0 is silent" {
  team reviewing
  echo "flow_closure_busy_max_age=0" > "$BANK/.mb-config"
  guard
  [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
  echo "flow_closure_remind=0" > "$BANK/.mb-config"
  guard
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
