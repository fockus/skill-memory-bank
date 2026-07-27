#!/usr/bin/env bash
# mb-drive-stop.sh — drive-loop stop telemetry + per-run drive state
# (drive-loop Task 4 — REQ-DR-033, REQ-DR-034).
#
# Split out of scripts/mb-drive.sh on purpose: that file is the PURE decision
# function (and already over the 400-line budget, backlog I-102). Stop
# telemetry is the only stateful side of the loop, so it lives here.
#
# Subcommands (all take [--bank <b>] [--run-id ID], run_id also from
# $MB_WORK_RUN_ID):
#   arm     [--goal-id X]   marks a drive as RUNNING. This is the ONLY thing
#                           that arms hooks/mb-drive-resume-gate.sh — without
#                           it the Stop-hook is inert, so ordinary sessions
#                           are never gated.
#   record  --reason R | --action "<action line>" [--item ID]
#                           records a stop in three places, once each:
#                             1. the drive-state slot (status=stopped)
#                             2. the `mb-flow` fence in status.md, via
#                                mb-flow-sync.sh (the fence's single writer)
#                             3. progress.md, via mb-work-progress-append.sh
#                                (the append-only single-writer primitive)
#                           NO second fence-writing or append path exists here.
#   state                   prints the drive-state JSON ({} when absent/corrupt)
#   path                    prints the resolved drive-state slot path
#
# Stop-reason vocabulary (CLOSED — REQ-DR-033):
#   success | budget | human:max-cycle | human:stall | human:undecidable |
#   human:check-broke | human:check-broke:<check>
# The first five of the spec's enum are canonical; `human:undecidable` covers
# mb-drive.sh's fourth `stop_human` token, so every stop branch the decision
# function can emit is recordable (no telemetry hole).
#
# --action maps mb-drive.sh's action grammar onto that vocabulary, so the loop
# never hand-rolls a reason string:
#   stop_success -> success · stop_budget -> budget ·
#   stop_human <token> -> human:<token>
#
# Parallel runs (REQ-DR-034, reuses I-094): with MB_WORK_PARALLEL=1 and a
# run_id the state lives at <bank>/.drive-state/<run_id>.json; otherwise at
# the singleton <bank>/.drive-state.json. Two runs never contaminate each
# other. Path resolution is mbw_drive_slot (scripts/mb-work-slots.sh) — the
# same helper family that keys work-state and budget.
#
# Exit codes: 0 ok · 2 usage error (unknown subcommand/flag, a reason outside
# the closed vocabulary, a non-stop action).
#
# Fail-safe: once the state slot is written, a failing sink (fence or progress)
# degrades to a stderr warning + exit 0. Telemetry must never wedge a drive.
#
# Test seams (mirror mb-drive.sh's MB_*_BIN pattern):
#   MB_FLOW_SYNC_BIN        override mb-flow-sync.sh
#   MB_PROGRESS_APPEND_BIN  override mb-work-progress-append.sh
#
# Portability: bash 3.2 (no mapfile, no associative arrays); shellcheck clean.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# shellcheck source=mb-work-slots.sh
source "$SCRIPT_DIR/mb-work-slots.sh"

FLOW_SYNC_BIN="${MB_FLOW_SYNC_BIN:-$SCRIPT_DIR/mb-flow-sync.sh}"
PROGRESS_APPEND_BIN="${MB_PROGRESS_APPEND_BIN:-$SCRIPT_DIR/mb-work-progress-append.sh}"

usage() {
  sed -n '2,52p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

warn() {
  printf '[drive-stop] %s\n' "$1" >&2
}

# ---------------------------------------------------------------------------
# Shared flag parsing. Sets PARSED_BANK / PARSED_RUN_ID and leaves the
# subcommand-specific flags to the caller through REST_* globals.
# ---------------------------------------------------------------------------
PARSED_BANK=""
PARSED_RUN_ID=""
REST_REASON=""
REST_ACTION=""
REST_ITEM=""
REST_GOAL_ID=""

parse_flags() {
  PARSED_BANK=""
  PARSED_RUN_ID=""
  REST_REASON=""
  REST_ACTION=""
  REST_ITEM=""
  REST_GOAL_ID=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --bank) PARSED_BANK="${2:-}"; shift 2 ;;
      --bank=*) PARSED_BANK="${1#--bank=}"; shift ;;
      --mb) PARSED_BANK="${2:-}"; shift 2 ;;
      --mb=*) PARSED_BANK="${1#--mb=}"; shift ;;
      --run-id) PARSED_RUN_ID="${2:-}"; shift 2 ;;
      --run-id=*) PARSED_RUN_ID="${1#--run-id=}"; shift ;;
      --reason) REST_REASON="${2:-}"; shift 2 ;;
      --reason=*) REST_REASON="${1#--reason=}"; shift ;;
      --action) REST_ACTION="${2:-}"; shift 2 ;;
      --action=*) REST_ACTION="${1#--action=}"; shift ;;
      --item) REST_ITEM="${2:-}"; shift 2 ;;
      --item=*) REST_ITEM="${1#--item=}"; shift ;;
      --goal-id) REST_GOAL_ID="${2:-}"; shift 2 ;;
      --goal-id=*) REST_GOAL_ID="${1#--goal-id=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) warn "unknown argument '$1'"; exit 2 ;;
    esac
  done
  [ -n "$PARSED_RUN_ID" ] || PARSED_RUN_ID="${MB_WORK_RUN_ID:-}"
}

# Echoes the resolved drive-state slot for the parsed bank/run.
resolve_slot() {
  local bank
  bank="$(mb_resolve_path "$PARSED_BANK")"
  mbw_drive_slot "$bank" "$PARSED_RUN_ID"
}

# ---------------------------------------------------------------------------
# Reason vocabulary — CLOSED. Returns 0 when $1 is a legal stop reason.
# ---------------------------------------------------------------------------
valid_reason() {
  case "${1:-}" in
    success|budget|human:max-cycle|human:stall|human:undecidable|human:check-broke)
      return 0
      ;;
    human:check-broke:*)
      # The check name must be a plain token — no whitespace/newline can enter
      # the fence (a one-line field) or a progress line.
      case "${1#human:check-broke:}" in
        ''|*[!A-Za-z0-9._-]*) return 1 ;;
        *) return 0 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

# Maps an mb-drive.sh action line onto a stop reason. Echoes "" for any
# non-stop action, so only real stops can produce telemetry.
reason_from_action() {
  local action="${1:-}"
  case "$action" in
    stop_success) printf 'success\n' ;;
    stop_budget) printf 'budget\n' ;;
    "stop_human "*)
      local token="${action#stop_human }"
      # Collapse to the first word: the grammar is `stop_human <why>`.
      token="${token%% *}"
      [ -n "$token" ] && printf 'human:%s\n' "$token"
      ;;
    *) : ;;
  esac
}

# ---------------------------------------------------------------------------
# State slot IO. Atomic write (temp file + mv) so no reader ever sees a
# partial JSON — the same discipline as mb-work-state.sh / the progress writer.
# ---------------------------------------------------------------------------
write_state() {
  # $1 = slot path, $2 = status, $3 = stop_reason, $4 = item, $5 = goal_id
  local slot="$1" status="$2" reason="$3" item="$4" goal_id="$5" dir tmp
  dir="$(dirname "$slot")"
  mkdir -p "$dir" 2>/dev/null || { warn "cannot create $dir"; return 1; }
  tmp="$(mktemp "$dir/.drive.XXXXXX" 2>/dev/null)" || { warn "mktemp failed"; return 1; }
  if ! SLOT_STATUS="$status" SLOT_REASON="$reason" SLOT_RUN_ID="$PARSED_RUN_ID" \
    SLOT_ITEM="$item" SLOT_GOAL_ID="$goal_id" python3 -c '
import datetime, json, os
e = os.environ
doc = {
    "run_id": e.get("SLOT_RUN_ID", ""),
    "status": e.get("SLOT_STATUS", ""),
    "stop_reason": e.get("SLOT_REASON", ""),
    "item": e.get("SLOT_ITEM", ""),
    "goal_id": e.get("SLOT_GOAL_ID", ""),
    "updated": datetime.datetime.now(datetime.timezone.utc)
    .replace(microsecond=0)
    .isoformat()
    .replace("+00:00", "Z"),
}
print(json.dumps(doc, indent=2, ensure_ascii=False))
' >"$tmp" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null || true
    warn "could not render drive state"
    return 1
  fi
  mv -f "$tmp" "$slot" 2>/dev/null || { rm -f "$tmp" 2>/dev/null || true; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------
cmd_arm() {
  parse_flags "$@"
  local slot
  slot="$(resolve_slot)"
  write_state "$slot" "driving" "" "$REST_ITEM" "$REST_GOAL_ID" || exit 1
  printf '%s\n' "$slot"
}

cmd_path() {
  parse_flags "$@"
  resolve_slot
}

cmd_state() {
  parse_flags "$@"
  local slot
  slot="$(resolve_slot)"
  if [ ! -f "$slot" ]; then
    printf '{}\n'
    return 0
  fi
  # Fail-safe: a corrupt slot reads as {} — a drive that cannot be proven live
  # must never look live to the resume-gate.
  SLOT="$slot" python3 -c '
import json, os
try:
    doc = json.load(open(os.environ["SLOT"], encoding="utf-8"))
    if not isinstance(doc, dict):
        doc = {}
except Exception:
    doc = {}
print(json.dumps(doc, indent=2, ensure_ascii=False))
' 2>/dev/null || printf '{}\n'
}

cmd_record() {
  parse_flags "$@"

  local reason="$REST_REASON"
  if [ -z "$reason" ] && [ -n "$REST_ACTION" ]; then
    reason="$(reason_from_action "$REST_ACTION")"
    if [ -z "$reason" ]; then
      warn "--action '$REST_ACTION' is not a stop action; only stops are telemetry"
      exit 2
    fi
  fi

  if [ -z "$reason" ]; then
    warn "record needs --reason <R> or --action \"<action line>\""
    usage >&2
    exit 2
  fi

  if ! valid_reason "$reason"; then
    warn "reason '$reason' is outside the closed vocabulary (success | budget | human:max-cycle | human:stall | human:undecidable | human:check-broke[:<check>])"
    exit 2
  fi

  local bank slot
  bank="$(mb_resolve_path "$PARSED_BANK")"
  slot="$(mbw_drive_slot "$bank" "$PARSED_RUN_ID")"

  # 1. Durable drive state first: it is what the resume-gate reads, so it must
  #    be true before either narrative sink is attempted.
  write_state "$slot" "stopped" "$reason" "$REST_ITEM" "" || exit 1

  # 2. The mb-flow fence — via its SINGLE writer. Fail-safe: warn, never wedge.
  if [ -x "$FLOW_SYNC_BIN" ] || [ -f "$FLOW_SYNC_BIN" ]; then
    bash "$FLOW_SYNC_BIN" "$bank" --stop-reason "$reason" >/dev/null 2>&1 ||
      warn "fence write failed (stop recorded in $slot)"
  else
    warn "mb-flow-sync.sh not found at $FLOW_SYNC_BIN; fence not updated"
  fi

  # 3. progress.md — via the append-only single-writer primitive.
  local line
  line="- **drive stop** (\`${reason}\`)"
  [ -n "$PARSED_RUN_ID" ] && line="$line run=\`${PARSED_RUN_ID}\`"
  [ -n "$REST_ITEM" ] && line="$line item=\`${REST_ITEM}\`"
  line="$line — drive-loop halted; see the \`mb-flow\` fence in status.md."
  if [ -x "$PROGRESS_APPEND_BIN" ] || [ -f "$PROGRESS_APPEND_BIN" ]; then
    bash "$PROGRESS_APPEND_BIN" --text "$line" --mb "$bank" >/dev/null 2>&1 ||
      warn "progress append failed (stop recorded in $slot)"
  else
    warn "mb-work-progress-append.sh not found at $PROGRESS_APPEND_BIN; progress not updated"
  fi

  return 0
}

main() {
  if [ "$#" -lt 1 ]; then
    usage >&2
    exit 2
  fi
  case "$1" in
    -h|--help) usage; exit 0 ;;
    arm) shift; cmd_arm "$@" ;;
    record) shift; cmd_record "$@" ;;
    state) shift; cmd_state "$@" ;;
    path) shift; cmd_path "$@" ;;
    *) warn "unknown subcommand '$1'"; usage >&2; exit 2 ;;
  esac
}

main "$@"
