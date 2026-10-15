#!/usr/bin/env bash
# mb-drive-resume-gate.sh — Stop-hook resume gate for `/mb drive`
# (drive-autopilot design C4; REQ-045, REQ-043).
#
# HOSTS THAT CALL IT
#   Claude Code (settings/hooks.json, Stop) and Codex (hooks/mb-codex.py, the
#   Stop dispatch). Hosts without a Stop event rely on the `/mb drive` loop
#   contract in AGENTS.md and the commit-time closure guard instead.
#
# WHAT IT DOES
#   While a drive run is in phase `execution`, a stop is premature unless its
#   goal is met or the run recorded a stop (`mb-drive-stop.sh record` sets
#   phase `stopped`). This hook blocks such a stop, so the loop resumes.
#
# COST CONTRACT (backlog I-131)
#   Decides by READING FILES ONLY: the run files <bank>/.drive/<run_id>.json
#   and the goal's checkboxes through `mb-goal-acceptance.sh --ticks-only`
#   (no plan read, no `check:` command). It NEVER runs mb-flow-verify.sh, a
#   test battery or an LLM, and never reads the environment's run id.
#
# Stop-hook contract
#   - JSON object on STDIN (`stop_hook_active`, `cwd`, `session_id`).
#   - BLOCK: print {"decision":"block","reason":"<text>"} on stdout, exit 0.
#   - ALLOW: exit 0 with no decision.
#
# DECISION (first match wins)
#   1. kill-switch MB_DRIVE_RESUME_GATE=off, or the re-entry sentinel  -> allow
#   2. unparseable stdin / not a JSON object                            -> allow
#   3. stop_hook_active (re-entry after a block)                        -> allow
#   4. no bank                                                          -> allow
#   5. candidates = run files in phase `execution`; those whose `session`
#      is the input's session_id, else those without a session (all runs
#      when the input has no session_id); none                          -> allow
#   6. several candidates -> allow with one stderr warning listing them
#   7. one candidate whose goal ticks report "ok":false                 -> BLOCK
#   8. otherwise (goal met, no criteria, unreadable)                    -> allow
#
# FAIL-SAFE: any infrastructure problem (missing python3, corrupt run file,
# missing acceptance helper, a timeout) resolves to ALLOW.

set -u

[ -n "${MB_CAPTURE_SUBPROCESS:-}" ] && exit 0

allow() {
  exit 0
}

case "${MB_DRIVE_RESUME_GATE:-}" in
  off|OFF|0|false|FALSE|no|NO) allow ;;
  *) : ;;
esac

command -v python3 >/dev/null 2>&1 || allow
HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || allow
if [ -f "$HOOK_DIR/_skill_root.sh" ]; then
  # shellcheck source=hooks/_skill_root.sh
  . "$HOOK_DIR/_skill_root.sh"
fi

# Parse stdin → "active<TAB>session<TAB>cwd"; anything but an object → allow.
INPUT="$(cat 2>/dev/null || true)"
PARSED="$(MB_GATE_INPUT="$INPUT" python3 -c '
import json, os
obj = json.loads(os.environ["MB_GATE_INPUT"])
assert isinstance(obj, dict)
clean = lambda v: v.replace("\t", " ").replace("\n", " ") if isinstance(v, str) else ""
print("true" if obj.get("stop_hook_active") is True else "false",
      clean(obj.get("session_id")), clean(obj.get("cwd")), sep="\t")
' 2>/dev/null)" || allow

STOP_ACTIVE="${PARSED%%	*}"
_rest="${PARSED#*	}"
SESSION="${_rest%%	*}"
CWD="${_rest#*	}"

[ "$STOP_ACTIVE" = "true" ] && allow
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"

BANK=""
if command -v mb_hook_resolve_mb_path >/dev/null 2>&1; then
  BANK="$(mb_hook_resolve_mb_path "$CWD" 2>/dev/null || true)"
elif [ -n "${MB_PATH:-}" ]; then
  BANK="$MB_PATH"
elif [ -d "$CWD/.memory-bank" ]; then
  BANK="$CWD/.memory-bank"
fi
[ -n "$BANK" ] && [ -d "$BANK/.drive" ] || allow

# Candidates as "run_id<TAB>goal" lines (design C4 step 5).
CANDIDATES="$(python3 -c '
import json, pathlib, sys
session = sys.argv[2]
runs = []
for path in sorted(pathlib.Path(sys.argv[1]).glob("*.json")):
    try:
        st = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        continue
    if isinstance(st, dict) and st.get("phase") == "execution" and st.get("run_id") and st.get("goal"):
        runs.append(st)
own = [st for st in runs if session and st.get("session") == session]
# Without a session id from the host every execution run qualifies (REQ-045).
for st in own or ([st for st in runs if not st.get("session")] if session else runs):
    print(st["run_id"], st["goal"], sep="\t")
' "$BANK/.drive" "$SESSION" 2>/dev/null)" || allow

[ -n "$CANDIDATES" ] || allow
if [ "$(printf '%s\n' "$CANDIDATES" | wc -l | tr -d ' ')" -gt 1 ]; then
  printf '[drive-gate] several drive runs qualify, not gating this stop: %s\n' \
    "$(printf '%s\n' "$CANDIDATES" | cut -f1 | tr '\n' ' ')" >&2
  allow
fi

RUN_ID="${CANDIDATES%%	*}"
GOAL="${CANDIDATES#*	}"

ACCEPT_BIN="${MB_GOAL_ACCEPTANCE_BIN:-$HOOK_DIR/../scripts/mb-goal-acceptance.sh}"
# An explicit override wins outright; only the default is re-resolved.
if [ -z "${MB_GOAL_ACCEPTANCE_BIN:-}" ] && [ ! -f "$ACCEPT_BIN" ] &&
  command -v mb_skill_script_path >/dev/null 2>&1; then
  ACCEPT_BIN="$(mb_skill_script_path "mb-goal-acceptance.sh" "$HOOK_DIR" 2>/dev/null || true)"
fi
[ -n "$ACCEPT_BIN" ] && [ -f "$ACCEPT_BIN" ] || allow

TIMEOUT_BIN=""
command -v timeout >/dev/null 2>&1 && TIMEOUT_BIN="timeout"
[ -z "$TIMEOUT_BIN" ] && command -v gtimeout >/dev/null 2>&1 && TIMEOUT_BIN="gtimeout"
if [ -n "$TIMEOUT_BIN" ]; then
  ACCEPT_JSON="$("$TIMEOUT_BIN" "${MB_DRIVE_GATE_TIMEOUT:-10}" bash "$ACCEPT_BIN" "$GOAL" "$BANK" --ticks-only 2>/dev/null || true)"
else
  ACCEPT_JSON="$(bash "$ACCEPT_BIN" "$GOAL" "$BANK" --ticks-only 2>/dev/null || true)"
fi

# Only an explicit ok=false means "not done"; true / null / garbage allow.
case "$ACCEPT_JSON" in
  *'"ok":false'*|*'"ok": false'*) : ;;
  *) allow ;;
esac

REASON="Drive resume gate: run $RUN_ID is executing and its goal $GOAL is not met — this stop is premature (REQ-045). Call \`scripts/mb-drive.sh next --bank $BANK --run-id $RUN_ID\` and execute the action it prints until it prints a stop_* action. To end deliberately, record it first: \`scripts/mb-drive-stop.sh record --bank $BANK --run-id $RUN_ID --action \"<the stop_* action>\"\`."
if command -v jq >/dev/null 2>&1; then
  jq -cn --arg r "$REASON" '{decision:"block", reason:$r}'
else
  MB_GATE_REASON="$REASON" python3 -c 'import json, os; print(json.dumps({"decision": "block", "reason": os.environ["MB_GATE_REASON"]}, separators=(",", ":")))'
fi
exit 0
