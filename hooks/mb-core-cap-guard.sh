#!/usr/bin/env bash
# mb-core-cap-guard.sh — Stop hook enforcing the core-file line caps (AGR-043).
#
# `status.md` = the current state, `checklist.md` = the plans in flight. Both
# carry a hard line cap; everything else belongs in `progress.md`. A cap that
# is only a sentence in a file header is a convention nobody runs, so this hook
# makes it a gate: on every Stop it runs `scripts/mb-core-cap.sh fix`
# (rotation + v2 compaction, both append-only and verified) and, when the bank
# is STILL over cap, blocks the stop ONCE per session with the repair command.
#
# CC Stop-hook contract:
#   - JSON object on STDIN (`session_id`, `cwd`, `stop_hook_active`).
#   - BLOCK: print {"decision":"block","reason":"<text>"} on stdout, exit 0.
#   - ALLOW: exit 0 with no output.
#   - LOOP-GUARD: `stop_hook_active: true` means the host re-entered after a
#     block — always allow, or the session wedges in a stop loop.
#
# One block per session: the marker `<bank>/.core-cap.nudged.<session_id>` is
# written with the block, and its presence allows every later Stop of that
# session. The nudge is a signal to the orchestrator, never a wall.
#
# ON BY DEFAULT — a deliberate departure from the "opt-in" default of the other
# MB layers, decided by the owner (AGR-043): a cap enforced only when someone
# remembers to enable it is the state this hook exists to end. Kill-switch:
# `MB_CORE_CAP=off` (env) or `core_cap=off` in `<bank>/.mb-config`.
#
# Fail-open everywhere except the cap itself: unparseable stdin, no bank, no
# python3, a missing/erroring mb-core-cap.sh (exit 2) → allow. Replaces the
# opt-in SessionEnd hook `mb-checklist-autoprune.sh`.

set -u

[ -n "${MB_CAPTURE_SUBPROCESS:-}" ] && exit 0
case "${MB_CORE_CAP:-on}" in
  off|OFF|0|false|FALSE|no|NO) exit 0 ;;
esac

allow() { exit 0; }

block() {
  local reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg r "$reason" '{decision:"block", reason:$r}'
  else
    local esc="$reason"
    esc="${esc//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    printf '{"decision":"block","reason":"%s"}\n' "$esc"
  fi
  exit 0
}

HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || allow
if [ -f "$HOOK_DIR/_skill_root.sh" ]; then
  # shellcheck source=hooks/_skill_root.sh
  . "$HOOK_DIR/_skill_root.sh"
fi

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || allow

# stdin parse: jq when available, python3 otherwise. A parse failure allows
# BEFORE any path resolution — a broken payload must never drive a decision
# off $PWD.
SESSION_ID=""
CWD=""
STOP_ACTIVE="false"
PARSE_OK="false"
if command -v jq >/dev/null 2>&1; then
  if printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
    PARSE_OK="true"
    SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
    CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
    STOP_ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
  fi
elif command -v python3 >/dev/null 2>&1; then
  # A heredoc nested in $(...) mis-parses on /bin/bash 3.2 — route via a file.
  _pjson="$(mktemp 2>/dev/null || echo "/tmp/mb-core-cap-parse.$$")"
  MB_CC_INPUT="$INPUT" python3 - >"$_pjson" 2>/dev/null <<'PY' || true
import json
import os

try:
    obj = json.loads(os.environ.get("MB_CC_INPUT", ""))
    if not isinstance(obj, dict):
        raise ValueError
except Exception:
    print("FAIL\t\t")
else:
    print(
        "OK\t"
        + ("true" if obj.get("stop_hook_active") is True else "false")
        + "\t" + (obj.get("session_id") or "")
        + "\t" + (obj.get("cwd") or "")
    )
PY
  _parsed="$(head -n1 "$_pjson" 2>/dev/null || true)"
  rm -f "$_pjson"
  case "$_parsed" in
    OK*)
      PARSE_OK="true"
      IFS=$'\t' read -r _ STOP_ACTIVE SESSION_ID CWD <<< "$_parsed"
      [ "$STOP_ACTIVE" = "true" ] || STOP_ACTIVE="false"
      ;;
  esac
fi

[ "$PARSE_OK" = "true" ] || allow
[ "$STOP_ACTIVE" = "true" ] && allow

[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"

BANK=""
if command -v mb_hook_resolve_mb_path >/dev/null 2>&1; then
  BANK="$(mb_hook_resolve_mb_path "$CWD" 2>/dev/null || true)"
fi
if [ -z "$BANK" ]; then
  if [ -n "${MB_PATH:-}" ]; then
    BANK="$MB_PATH"
  elif [ -d "$CWD/.memory-bank" ]; then
    BANK="$CWD/.memory-bank"
  fi
fi
[ -n "$BANK" ] && [ -d "$BANK" ] || allow

# One block per session. The marker short-circuits before the (mutating) fix
# run, so a session that was already told is neither blocked nor re-repaired.
SAFE_SID="$(printf '%s' "${SESSION_ID:-nosession}" | tr -c 'A-Za-z0-9._-' '_')"
MARKER="$BANK/.core-cap.nudged.$SAFE_SID"
[ -e "$MARKER" ] && allow

CAP_SH="$HOOK_DIR/../scripts/mb-core-cap.sh"
if [ ! -f "$CAP_SH" ] && command -v mb_skill_script_path >/dev/null 2>&1; then
  _resolved="$(mb_skill_script_path "mb-core-cap.sh" "$HOOK_DIR" 2>/dev/null || true)"
  [ -n "$_resolved" ] && CAP_SH="$_resolved"
fi
[ -f "$CAP_SH" ] || allow

FIX_OUT="$(bash "$CAP_SH" fix --mb "$BANK" 2>&1)"
FIX_RC=$?
# 0 = within caps after repair, 2 = the tool itself could not run → allow.
[ "$FIX_RC" -eq 1 ] || [ "$FIX_RC" -eq 3 ] || allow

COUNTS="$(printf '%s\n' "$FIX_OUT" | grep -E '^status_lines=' | tail -1)"
[ -n "$COUNTS" ] || allow
STATUS_N="$(printf '%s' "$COUNTS" | sed -E 's/.*status_lines=([0-9]+).*/\1/')"
STATUS_CAP="$(printf '%s' "$COUNTS" | sed -E 's/.*status_cap=([0-9]+).*/\1/')"
CHECK_N="$(printf '%s' "$COUNTS" | sed -E 's/.*checklist_lines=([0-9]+).*/\1/')"
CHECK_CAP="$(printf '%s' "$COUNTS" | sed -E 's/.*checklist_cap=([0-9]+).*/\1/')"

REASON="core-cap: status.md $STATUS_N/$STATUS_CAP, checklist.md $CHECK_N/$CHECK_CAP — dispatch MB Manager action: actualize --strict, then rerun mb-core-cap.sh check"
if [ "$FIX_RC" -eq 3 ]; then
  REASON="$REASON (checklist.md is over cap with live plans — that is an owner decision: pause or close plans, never trim live work)"
fi

: > "$MARKER" 2>/dev/null || true
block "$REASON"
