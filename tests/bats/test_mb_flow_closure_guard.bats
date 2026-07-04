#!/usr/bin/env bats
# Tests for hooks/mb-flow-closure-guard.sh — the Claude Code Stop-hook closure
# gate (dynamic-flow Task 6, REQ-DF-045).
#
# Contract (CC Stop-hook):
#   - Receives a JSON object on STDIN (fields incl. stop_hook_active, cwd).
#   - To BLOCK the stop: print {"decision":"block","reason":"..."} on stdout, exit 0.
#   - To ALLOW: exit 0 with no decision (or {"decision":"approve"}).
#   - LOOP-GUARD: if stop_hook_active==true → ALWAYS allow (never re-block).
#
# Closure semantics (the firewall is the SOLE exit authority — Task 5):
#   - Flow is active IFF <bank>/goal.md exists. No goal.md → INERT (allow).
#   - goal.md present → run scripts/mb-flow-verify.sh <bank>:
#       exit 0 → allow.  exit 1 → block (red verify).  exit 2 → block (broke).
#   - Robust: empty / garbage stdin → allow (never wedge a session).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  GUARD="$REPO_ROOT/hooks/mb-flow-closure-guard.sh"

  TMPROOT="$(mktemp -d)"
  PROJECT="$TMPROOT/proj"
  BANK="$PROJECT/.memory-bank"
  mkdir -p "$BANK"
  git -C "$PROJECT" init -q
  git -C "$PROJECT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  command -v jq >/dev/null || skip "jq required"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# Author a goal.md whose single acceptance criterion is met (- [x]) or unmet (- [ ]).
# Then commit so the firewall's git-scoped default checks see a clean tree.
write_goal() {
  local box="$1"  # 'x' (met → firewall exit 0) | ' ' (unmet → firewall exit 1)
  cat > "$BANK/goal.md" <<EOF
# Goal
Ship it.

## Acceptance criteria

- [$box] the only criterion
EOF
  git -C "$PROJECT" -c user.email=t@t -c user.name=t add -A
  git -C "$PROJECT" -c user.email=t@t -c user.name=t commit -q -m goal
}

# Run the guard feeding STDIN, capturing stdout+status. $1=stdin payload.
run_guard() {
  local payload="$1"
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$GUARD"
}

# ═══════════════════════════════════════════════════════════════
# Existence
# ═══════════════════════════════════════════════════════════════

@test "closure-guard: script exists and is executable" {
  [ -f "$GUARD" ]
  [ -x "$GUARD" ]
}

# ═══════════════════════════════════════════════════════════════
# Inert when no flow is active (no goal.md)
# ═══════════════════════════════════════════════════════════════

@test "closure-guard: no goal.md → allow (exit 0, no block decision)" {
  run_guard "$(printf '{"cwd":"%s","stop_hook_active":false}' "$PROJECT")"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision":"block"'* ]]
}

@test "closure-guard: no .memory-bank at all → allow (exit 0)" {
  rm -rf "$BANK"
  run_guard "$(printf '{"cwd":"%s","stop_hook_active":false}' "$PROJECT")"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision":"block"'* ]]
}

# ═══════════════════════════════════════════════════════════════
# Loop-guard — stop_hook_active dominates even a red flow
# ═══════════════════════════════════════════════════════════════

@test "closure-guard: stop_hook_active=true with a RED flow → allow (loop-guard)" {
  write_goal ' '   # unmet → firewall would exit 1
  run_guard "$(printf '{"cwd":"%s","stop_hook_active":true}' "$PROJECT")"
  [ "$status" -eq 0 ]
  # Must NOT re-block: that would cause an infinite stop loop.
  [[ "$output" != *'"decision":"block"'* ]]
}

# ═══════════════════════════════════════════════════════════════
# The gate proper — block on red, allow on green
# ═══════════════════════════════════════════════════════════════

@test "closure-guard: goal.md + RED verify (unmet acceptance) → block" {
  write_goal ' '
  run_guard "$(printf '{"cwd":"%s","stop_hook_active":false}' "$PROJECT")"
  [ "$status" -eq 0 ]   # CC contract: a block is still exit 0
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *'mb-flow-verify'* ]]
}

@test "closure-guard: goal.md + GREEN verify (met acceptance) → allow" {
  write_goal 'x'
  run_guard "$(printf '{"cwd":"%s","stop_hook_active":false}' "$PROJECT")"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision":"block"'* ]]
}

@test "closure-guard: block reason is valid JSON carrying decision+reason" {
  write_goal ' '
  run_guard "$(printf '{"cwd":"%s","stop_hook_active":false}' "$PROJECT")"
  [ "$status" -eq 0 ]
  # The whole stdout must be a JSON object the host can parse.
  echo "$output" | jq -e '.decision == "block"' >/dev/null
  echo "$output" | jq -e '.reason | length > 0' >/dev/null
}

# ═══════════════════════════════════════════════════════════════
# Robustness — never wedge a session on bad input
# ═══════════════════════════════════════════════════════════════

@test "closure-guard: empty stdin → allow (no wedge)" {
  run_guard ""
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision":"block"'* ]]
}

@test "closure-guard: garbage (non-JSON) stdin → allow (no wedge)" {
  run_guard "this is not json at all <<<"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision":"block"'* ]]
}

@test "closure-guard: missing cwd falls back to PWD; no flow there → allow" {
  # cd into a clean non-flow dir; empty JSON object means no cwd field.
  run bash -c 'cd "$1" && printf "%s" "{}" | bash "$2"' _ "$TMPROOT" "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision":"block"'* ]]
}

# ═══════════════════════════════════════════════════════════════
# MB_PATH override (global-storage bank away from cwd)
# ═══════════════════════════════════════════════════════════════

@test "closure-guard: MB_PATH override points the gate at an external bank" {
  write_goal ' '   # red flow in $BANK
  # cwd is a clean dir with no goal.md; MB_PATH retargets the gate at the red bank.
  run bash -c 'cd "$1" && printf "%s" "{}" | MB_PATH="$2" bash "$3"' _ "$TMPROOT" "$BANK" "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]]
}

# ═══════════════════════════════════════════════════════════════
# Defect 3 fix — garbage/empty stdin while current dir IS a red flow
# ═══════════════════════════════════════════════════════════════

@test "closure-guard: garbage stdin while PWD is a red flow bank → ALLOW (no block)" {
  # Defect 3: when stdin is empty/non-JSON the guard must allow BEFORE resolving
  # CWD. If CWD/PWD falls back to an active red-flow project the old code would
  # run the firewall and block — contradicting "garbage stdin → allow".
  write_goal ' '   # red flow in $BANK (PROJECT/.memory-bank)
  # Run the guard with its cwd set to PROJECT (where the red bank lives) but
  # feed garbage stdin so the JSON parse fails → must allow unconditionally.
  run bash -c 'cd "$1" && printf "%s" "not json at all" | bash "$2"' _ "$PROJECT" "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision":"block"'* ]]
}

@test "closure-guard: empty stdin while PWD is a red flow bank → ALLOW (no block)" {
  write_goal ' '
  run bash -c 'cd "$1" && printf "" | bash "$2"' _ "$PROJECT" "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision":"block"'* ]]
}

# ═══════════════════════════════════════════════════════════════
# Defect 1 fix — global/registry-resolved red bank (no local .memory-bank)
# ═══════════════════════════════════════════════════════════════

@test "closure-guard: global-registry bank via MB_PATH (no local .memory-bank) RED flow → block" {
  # Defect 1 — MB_PATH variant: a project with global storage sets MB_PATH to
  # the external bank; no local .memory-bank. The guard must resolve the bank
  # via MB_PATH, not assume <cwd>/.memory-bank.

  # Create an external bank (simulates a global-storage bank path) with a red flow.
  local ext_bank="$TMPROOT/global_bank/.memory-bank"
  mkdir -p "$ext_bank"
  git -C "$TMPROOT/global_bank" init -q
  git -C "$TMPROOT/global_bank" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  cat > "$ext_bank/goal.md" <<'EOF'
# Goal
Ship it.

## Acceptance criteria

- [ ] pending criterion
EOF
  git -C "$TMPROOT/global_bank" -c user.email=t@t -c user.name=t add -A
  git -C "$TMPROOT/global_bank" -c user.email=t@t -c user.name=t commit -q -m goal

  # Project dir has NO local .memory-bank — simulates a global-storage project.
  local project_no_local="$TMPROOT/no_local_bank"
  mkdir -p "$project_no_local"

  # Guard runs from the no-local-bank project dir with MB_PATH pointing to the
  # global bank. The gate must resolve via MB_PATH and block on the red flow.
  run bash -c 'cd "$1" && printf "%s" "{}" | MB_PATH="$2" bash "$3"' \
    _ "$project_no_local" "$ext_bank" "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "closure-guard: registry-only bank (no MB_PATH, no local .memory-bank) RED flow → block" {
  # Defect 1 — registry variant: the old code had no registry lookup at all.
  # mb_hook_resolve_mb_path does MB_PATH → <cwd>/.memory-bank → registry.
  # This test exercises the registry path by setting MB_AGENT + a real registry.
  command -v python3 >/dev/null 2>&1 || skip "python3 required for registry setup"

  local ext_bank="$TMPROOT/reg_bank/.memory-bank"
  mkdir -p "$ext_bank"
  git -C "$TMPROOT/reg_bank" init -q
  git -C "$TMPROOT/reg_bank" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  cat > "$ext_bank/goal.md" <<'EOF'
# Goal

## Acceptance criteria

- [ ] pending
EOF
  git -C "$TMPROOT/reg_bank" -c user.email=t@t -c user.name=t add -A
  git -C "$TMPROOT/reg_bank" -c user.email=t@t -c user.name=t commit -q -m goal

  # Project dir that will be the cwd for the guard — no local .memory-bank.
  local prj="$TMPROOT/reg_project"
  mkdir -p "$prj"

  # Build a registry pointing prj → ext_bank under a sandboxed HOME.
  local fake_home="$TMPROOT/fake_home"
  mkdir -p "$fake_home/.claude/memory-bank"
  local registry="$fake_home/.claude/memory-bank/registry.json"
  local real_prj
  real_prj="$(cd "$prj" && pwd -P)"
  python3 - "$registry" "$real_prj" "$ext_bank" <<'PY'
import json, sys
path, project, bank = sys.argv[1], sys.argv[2], sys.argv[3]
data = {"projects": {project: {"bank_path": bank}}}
with open(path, "w") as f:
    json.dump(data, f)
PY

  # Run guard: cwd=prj, no local .memory-bank, no MB_PATH, but registry + MB_AGENT set.
  # MB_SKILL_ROOT lets mb_hook_resolve_mb_path find _lib.sh in our repo.
  run bash -c 'cd "$1" && printf "%s" "{}" | HOME="$2" MB_AGENT=claude-code MB_SKILL_ROOT="$3" bash "$4"' \
    _ "$prj" "$fake_home" "$REPO_ROOT" "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]]
}

# ═══════════════════════════════════════════════════════════════
# Registration — the Stop array must reference the guard
# ═══════════════════════════════════════════════════════════════

@test "closure-guard: settings/hooks.json is valid JSON and registers the guard in Stop" {
  local hooks="$REPO_ROOT/settings/hooks.json"
  [ -f "$hooks" ]
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$hooks"
  # The guard must appear as a Stop hook command.
  python3 - "$hooks" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
cmds = [h.get("command", "") for entry in data.get("Stop", []) for h in entry.get("hooks", [])]
guard_cmds = [c for c in cmds if "mb-flow-closure-guard.sh" in c]
assert guard_cmds, "guard not registered in Stop"
# This is the Claude Code hooks file: the guard must pin MB_AGENT=claude-code so
# global/registry bank resolution is deterministic even when ~/.cursor/skills/
# memory-bank exists (mb_hook_default_agent would otherwise guess 'cursor').
assert all("MB_AGENT=claude-code" in c for c in guard_cmds), \
    "guard registration must pin MB_AGENT=claude-code"
# The two pre-existing Stop hooks must survive. The session-turn capture hook is
# unchanged; the old unconditional "/mb done" recommendation echo was intentionally
# replaced (I-087 B1) by the drift-gated mb-freshness.sh --stop-nudge (silent when the
# bank is fresh), so pin the new wiring instead of the retired literal text.
joined = "\n".join(cmds)
assert "mb-session-turn.sh" in joined, "mb-session-turn.sh removed"
assert "mb-freshness.sh" in joined, "the drift-gated Stop nudge (mb-freshness.sh) removed"
PY
}
