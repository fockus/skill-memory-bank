#!/usr/bin/env bats
# Tests for scripts/mb-drive-stop.sh — drive stop telemetry on the drive run
# files <bank>/.drive/<run_id>.json (drive-autopilot design C4).
#
# Contract under test:
#   - `record --reason <R>` writes the stop in three places, once:
#       1. the selected run file (phase=stopped, stop_reason=R)
#       2. the `mb-flow` fence in status.md (via mb-flow-sync.sh, the fence's
#          single writer — no second fence-writing path)
#       3. progress.md (via mb-work-progress-append.sh, the append-only
#          single-writer primitive — no second append path)
#   - Closed reason vocabulary; `--action "<mb-drive.sh action line>"` maps
#     the decision function's action grammar onto it.
#   - Two runs never contaminate each other's run file.
#   - New-vocabulary and gate cases live in test_drive_stop_gate.bats.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-drive-stop.sh"
  BANK="$BATS_TEST_TMPDIR/bank"
  mkdir -p "$BANK/.drive"
  printf '# Status\n\nWorking.\n' > "$BANK/status.md"
  printf '# Progress\n\n' > "$BANK/progress.md"
  unset MB_WORK_PARALLEL MB_WORK_RUN_ID
}

# write_run [run_id] — a live execution-phase run file.
write_run() {
  printf '{"run_id":"%s","bank":"%s","goal":"%s/goal.md","session":null,"phase":"execution","stop_reason":""}\n' \
    "${1:-R1}" "$BANK" "$BANK" > "$BANK/.drive/${1:-R1}.json"
}

state_field() {
  # $1 = run file, $2 = field → its value ("" when absent or unreadable).
  python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    d = {}
v = d.get(sys.argv[2], "")
print(v if isinstance(v, str) else json.dumps(v))
' "$1" "$2"
}

# ---- basics -----------------------------------------------------------------

@test "mb-drive-stop.sh: script exists and is executable" {
  [ -f "$RUN" ]
  [ -x "$RUN" ]
}

@test "--help exits 0 and documents record/state/path" {
  run bash "$RUN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"record"* ]]
  [[ "$output" == *"state"* ]]
  [[ "$output" == *"path"* ]]
}

@test "unknown subcommand -> usage error, exit 2" {
  run bash "$RUN" bogus --bank "$BANK"
  [ "$status" -eq 2 ]
}

# ---- state ------------------------------------------------------------------

@test "state: no live run -> exit 1" {
  run bash "$RUN" state --bank "$BANK"
  [ "$status" -eq 1 ]
}

@test "state: a corrupt run file degrades to {} and exit 0 (fail-safe)" {
  printf 'not json {{{' > "$BANK/.drive/R1.json"
  run bash "$RUN" state --bank "$BANK" --run-id R1
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

# ---- record: the closed reason vocabulary -----------------------------------

@test "record: rejects a reason outside the closed vocabulary (exit 2, nothing written)" {
  write_run
  run bash "$RUN" record --bank "$BANK" --reason "because-i-said-so"
  [ "$status" -eq 2 ]
  [ "$(state_field "$BANK/.drive/R1.json" phase)" = "execution" ]
  run grep -c "because-i-said-so" "$BANK/progress.md"
  [ "$output" = "0" ]
}

@test "record: requires a reason or an action (exit 2)" {
  run bash "$RUN" record --bank "$BANK"
  [ "$status" -eq 2 ]
}

@test "record success: the run file flips to stopped with the reason" {
  write_run
  run bash "$RUN" record --bank "$BANK" --reason success
  [ "$status" -eq 0 ]
  [ "$(state_field "$BANK/.drive/R1.json" phase)" = "stopped" ]
  [ "$(state_field "$BANK/.drive/R1.json" stop_reason)" = "success" ]
}

# ---- record: every stop branch reaches BOTH sinks ----------------------------

@test "record: every stop reason lands in the mb-flow fence AND progress.md" {
  for reason in success human:check-broke human:max-cycle human:stall budget; do
    rm -f "$BANK/.drive/R1.json"
    printf '# Status\n\nWorking.\n' > "$BANK/status.md"
    printf '# Progress\n\n' > "$BANK/progress.md"
    write_run

    run bash "$RUN" record --bank "$BANK" --reason "$reason"
    [ "$status" -eq 0 ]

    # 1. fence — one line, inside the mb-flow fence
    run grep -c "^stop_reason: $reason\$" "$BANK/status.md"
    [ "$output" = "1" ]
    run grep -c '<!-- mb-flow -->' "$BANK/status.md"
    [ "$output" = "1" ]

    # 2. progress.md — appended, exactly once
    run grep -c "$reason" "$BANK/progress.md"
    [ "$output" = "1" ]
  done
}

@test "record: the stop line is written INSIDE the mb-flow fence" {
  write_run
  bash "$RUN" record --bank "$BANK" --reason budget
  open_ln=$(grep -n '<!-- mb-flow -->' "$BANK/status.md" | cut -d: -f1)
  stop_ln=$(grep -n '^stop_reason: budget$' "$BANK/status.md" | cut -d: -f1)
  close_ln=$(grep -n '<!-- /mb-flow -->' "$BANK/status.md" | cut -d: -f1)
  [ "$open_ln" -lt "$stop_ln" ]
  [ "$stop_ln" -lt "$close_ln" ]
}

@test "record: a stop preserves every other mb-flow field (partial write must not wipe)" {
  # FIX-CYCLE2 FIX-1: `record` calls the fence writer with ONLY --stop-reason.
  # A live drive has route/phase/phases/checks/gate/last_verify_sha/stall_count
  # already in the fence; recording the stop must not blank them, or the fence
  # loses exactly the context that explains WHY the loop stopped.
  local sync="$REPO_ROOT/scripts/mb-flow-sync.sh"
  bash "$sync" "$BANK" \
    --route code-change --phase 2/4 --phases "plan,implement,verify" \
    --checks '{"tests":"pass","rules":"pass","lint":"skip","build":"skip","mb_updated":"pass","no_todo":"pass","diff_scope":"pass","acceptance":"fail"}' \
    --gate FAIL --last-verify-sha abc1234 --stall-count 2

  before="$(sed -n '/<!-- mb-flow -->/,/<!-- \/mb-flow -->/p' "$BANK/status.md" |
    grep -v '^stop_reason:')"

  write_run
  run bash "$RUN" record --bank "$BANK" --reason success
  [ "$status" -eq 0 ]

  after="$(sed -n '/<!-- mb-flow -->/,/<!-- \/mb-flow -->/p' "$BANK/status.md" |
    grep -v '^stop_reason:')"

  # Every non-stop_reason line is byte-identical...
  [ "$before" = "$after" ]
  # ...and the individual fields are genuinely still there (not all blanked to `-`).
  grep -q '^route: code-change$' "$BANK/status.md"
  grep -q '^current_phase: 2/4$' "$BANK/status.md"
  grep -q '^phases: \[plan, implement, verify\]$' "$BANK/status.md"
  grep -q '^gate: FAIL$' "$BANK/status.md"
  grep -q '^last_verify_sha: abc1234$' "$BANK/status.md"
  grep -q '^stall_count: 2$' "$BANK/status.md"
  grep -q 'acceptance: fail' "$BANK/status.md"
  # ...while the stop reason itself IS updated.
  grep -q '^stop_reason: success$' "$BANK/status.md"
}

@test "record: progress append is append-only (pre-existing content survives)" {
  printf '# Progress\n\n- earlier entry\n' > "$BANK/progress.md"
  write_run
  bash "$RUN" record --bank "$BANK" --reason human:stall
  run grep -c "earlier entry" "$BANK/progress.md"
  [ "$output" = "1" ]
  run grep -c "human:stall" "$BANK/progress.md"
  [ "$output" = "1" ]
}

@test "record: check-broke carries the broken check name through to both sinks" {
  write_run
  run bash "$RUN" record --bank "$BANK" --reason "human:check-broke:tests"
  [ "$status" -eq 0 ]
  grep -q '^stop_reason: human:check-broke:tests$' "$BANK/status.md"
  grep -q 'human:check-broke:tests' "$BANK/progress.md"
}

@test "record: --item is recorded in the progress line when given" {
  write_run
  bash "$RUN" record --bank "$BANK" --reason human:max-cycle --item "T4"
  grep -q 'T4' "$BANK/progress.md"
}

# ---- record --action: mapping from the mb-drive.sh action grammar ------------

@test "record --action: maps every mb-drive.sh stop action onto a reason" {
  # action line (mb-drive.sh grammar) -> expected fence reason
  while IFS='|' read -r action expected; do
    [ -n "$action" ] || continue
    rm -f "$BANK/.drive/R1.json"
    printf '# Status\n\nWorking.\n' > "$BANK/status.md"
    printf '# Progress\n\n' > "$BANK/progress.md"
    write_run

    run bash "$RUN" record --bank "$BANK" --action "$action"
    [ "$status" -eq 0 ]
    grep -q "^stop_reason: $expected\$" "$BANK/status.md"
  done <<'EOF'
stop_success|success
stop_budget|budget
stop_human max-cycle|human:max-cycle
stop_human stall|human:stall
stop_human undecidable|human:undecidable
stop_human check-broke:tests|human:check-broke:tests
EOF
}

@test "record --action: a non-stop action is refused (exit 2) — only stops are telemetry" {
  write_run
  run bash "$RUN" record --bank "$BANK" --action "implement code-change T4"
  [ "$status" -eq 2 ]
  [ "$(state_field "$BANK/.drive/R1.json" phase)" = "execution" ]
}

# ---- per-run isolation --------------------------------------------------------

@test "isolation: stopping one run leaves another run's file live" {
  write_run run-a
  write_run run-b
  bash "$RUN" record --bank "$BANK" --run-id run-a --reason budget
  [ "$(state_field "$BANK/.drive/run-a.json" phase)" = "stopped" ]
  [ "$(state_field "$BANK/.drive/run-a.json" stop_reason)" = "budget" ]
  [ "$(state_field "$BANK/.drive/run-b.json" phase)" = "execution" ]
  [ "$(state_field "$BANK/.drive/run-b.json" stop_reason)" = "" ]
}

@test "isolation: MB_WORK_RUN_ID does not select the run" {
  write_run run-a
  write_run run-b
  MB_WORK_RUN_ID=run-a run bash "$RUN" record --bank "$BANK" --reason success
  [ "$status" -eq 2 ]
  [ "$(state_field "$BANK/.drive/run-a.json" phase)" = "execution" ]
}

@test "isolation: several live runs without --run-id are listed, not swallowed" {
  write_run run-a
  write_run run-b
  for sub in record state path; do
    run bash "$RUN" "$sub" --bank "$BANK" --reason budget
    [ "$status" -eq 2 ]
    [[ "$output" == *"run-a"* && "$output" == *"run-b"* ]]
  done
}

# ---- reuse discipline (no second write path) --------------------------------

@test "reuse: progress append goes through mb-work-progress-append.sh only" {
  # The helper must not hand-roll an append; it must call the single-writer
  # primitive. Proven by making that primitive the only thing that can write:
  # if the helper appended directly, the reason would appear even with the
  # primitive stubbed out to a no-op.
  stub_dir="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/append.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$stub_dir/append.sh"
  write_run
  MB_PROGRESS_APPEND_BIN="$stub_dir/append.sh" run bash "$RUN" record --bank "$BANK" --reason success
  [ "$status" -eq 0 ]
  run grep -c "success" "$BANK/progress.md"
  [ "$output" = "0" ]
}

@test "reuse: fence write goes through mb-flow-sync.sh only" {
  stub_dir="$BATS_TEST_TMPDIR/stub2"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/sync.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$stub_dir/sync.sh"
  write_run
  MB_FLOW_SYNC_BIN="$stub_dir/sync.sh" run bash "$RUN" record --bank "$BANK" --reason success
  [ "$status" -eq 0 ]
  run grep -c "stop_reason" "$BANK/status.md"
  [ "$output" = "0" ]
}

@test "record: a failing sink does not wedge the loop (fail-safe exit 0, run still stopped)" {
  stub_dir="$BATS_TEST_TMPDIR/stub3"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/boom.sh" <<'EOF'
#!/usr/bin/env bash
echo "boom" >&2
exit 7
EOF
  chmod +x "$stub_dir/boom.sh"
  write_run
  MB_FLOW_SYNC_BIN="$stub_dir/boom.sh" MB_PROGRESS_APPEND_BIN="$stub_dir/boom.sh" \
    run bash "$RUN" record --bank "$BANK" --reason success
  [ "$status" -eq 0 ]
  [ "$(state_field "$BANK/.drive/R1.json" stop_reason)" = "success" ]
}
