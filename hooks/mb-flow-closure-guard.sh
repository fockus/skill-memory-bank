#!/usr/bin/env bash
# mb-flow-closure-guard.sh — Claude Code Stop-hook closure gate (dynamic-flow
# Task 6, REQ-DF-045).
#
# When a dynamic-flow is active, this hook gates "finished" on THE firewall
# (scripts/mb-flow-verify.sh — the SOLE exit-code authority, Task 5). A red
# verify physically BLOCKS the stop so the agent cannot declare done on red.
#
# CC Stop-hook contract:
#   - A JSON object arrives on STDIN (fields incl. `stop_hook_active`, `cwd`).
#   - To BLOCK the stop: print {"decision":"block","reason":"<text>"} on stdout
#     and exit 0. The host shows the reason and keeps the turn going.
#   - To ALLOW: exit 0 with NO decision (an empty/absent decision = allow).
#   - LOOP-GUARD: if `stop_hook_active` is true the host is RE-entering after a
#     prior block — we MUST allow immediately, or we wedge an infinite stop loop.
#
# Flow-active predicate (REQ-DF-045): a flow is active IFF <bank>/goal.md exists.
#   With no goal.md the gate is INERT (allow) so it never blocks unrelated stops
#   on a bank that is not running a flow.
#
# Exit-code mapping from the firewall:
#   verify exit 0 → allow (closure certified).
#   verify exit 1 → block ("a red verify"): name the red + how to repair.
#   verify exit 2 → block ("a check script broke; cannot certify closure").
#
# Fail-safe: ANY infrastructure problem (empty/garbage stdin, missing jq/python3,
# missing firewall, unreadable bank) resolves to ALLOW (exit 0). A closure gate
# must never WEDGE a session — its job is to block a *certified-red* flow, not to
# punish a broken toolchain. The firewall's own stderr is captured, never leaked
# as a hard error.
#
# Bank resolution (Defect 1 fix): uses mb_hook_resolve_mb_path from
# hooks/_skill_root.sh — the global-aware resolver (MB_PATH → <cwd>/.memory-bank
# → registry) that every other hook uses, so global-storage banks are visible.
#
# Stdin discipline (Defect 3 fix): parse success is tracked explicitly. When
# stdin is empty, non-JSON, or not a JSON object, the hook allows BEFORE
# resolving CWD/bank — it never falls back to $PWD and runs the firewall on a
# red cwd. Only a successfully-parsed JSON object can drive CWD resolution.

set -u

# Loop-guard sentinel for our own subprocess re-entry (mirrors mb-session-turn.sh).
[ -n "${MB_CAPTURE_SUBPROCESS:-}" ] && exit 0

# ---------------------------------------------------------------------------
# Allow helper — the safe default. Print nothing + exit 0.
# ---------------------------------------------------------------------------
allow() {
  exit 0
}

# Block helper — emit the CC block JSON and exit 0 (a block is still exit 0).
block() {
  local reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg r "$reason" '{decision:"block", reason:$r}'
  else
    # Bash-only fallback: hand-roll the JSON, escaping backslashes then quotes.
    local esc="$reason"
    esc="${esc//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    printf '{"decision":"block","reason":"%s"}\n' "$esc"
  fi
  exit 0
}

HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || allow

# ---------------------------------------------------------------------------
# Source the global-aware bank resolver early (Defect 1 fix).
# The functions it defines are used below in bank resolution.
# If _skill_root.sh is absent we still degrade safely via allow().
# ---------------------------------------------------------------------------
if [ -f "$HOOK_DIR/_skill_root.sh" ]; then
  # shellcheck source=hooks/_skill_root.sh
  . "$HOOK_DIR/_skill_root.sh"
fi

# ---------------------------------------------------------------------------
# Read + parse stdin (guarded). Empty / unparseable → allow IMMEDIATELY,
# before resolving CWD (Defect 3 fix: a successful parse is REQUIRED before
# any bank lookup; we must not fall back to $PWD on a parse failure).
# ---------------------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"

STOP_ACTIVE="false"
CWD=""
PARSE_OK="false"   # Defect 3: track whether stdin was a valid JSON object.

if [ -n "$INPUT" ]; then
  if command -v jq >/dev/null 2>&1; then
    # jq exits non-zero on invalid JSON. Check that the input IS a JSON object
    # before extracting fields — an invalid input must not fall through to $PWD.
    if printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
      PARSE_OK="true"
      STOP_ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
      CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
    fi
  elif command -v python3 >/dev/null 2>&1; then
    # A heredoc nested inside $(...) mis-parses on /bin/bash 3.2 (same gotcha the
    # firewall documents), so route the python output through a temp file.
    _pjson="$(mktemp 2>/dev/null || echo "/tmp/mb-closure-parse.$$")"
    MB_GUARD_INPUT="$INPUT" python3 - >"$_pjson" 2>/dev/null <<'PY' || true
import json
import os

try:
    obj = json.loads(os.environ.get("MB_GUARD_INPUT", ""))
    if not isinstance(obj, dict):
        raise ValueError
except Exception:
    # Not a JSON object — signal parse failure with a special prefix.
    print("FAIL\t")
else:
    active = "true" if obj.get("stop_hook_active") is True else "false"
    print("OK\t" + active + "\t" + (obj.get("cwd") or ""))
PY
    _parsed="$(head -n1 "$_pjson" 2>/dev/null || true)"
    rm -f "$_pjson"
    case "$_parsed" in
      OK*)
        PARSE_OK="true"
        _rest="${_parsed#OK	}"
        STOP_ACTIVE="${_rest%%	*}"
        CWD="${_rest#*	}"
        [ "$STOP_ACTIVE" = "true" ] || STOP_ACTIVE="false"
        ;;
      *)
        # FAIL or empty — parse failed; allow immediately (Defect 3).
        PARSE_OK="false"
        ;;
    esac
  fi
fi

# Defect 3: if stdin was empty or unparseable, allow immediately.
# Do NOT fall back to $PWD — that could fire the firewall on a red cwd.
[ "$PARSE_OK" = "true" ] || allow

# LOOP-GUARD: a re-entrant Stop (host already blocked once) must ALWAYS allow.
[ "$STOP_ACTIVE" = "true" ] && allow

# CWD from parsed JSON; fall back to $PWD only when the JSON had no usable cwd
# (Defect 3: the fallback now happens ONLY after a successful parse).
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"

# ---------------------------------------------------------------------------
# Resolve the bank via the global-aware resolver (Defect 1 fix).
# mb_hook_resolve_mb_path: MB_PATH → <cwd>/.memory-bank → registry lookup.
# If the resolver is available, use it; otherwise fall back to the two-step
# MB_PATH / local check (mirrors the pre-fix behavior but keeps the safe path).
# ---------------------------------------------------------------------------
BANK=""
if command -v mb_hook_resolve_mb_path >/dev/null 2>&1; then
  BANK="$(mb_hook_resolve_mb_path "$CWD" 2>/dev/null || true)"
else
  # _skill_root.sh was absent — minimal two-step fallback.
  if [ -n "${MB_PATH:-}" ]; then
    BANK="$MB_PATH"
  elif [ -d "$CWD/.memory-bank" ]; then
    BANK="$CWD/.memory-bank"
  fi
fi

# Flow-active predicate: inert unless the bank exists AND carries a goal.md.
[ -n "$BANK" ] || allow
[ -d "$BANK" ] || allow
[ -f "$BANK/goal.md" ] || allow

# ---------------------------------------------------------------------------
# Locate the firewall. The hook lives in hooks/, the firewall in scripts/ — both
# siblings under the skill root. Fall back to the shared resolver for installed
# layouts where hooks/ and scripts/ are not co-located under one parent.
# ---------------------------------------------------------------------------
VERIFY="$HOOK_DIR/../scripts/mb-flow-verify.sh"
if [ ! -f "$VERIFY" ]; then
  if command -v mb_skill_script_path >/dev/null 2>&1; then
    _resolved="$(mb_skill_script_path "mb-flow-verify.sh" "$HOOK_DIR" 2>/dev/null || true)"
    [ -n "$_resolved" ] && VERIFY="$_resolved"
  fi
fi
# Firewall missing → cannot certify; fail SAFE (allow), never wedge the session.
[ -f "$VERIFY" ] || allow

# ---------------------------------------------------------------------------
# Run the firewall ONLY for its exit code. Its stdout (the JSON summary) and
# stderr (breach lines) are both discarded here so neither leaks into the Stop
# event nor surfaces as a hard hook error — the exit code is the whole contract.
# ---------------------------------------------------------------------------
bash "$VERIFY" "$BANK" >/dev/null 2>&1
VERIFY_RC=$?

case "$VERIFY_RC" in
  0)
    allow
    ;;
  1)
    block "Dynamic-flow closure blocked: mb-flow-verify reported a red flow (verify exit 1). The flow is NOT finished — repair the breach and re-run mb-flow-verify until it exits 0 before stopping."
    ;;
  2)
    block "Dynamic-flow closure blocked: a check script broke (mb-flow-verify exit 2) — cannot certify closure. Fix the broken check, then re-run mb-flow-verify before stopping."
    ;;
  *)
    # The firewall is contracted to 0/1/2. Anything else means the firewall ITSELF
    # could not run (e.g. 127). Infrastructure fault → fail SAFE (allow).
    allow
    ;;
esac
