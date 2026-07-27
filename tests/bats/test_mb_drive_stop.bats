#!/usr/bin/env bats
# Tests for scripts/mb-drive-stop.sh — drive-loop stop telemetry + per-run
# drive state (drive-loop Task 4 — REQ-DR-033, REQ-DR-034).
#
# Contract under test:
#   - `arm` marks a drive as running (the ONLY thing that makes the Stop-hook
#     resume-gate active); without it every gate/telemetry path is inert.
#   - `record --reason <R>` writes the stop reason in THREE places, once:
#       1. the drive-state slot (status=stopped, stop_reason=R)
#       2. the `mb-flow` fence in status.md (via mb-flow-sync.sh, the fence's
#          single writer — no second fence-writing path)
#       3. progress.md (via mb-work-progress-append.sh, the append-only
#          single-writer primitive — no second append path)
#   - Closed reason vocabulary: success | human:check-broke[:<name>] |
#     human:max-cycle | human:stall | human:undecidable | budget.
#   - `--action "<mb-drive.sh action line>"` maps the decision function's
#     action grammar onto that vocabulary, so the loop never hand-rolls a
#     reason string.
#   - MB_WORK_PARALLEL=1 + --run-id keys the drive state per run (I-094 dirs);
#     two runs never contaminate each other. Unset ⇒ legacy singleton path.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-drive-stop.sh"
  BANK="$BATS_TEST_TMPDIR/bank"
  mkdir -p "$BANK"
  printf '# Status\n\nWorking.\n' > "$BANK/status.md"
  printf '# Progress\n\n' > "$BANK/progress.md"
  unset MB_WORK_PARALLEL MB_WORK_RUN_ID
}

state_field() {
  # $1 = state file, $2 = json field → prints the value ("" when absent or
  # the file is missing/corrupt; a read failure is not a test signal here).
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

@test "--help exits 0 and documents arm/record/state/path" {
  run bash "$RUN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"arm"* ]]
  [[ "$output" == *"record"* ]]
  [[ "$output" == *"state"* ]]
  [[ "$output" == *"path"* ]]
}

@test "unknown subcommand -> usage error, exit 2" {
  run bash "$RUN" bogus --bank "$BANK"
  [ "$status" -eq 2 ]
}

# ---- arm --------------------------------------------------------------------

@test "arm: creates the drive-state slot with status=driving and empty stop_reason" {
  run bash "$RUN" arm --bank "$BANK"
  [ "$status" -eq 0 ]
  [ -f "$BANK/.drive-state.json" ]
  [ "$(state_field "$BANK/.drive-state.json" status)" = "driving" ]
  [ "$(state_field "$BANK/.drive-state.json" stop_reason)" = "" ]
}

@test "state: with no slot at all degrades to {} and exit 0 (fail-safe)" {
  run bash "$RUN" state --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "state: a corrupt slot degrades to {} and exit 0 (fail-safe)" {
  printf 'not json {{{' > "$BANK/.drive-state.json"
  run bash "$RUN" state --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

# ---- record: the closed reason vocabulary -----------------------------------

@test "record: rejects a reason outside the closed vocabulary (exit 2, nothing written)" {
  bash "$RUN" arm --bank "$BANK"
  run bash "$RUN" record --bank "$BANK" --reason "because-i-said-so"
  [ "$status" -eq 2 ]
  [ "$(state_field "$BANK/.drive-state.json" status)" = "driving" ]
  run grep -c "because-i-said-so" "$BANK/progress.md"
  [ "$output" = "0" ]
}

@test "record: requires a reason or an action (exit 2)" {
  run bash "$RUN" record --bank "$BANK"
  [ "$status" -eq 2 ]
}

@test "record success: state flips to stopped with the reason" {
  bash "$RUN" arm --bank "$BANK"
  run bash "$RUN" record --bank "$BANK" --reason success
  [ "$status" -eq 0 ]
  [ "$(state_field "$BANK/.drive-state.json" status)" = "stopped" ]
  [ "$(state_field "$BANK/.drive-state.json" stop_reason)" = "success" ]
}

# ---- record: every stop branch reaches BOTH sinks ----------------------------

@test "record: every stop reason lands in the mb-flow fence AND progress.md" {
  for reason in success human:check-broke human:max-cycle human:stall budget; do
    rm -f "$BANK/.drive-state.json"
    printf '# Status\n\nWorking.\n' > "$BANK/status.md"
    printf '# Progress\n\n' > "$BANK/progress.md"
    bash "$RUN" arm --bank "$BANK"

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
  bash "$RUN" arm --bank "$BANK"
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

  bash "$RUN" arm --bank "$BANK"
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
  bash "$RUN" arm --bank "$BANK"
  bash "$RUN" record --bank "$BANK" --reason human:stall
  run grep -c "earlier entry" "$BANK/progress.md"
  [ "$output" = "1" ]
  run grep -c "human:stall" "$BANK/progress.md"
  [ "$output" = "1" ]
}

@test "record: check-broke carries the broken check name through to both sinks" {
  bash "$RUN" arm --bank "$BANK"
  run bash "$RUN" record --bank "$BANK" --reason "human:check-broke:tests"
  [ "$status" -eq 0 ]
  grep -q '^stop_reason: human:check-broke:tests$' "$BANK/status.md"
  grep -q 'human:check-broke:tests' "$BANK/progress.md"
}

@test "record: --item is recorded in the progress line when given" {
  bash "$RUN" arm --bank "$BANK"
  bash "$RUN" record --bank "$BANK" --reason human:max-cycle --item "T4"
  grep -q 'T4' "$BANK/progress.md"
}

# ---- record --action: mapping from the mb-drive.sh action grammar ------------

@test "record --action: maps every mb-drive.sh stop action onto a reason" {
  # action line (mb-drive.sh grammar) -> expected fence reason
  while IFS='|' read -r action expected; do
    [ -n "$action" ] || continue
    rm -f "$BANK/.drive-state.json"
    printf '# Status\n\nWorking.\n' > "$BANK/status.md"
    printf '# Progress\n\n' > "$BANK/progress.md"
    bash "$RUN" arm --bank "$BANK"

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
  bash "$RUN" arm --bank "$BANK"
  run bash "$RUN" record --bank "$BANK" --action "implement code-change T4"
  [ "$status" -eq 2 ]
  [ "$(state_field "$BANK/.drive-state.json" status)" = "driving" ]
}

# ---- REQ-DR-034: per-run keying under MB_WORK_PARALLEL ----------------------

@test "keying: MB_WORK_PARALLEL unset -> legacy singleton slot even with a run-id" {
  run bash "$RUN" path --bank "$BANK" --run-id run-a
  [ "$status" -eq 0 ]
  [ "$output" = "$BANK/.drive-state.json" ]
}

@test "keying: MB_WORK_PARALLEL=1 + run-id -> per-run slot under .drive-state/" {
  MB_WORK_PARALLEL=1 run bash "$RUN" path --bank "$BANK" --run-id run-a
  [ "$status" -eq 0 ]
  [ "$output" = "$BANK/.drive-state/run-a.json" ]
}

@test "keying: MB_WORK_PARALLEL=1 without a run-id -> singleton slot (no half-isolation)" {
  MB_WORK_PARALLEL=1 run bash "$RUN" path --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "$BANK/.drive-state.json" ]
}

@test "keying: two parallel runs do not contaminate each other's drive state" {
  export MB_WORK_PARALLEL=1
  bash "$RUN" arm --bank "$BANK" --run-id run-a
  bash "$RUN" arm --bank "$BANK" --run-id run-b

  # Stop ONLY run-a.
  bash "$RUN" record --bank "$BANK" --run-id run-a --reason budget

  [ "$(state_field "$BANK/.drive-state/run-a.json" status)" = "stopped" ]
  [ "$(state_field "$BANK/.drive-state/run-a.json" stop_reason)" = "budget" ]

  # run-b is untouched: still driving, no stop reason.
  [ "$(state_field "$BANK/.drive-state/run-b.json" status)" = "driving" ]
  [ "$(state_field "$BANK/.drive-state/run-b.json" stop_reason)" = "" ]

  # And the legacy singleton was never created by a parallel run.
  [ ! -f "$BANK/.drive-state.json" ]
}

@test "keying: MB_WORK_RUN_ID env is honoured like --run-id" {
  export MB_WORK_PARALLEL=1 MB_WORK_RUN_ID=run-env
  bash "$RUN" arm --bank "$BANK"
  [ -f "$BANK/.drive-state/run-env.json" ]
  run bash "$RUN" state --bank "$BANK"
  [[ "$output" == *"run-env"* ]]
}

@test "keying: a per-run stop leaves another run's state readable through --run-id" {
  export MB_WORK_PARALLEL=1
  bash "$RUN" arm --bank "$BANK" --run-id run-a
  bash "$RUN" arm --bank "$BANK" --run-id run-b
  bash "$RUN" record --bank "$BANK" --run-id run-a --reason success

  run bash "$RUN" state --bank "$BANK" --run-id run-b
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status": "driving"'* ]] || [[ "$output" == *'"status":"driving"'* ]]
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
  bash "$RUN" arm --bank "$BANK"
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
  bash "$RUN" arm --bank "$BANK"
  MB_FLOW_SYNC_BIN="$stub_dir/sync.sh" run bash "$RUN" record --bank "$BANK" --reason success
  [ "$status" -eq 0 ]
  run grep -c "stop_reason" "$BANK/status.md"
  [ "$output" = "0" ]
}

@test "record: a failing sink does not wedge the loop (fail-safe exit 0, state still stopped)" {
  stub_dir="$BATS_TEST_TMPDIR/stub3"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/boom.sh" <<'EOF'
#!/usr/bin/env bash
echo "boom" >&2
exit 7
EOF
  chmod +x "$stub_dir/boom.sh"
  bash "$RUN" arm --bank "$BANK"
  MB_FLOW_SYNC_BIN="$stub_dir/boom.sh" MB_PROGRESS_APPEND_BIN="$stub_dir/boom.sh" \
    run bash "$RUN" record --bank "$BANK" --reason success
  [ "$status" -eq 0 ]
  [ "$(state_field "$BANK/.drive-state.json" stop_reason)" = "success" ]
}
