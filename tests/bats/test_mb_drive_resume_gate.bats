#!/usr/bin/env bats
# Tests for hooks/mb-drive-resume-gate.sh — the Stop-hook resume gate for
# `/mb drive` on the drive run files (drive-autopilot design C4, REQ-045).
#
# Stop-hook contract: JSON object on STDIN (stop_hook_active, cwd,
# session_id); BLOCK prints {"decision":"block",...} and exits 0; ALLOW exits
# 0 with no decision; stop_hook_active==true always allows.
#
# COST CONTRACT (backlog I-131): the decision reads files only — never the
# firewall (mb-flow-verify.sh), a test battery or an LLM. Session matching,
# the several-runs warning and the poisoned check/firewall cases live in
# test_drive_stop_gate.bats.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  GATE="$REPO_ROOT/hooks/mb-drive-resume-gate.sh"
  STOP="$REPO_ROOT/scripts/mb-drive-stop.sh"

  TMPROOT="$(mktemp -d)"
  PROJECT="$TMPROOT/proj"
  BANK="$PROJECT/.memory-bank"
  mkdir -p "$BANK/.drive"
  printf '# Status\n\nWorking.\n' > "$BANK/status.md"
  printf '# Progress\n\n' > "$BANK/progress.md"
  unset MB_WORK_PARALLEL MB_WORK_RUN_ID MB_DRIVE_RESUME_GATE
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# goal.md with one acceptance criterion: met ('x') or unmet (' ').
write_goal() {
  local box="$1"
  cat > "$BANK/goal.md" <<EOF
---
id: G-TEST
status: active
---

# Goal
Ship it.

## Acceptance criteria

- [$box] the only criterion
EOF
}

# write_run <phase> — run R1 of session S1 driving $BANK/goal.md.
write_run() {
  printf '{"run_id":"R1","bank":"%s","goal":"%s/goal.md","session":"S1","phase":"%s","stop_reason":""}\n' \
    "$BANK" "$BANK" "$1" > "$BANK/.drive/R1.json"
}

run_gate() {
  local payload="$1"
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$GATE"
}

payload() {
  printf '{"cwd":"%s","session_id":"S1","stop_hook_active":%s}' "$PROJECT" "${1:-false}"
}

assert_allow() {
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision":"block"'* ]]
}

assert_block() {
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]]
}

# ═══════════════════════════════════════════════════════════════
# Existence
# ═══════════════════════════════════════════════════════════════

@test "resume-gate: script exists and is executable" {
  [ -f "$GATE" ]
  [ -x "$GATE" ]
}

# ═══════════════════════════════════════════════════════════════
# Inert unless a run is executing (never gate normal sessions)
# ═══════════════════════════════════════════════════════════════

@test "resume-gate: no bank -> allow" {
  rm -rf "$BANK"
  run_gate "$(payload)"
  assert_allow
}

@test "resume-gate: goal.md present but no run file -> allow (inert)" {
  write_goal ' '
  run_gate "$(payload)"
  assert_allow
}

@test "resume-gate: a run that recorded a stop -> allow (stop condition recorded)" {
  write_goal ' '
  write_run execution
  bash "$STOP" record --bank "$BANK" --run-id R1 --reason human:stall
  run_gate "$(payload)"
  assert_allow
}

# ═══════════════════════════════════════════════════════════════
# REQ-045 — the block: execution phase + goal not met
# ═══════════════════════════════════════════════════════════════

@test "resume-gate: execution + unmet goal -> BLOCK" {
  write_goal ' '
  write_run execution
  run_gate "$(payload)"
  assert_block
}

@test "resume-gate: the block reason names the run and how to proceed" {
  write_goal ' '
  write_run execution
  run_gate "$(payload)"
  assert_block
  [[ "$output" == *"mb-drive.sh"* && "$output" == *"R1"* ]]
}

@test "resume-gate: execution + acceptance 100% -> allow (goal done)" {
  write_goal 'x'
  write_run execution
  run_gate "$(payload)"
  assert_allow
}

@test "resume-gate: execution + goal with zero acceptance criteria -> allow (nothing to judge)" {
  cat > "$BANK/goal.md" <<'EOF'
# Goal
No criteria section at all.
EOF
  write_run execution
  run_gate "$(payload)"
  assert_allow
}

# ═══════════════════════════════════════════════════════════════
# LOOP-GUARD — a re-entrant Stop must never re-block
# ═══════════════════════════════════════════════════════════════

@test "resume-gate: stop_hook_active=true on a blockable state -> allow (loop-guard)" {
  write_goal ' '
  write_run execution
  run_gate "$(payload true)"
  assert_allow
}

# ═══════════════════════════════════════════════════════════════
# Fail-safe — infrastructure problems ALWAYS allow, never wedge
# ═══════════════════════════════════════════════════════════════

@test "resume-gate: empty stdin -> allow" {
  write_goal ' '
  write_run execution
  run_gate ""
  assert_allow
}

@test "resume-gate: garbage stdin -> allow" {
  write_goal ' '
  write_run execution
  run_gate "not json at all {{{"
  assert_allow
}

@test "resume-gate: a JSON array (not an object) -> allow" {
  write_goal ' '
  write_run execution
  run_gate '["nope"]'
  assert_allow
}

@test "resume-gate: corrupt run file -> allow (cannot prove a drive is live)" {
  write_goal ' '
  printf 'garbage{{{' > "$BANK/.drive/R1.json"
  run_gate "$(payload)"
  assert_allow
}

@test "resume-gate: missing acceptance helper -> allow (fail-safe, never wedge)" {
  write_goal ' '
  write_run execution
  run bash -c 'printf "%s" "$1" | MB_GOAL_ACCEPTANCE_BIN=/nonexistent/nope.sh bash "$2"' \
    _ "$(payload)" "$GATE"
  assert_allow
}

@test "resume-gate: kill-switch MB_DRIVE_RESUME_GATE=off -> allow (I-131 lesson)" {
  write_goal ' '
  write_run execution
  run bash -c 'printf "%s" "$1" | MB_DRIVE_RESUME_GATE=off bash "$2"' _ "$(payload)" "$GATE"
  assert_allow
}

@test "resume-gate: MB_CAPTURE_SUBPROCESS sentinel -> allow (no re-entry)" {
  write_goal ' '
  write_run execution
  run bash -c 'printf "%s" "$1" | MB_CAPTURE_SUBPROCESS=1 bash "$2"' _ "$(payload)" "$GATE"
  assert_allow
}

# ═══════════════════════════════════════════════════════════════
# COST CONTRACT (I-131) — file reads only, never the firewall
# ═══════════════════════════════════════════════════════════════

@test "resume-gate: executable source NEVER references the firewall or a test battery" {
  # Comments MUST discuss the firewall (that is the whole cost rationale), so
  # strip comment/blank lines and assert the CODE is clean.
  code="$(grep -vE '^[[:space:]]*(#|$)' "$GATE")"
  run bash -c 'printf "%s" "$1" | grep -cE "mb-flow-verify|mb-test-run|pytest|bats"' _ "$code"
  [ "$output" = "0" ]
}
