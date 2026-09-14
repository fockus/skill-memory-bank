#!/usr/bin/env bash
# Arm a validated drive goal without resetting an existing run's counters.
# Usage: mb-drive-preflight.sh --bank BANK --run-id ID [--max-cycles N] [--budget TOK]
# Empty limits mean unspecified. Same-run limits are immutable on resume;
# conflicting flags or corrupt existing components refuse before any writes.
# Missing components are initialized through the existing state owners.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# shellcheck source=mb-work-slots.sh
source "$SCRIPT_DIR/mb-work-slots.sh"

BANK_ARG=""; RUN_ID="${MB_WORK_RUN_ID:-}"; MAX_CYCLES=""; BUDGET=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bank|--run-id|--max-cycles|--budget)
      [ "$#" -ge 2 ] || { echo "[drive] $1 needs a value" >&2; exit 2; }
      case "$1" in
        --bank) BANK_ARG="$2" ;; --run-id) RUN_ID="$2" ;;
        --max-cycles) MAX_CYCLES="$2" ;; --budget) BUDGET="$2" ;;
      esac
      shift 2 ;;
    *) echo "[drive] unknown argument '$1'" >&2; exit 2 ;;
  esac
done
case "$RUN_ID" in
  ''|.|..|*[!A-Za-z0-9._-]*) echo "[drive] a filename-safe run-id is required" >&2; exit 2 ;;
esac
for limit in "$MAX_CYCLES" "$BUDGET"; do
  case "$limit" in *[!0-9]*) echo "[drive] limits must be non-negative integers" >&2; exit 2 ;; esac
done
BANK="$(mb_resolve_path "$BANK_ARG")"
[ -d "$BANK" ] || { echo "[drive] no Memory Bank at '$BANK'" >&2; exit 1; }

# Read slots directly: generic status deliberately masks corrupt JSON as {}.
# Validate every component before initializing any of them. A valid foreign
# singleton belongs to a new run; a same-run slot is kept byte-for-byte.
component_mode() {
  python3 - "$1" "$2" "$RUN_ID" "$3" <<'PY'
import json
import os
import sys

kind, path, run_id, limit = sys.argv[1:]
if not os.path.lexists(path):
    print("new")
    sys.exit(0)


def uint(value):
    return type(value) is int and value >= 0


try:
    with open(path, encoding="utf-8") as stream:
        state = json.load(stream)
    valid = isinstance(state, dict) and isinstance(state.get("run_id"), str) and bool(state["run_id"])
    if valid and kind == "work-state":
        valid = all(uint(state.get(key)) for key in ("cycle", "max_cycles", "item_no"))
        valid = valid and isinstance(state.get("steps"), list) and all(isinstance(step, str) for step in state["steps"])
        valid = valid and isinstance(state.get("source"), str) and bool(state["source"])
        valid = valid and state.get("phase") in ("in-progress", "done")
        limit_key = "max_cycles"
    elif valid and kind == "work-budget":
        valid = all(uint(state.get(key)) for key in ("total", "spent", "warn_at_percent", "stop_at_percent"))
        limit_key = "total"
    elif valid and kind == "drive-state":
        valid = state.get("status") in ("driving", "stopped")
    if not valid:
        raise ValueError("invalid state schema")
    if state["run_id"] != run_id:
        print("new")
    elif limit and int(limit) != state[limit_key]:
        raise ValueError(f"resume {limit_key} is {state[limit_key]}; omit the conflicting flag or use the stored limit")
    else:
        print("arm" if kind == "drive-state" and state["status"] == "stopped" else "resume")
except (OSError, ValueError, TypeError, KeyError) as error:
    print(f"[drive] refusing preflight: {kind} at '{path}': {error}; repair the saved state before retrying", file=sys.stderr)
    sys.exit(1)
PY
}

STATE_MODE="$(component_mode work-state "$(mbw_state_slot "$BANK" "$RUN_ID")" "$MAX_CYCLES")"
BUDGET_MODE="$(component_mode work-budget "$(mbw_budget_slot "$BANK" "$RUN_ID")" "$BUDGET")"
DRIVE_MODE="$(component_mode drive-state "$(mbw_drive_slot "$BANK" "$RUN_ID")" "")"

if [ "$STATE_MODE" = "new" ]; then
  state_args=(init drive 0 --run-id "$RUN_ID" --mb "$BANK")
  [ -z "$MAX_CYCLES" ] || state_args+=(--max-cycles "$MAX_CYCLES")
  bash "$SCRIPT_DIR/mb-work-state.sh" "${state_args[@]}" >/dev/null
fi
if [ "$BUDGET_MODE" = "new" ] && [ -n "$BUDGET" ]; then
  bash "$SCRIPT_DIR/mb-work-budget.sh" init "$BUDGET" --run-id "$RUN_ID" --mb "$BANK" >/dev/null
fi
# Arm telemetry last. A live same-run slot keeps its item and start metadata.
if [ "$DRIVE_MODE" != "resume" ]; then
  bash "$SCRIPT_DIR/mb-drive-stop.sh" arm --bank "$BANK" --run-id "$RUN_ID" >/dev/null
fi
