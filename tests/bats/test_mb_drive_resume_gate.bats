#!/usr/bin/env bats
# Tests for hooks/mb-drive-resume-gate.sh — the Claude Code Stop-hook
# resume-gate for the drive loop (drive-loop Task 4 — REQ-DR-032, ADR-5).
#
# Contract (CC Stop-hook, mirrors hooks/mb-flow-closure-guard.sh):
#   - JSON object on STDIN (stop_hook_active, cwd).
#   - BLOCK: print {"decision":"block","reason":"..."} on stdout, exit 0.
#   - ALLOW: exit 0 with no decision.
#   - LOOP-GUARD: stop_hook_active==true → ALWAYS allow.
#
# Gate semantics (REQ-DR-032): block a stop when the drive loop is ARMED AND
# the goal is not done AND no stop condition has fired. Everything else allows.
#
# COST CONTRACT (backlog I-131 — the whole reason this hook is separate from
# mb-flow-closure-guard.sh): the decision is made by READING FILES ONLY.
# The hook must NEVER invoke the firewall (mb-flow-verify.sh), a test battery,
# or an LLM on the Stop path — that is what wedges a session for minutes.
# Pinned by an explicit test below.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  GATE="$REPO_ROOT/hooks/mb-drive-resume-gate.sh"
  STOP="$REPO_ROOT/scripts/mb-drive-stop.sh"

  TMPROOT="$(mktemp -d)"
  PROJECT="$TMPROOT/proj"
  BANK="$PROJECT/.memory-bank"
  mkdir -p "$BANK"
  printf '# Status\n\nWorking.\n' > "$BANK/status.md"
  printf '# Progress\n\n' > "$BANK/progress.md"
  command -v jq >/dev/null || skip "jq required"
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

run_gate() {
  local payload="$1"
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$GATE"
}

payload() {
  printf '{"cwd":"%s","stop_hook_active":%s}' "$PROJECT" "${1:-false}"
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
# Inert unless a drive is actually armed (never gate normal sessions)
# ═══════════════════════════════════════════════════════════════

@test "resume-gate: no bank -> allow" {
  rm -rf "$BANK"
  run_gate "$(payload)"
  assert_allow
}

@test "resume-gate: goal.md present but NO drive armed -> allow (inert)" {
  write_goal ' '
  run_gate "$(payload)"
  assert_allow
}

@test "resume-gate: drive armed but no goal.md -> allow" {
  bash "$STOP" arm --bank "$BANK"
  run_gate "$(payload)"
  assert_allow
}

@test "resume-gate: a drive that already stopped -> allow (stop condition recorded)" {
  write_goal ' '
  bash "$STOP" arm --bank "$BANK"
  bash "$STOP" record --bank "$BANK" --reason human:max-cycle
  run_gate "$(payload)"
  assert_allow
}

# ═══════════════════════════════════════════════════════════════
# REQ-DR-032 — the block: armed + goal not done + no stop condition
# ═══════════════════════════════════════════════════════════════

@test "resume-gate: armed + unmet acceptance + no stop condition -> BLOCK" {
  write_goal ' '
  bash "$STOP" arm --bank "$BANK"
  run_gate "$(payload)"
  assert_block
}

@test "resume-gate: the block reason names the loop and how to proceed" {
  write_goal ' '
  bash "$STOP" arm --bank "$BANK"
  run_gate "$(payload)"
  assert_block
  [[ "$output" == *"mb-drive.sh"* ]]
}

@test "resume-gate: armed + acceptance 100% -> allow (goal done)" {
  write_goal 'x'
  bash "$STOP" arm --bank "$BANK"
  run_gate "$(payload)"
  assert_allow
}

@test "resume-gate: armed + goal with zero acceptance criteria -> allow (nothing to judge)" {
  cat > "$BANK/goal.md" <<'EOF'
# Goal
No criteria section at all.
EOF
  bash "$STOP" arm --bank "$BANK"
  run_gate "$(payload)"
  assert_allow
}

@test "resume-gate: armed + max_cycles exhausted -> allow (max-cycle IS a stop condition)" {
  write_goal ' '
  bash "$STOP" arm --bank "$BANK"
  printf '{"run_id":"r","source":"s","item_no":1,"cycle":3,"max_cycles":3}\n' \
    > "$BANK/.work-state.json"
  run_gate "$(payload)"
  assert_allow
}

@test "resume-gate: armed + cycles remaining -> BLOCK (not a stop condition yet)" {
  write_goal ' '
  bash "$STOP" arm --bank "$BANK"
  printf '{"run_id":"r","source":"s","item_no":1,"cycle":1,"max_cycles":3}\n' \
    > "$BANK/.work-state.json"
  run_gate "$(payload)"
  assert_block
}

@test "resume-gate: a stop_reason in the mb-flow fence -> allow" {
  write_goal ' '
  bash "$STOP" arm --bank "$BANK"
  # Fence records a stop even if the drive-state slot were lost.
  rm -f "$BANK/.drive-state.json"
  bash "$STOP" arm --bank "$BANK"
  printf '\n<!-- mb-flow -->\nstop_reason: budget\n<!-- /mb-flow -->\n' >> "$BANK/status.md"
  run_gate "$(payload)"
  assert_allow
}

# ═══════════════════════════════════════════════════════════════
# LOOP-GUARD — a re-entrant Stop must never re-block
# ═══════════════════════════════════════════════════════════════

@test "resume-gate: stop_hook_active=true on a blockable state -> allow (loop-guard)" {
  write_goal ' '
  bash "$STOP" arm --bank "$BANK"
  run_gate "$(payload true)"
  assert_allow
}

# ═══════════════════════════════════════════════════════════════
# Fail-safe — infrastructure problems ALWAYS allow, never wedge
# ═══════════════════════════════════════════════════════════════

@test "resume-gate: empty stdin -> allow" {
  write_goal ' '
  bash "$STOP" arm --bank "$BANK"
  run_gate ""
  assert_allow
}

@test "resume-gate: garbage stdin -> allow" {
  write_goal ' '
  bash "$STOP" arm --bank "$BANK"
  run_gate "not json at all {{{"
  assert_allow
}

@test "resume-gate: a JSON array (not an object) -> allow" {
  write_goal ' '
  bash "$STOP" arm --bank "$BANK"
  run_gate '["nope"]'
  assert_allow
}

@test "resume-gate: corrupt drive-state slot -> allow (cannot prove a drive is live)" {
  write_goal ' '
  printf 'garbage{{{' > "$BANK/.drive-state.json"
  run_gate "$(payload)"
  assert_allow
}

@test "resume-gate: missing acceptance helper -> allow (fail-safe, never wedge)" {
  write_goal ' '
  bash "$STOP" arm --bank "$BANK"
  run bash -c 'printf "%s" "$1" | MB_GOAL_ACCEPTANCE_BIN=/nonexistent/nope.sh bash "$2"' \
    _ "$(payload)" "$GATE"
  assert_allow
}

@test "resume-gate: kill-switch MB_DRIVE_RESUME_GATE=off -> allow (I-131 lesson)" {
  write_goal ' '
  bash "$STOP" arm --bank "$BANK"
  run bash -c 'printf "%s" "$1" | MB_DRIVE_RESUME_GATE=off bash "$2"' _ "$(payload)" "$GATE"
  assert_allow
}

@test "resume-gate: MB_CAPTURE_SUBPROCESS sentinel -> allow (no re-entry)" {
  write_goal ' '
  bash "$STOP" arm --bank "$BANK"
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

@test "resume-gate: a blocking decision costs no firewall run (proven by a poisoned firewall)" {
  write_goal ' '
  bash "$STOP" arm --bank "$BANK"
  # Poison the firewall: if the hook ran it, this marker file would appear
  # (and the hook would hang for 30s — the exact I-131 failure mode).
  poison="$TMPROOT/firewall-was-run"
  cat > "$TMPROOT/fake-verify.sh" <<EOF
#!/usr/bin/env bash
touch "$poison"
sleep 30
EOF
  chmod +x "$TMPROOT/fake-verify.sh"
  run bash -c 'printf "%s" "$1" | MB_FLOW_VERIFY_BIN="$3" bash "$2"' \
    _ "$(payload)" "$GATE" "$TMPROOT/fake-verify.sh"
  assert_block
  [ ! -f "$poison" ]
}

# ═══════════════════════════════════════════════════════════════
# REQ-DR-034 — per-run keying: no cross-run contamination
# ═══════════════════════════════════════════════════════════════

@test "resume-gate: run-scoped — run-b still driving does not gate run-a's stop" {
  write_goal ' '
  export MB_WORK_PARALLEL=1
  bash "$STOP" arm --bank "$BANK" --run-id run-a
  bash "$STOP" arm --bank "$BANK" --run-id run-b
  bash "$STOP" record --bank "$BANK" --run-id run-a --reason success

  # The session that owns run-a stopped legitimately → allow, even though
  # run-b is still driving in another session.
  run bash -c 'printf "%s" "$1" | MB_WORK_PARALLEL=1 MB_WORK_RUN_ID=run-a bash "$2"' \
    _ "$(payload)" "$GATE"
  assert_allow
}

@test "resume-gate: run-scoped — run-b is still gated after run-a stopped" {
  write_goal ' '
  export MB_WORK_PARALLEL=1
  bash "$STOP" arm --bank "$BANK" --run-id run-a
  bash "$STOP" arm --bank "$BANK" --run-id run-b
  bash "$STOP" record --bank "$BANK" --run-id run-a --reason success

  run bash -c 'printf "%s" "$1" | MB_WORK_PARALLEL=1 MB_WORK_RUN_ID=run-b bash "$2"' \
    _ "$(payload)" "$GATE"
  assert_block
}

@test "resume-gate: run-scoped — an unknown run-id is inert (allow)" {
  write_goal ' '
  export MB_WORK_PARALLEL=1
  bash "$STOP" arm --bank "$BANK" --run-id run-a
  run bash -c 'printf "%s" "$1" | MB_WORK_PARALLEL=1 MB_WORK_RUN_ID=run-zzz bash "$2"' \
    _ "$(payload)" "$GATE"
  assert_allow
}
