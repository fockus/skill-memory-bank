#!/usr/bin/env bash
# mb-drive-stop.sh — drive stop telemetry on the drive run files
# (drive-autopilot design C4; REQ-045, REQ-028).
#
# Subcommands (all take [--bank <b>] [--run-id R]):
#   record  --reason R | --action "<action line>" [--item ID]
#                           selects the run like `mb-drive.sh` (--run-id, else
#                           the only live run; several live → exit 2, none →
#                           exit 1) and records the stop in three places:
#                             1. the run file <bank>/.drive/<run_id>.json
#                                (phase=stopped, stop_reason) through
#                                `mb_drive_state.py stop`
#                             2. the `mb-flow` fence in status.md, via
#                                mb-flow-sync.sh (the fence's single writer)
#                             3. progress.md, via mb-work-progress-append.sh
#   state                   prints the selected run file ({} when unreadable)
#   path                    prints the selected run file path
#
# Stop-reason vocabulary (CLOSED):
#   success | budget | human:max-cycle | human:stall | human:undecidable |
#   human:qa-red | human:check-broke[:<checks>] | human:acceptance-red:<n> |
#   human:flow-red:<checks> | human:qa-blocked:<reason> |
#   human:owned-elsewhere:<id>        (tokens: [A-Za-z0-9._,:-])
#
# --action maps mb-drive.sh's action grammar onto that vocabulary:
#   stop_success -> success · stop_budget -> budget ·
#   stop_human <token> -> human:<token>
#
# Exit codes: 0 ok · 1 no such run · 2 usage error (unknown subcommand/flag,
# a reason outside the vocabulary, a non-stop action, several live runs).
#
# Fail-safe: once the run file is written, a failing sink (fence or progress)
# degrades to a stderr warning + exit 0. Telemetry must never wedge a drive.
#
# Test seams: MB_FLOW_SYNC_BIN (mb-flow-sync.sh), MB_PROGRESS_APPEND_BIN
# (mb-work-progress-append.sh).
#
# Portability: bash 3.2; shellcheck clean.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# shellcheck source=mb-work-slots.sh
source "$SCRIPT_DIR/mb-work-slots.sh"

FLOW_SYNC_BIN="${MB_FLOW_SYNC_BIN:-$SCRIPT_DIR/mb-flow-sync.sh}"
PROGRESS_APPEND_BIN="${MB_PROGRESS_APPEND_BIN:-$SCRIPT_DIR/mb-work-progress-append.sh}"

usage() {
  sed -n '2,37p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

warn() {
  printf '[drive-stop] %s\n' "$1" >&2
}

PARSED_BANK=""
PARSED_RUN_ID=""
REST_REASON=""
REST_ACTION=""
REST_ITEM=""

parse_flags() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --bank|--mb) PARSED_BANK="${2:-}"; shift 2 ;;
      --bank=*) PARSED_BANK="${1#--bank=}"; shift ;;
      --mb=*) PARSED_BANK="${1#--mb=}"; shift ;;
      --run-id) PARSED_RUN_ID="${2:-}"; shift 2 ;;
      --run-id=*) PARSED_RUN_ID="${1#--run-id=}"; shift ;;
      --reason) REST_REASON="${2:-}"; shift 2 ;;
      --reason=*) REST_REASON="${1#--reason=}"; shift ;;
      --action) REST_ACTION="${2:-}"; shift 2 ;;
      --action=*) REST_ACTION="${1#--action=}"; shift ;;
      --item) REST_ITEM="${2:-}"; shift 2 ;;
      --item=*) REST_ITEM="${1#--item=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) warn "unknown argument '$1'"; exit 2 ;;
    esac
  done
  BANK="$(mb_resolve_path "$PARSED_BANK")"
}

# Echoes the selected run file (design C2 run selection, owned by
# mb_drive_state.select: it lists the live runs and exits 2 when several).
selected_run_file() {
  local run_id="$PARSED_RUN_ID"
  if [ -z "$run_id" ]; then
    run_id="$(python3 -c '
import pathlib, sys
sys.path.insert(0, sys.argv[1])
import mb_drive_state as m
print(m.select(pathlib.Path(sys.argv[2]).resolve(), None)["run_id"])
' "$SCRIPT_DIR" "$BANK")" || { local rc=$?; printf '%s\n' "$run_id" >&2; return "$rc"; }
  fi
  mbw_drive_slot "$BANK" "$run_id"
}

# Returns 0 when $1 is a legal stop reason (the closed vocabulary).
valid_reason() {
  local token
  case "${1:-}" in
    success|budget|human:max-cycle|human:stall|human:undecidable|human:qa-red|human:check-broke)
      return 0 ;;
    human:check-broke:*|human:acceptance-red:*|human:flow-red:*|human:qa-blocked:*|human:owned-elsewhere:*)
      # One plain token: no whitespace or newline can enter the one-line
      # fence field or the progress line.
      token="${1#human:*:}"
      case "$token" in
        ''|*[!A-Za-z0-9._,:-]*) return 1 ;;
        *) return 0 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

# Maps an mb-drive.sh action line onto a stop reason; "" for a non-stop action.
reason_from_action() {
  case "${1:-}" in
    stop_success) printf 'success\n' ;;
    stop_budget) printf 'budget\n' ;;
    "stop_human "*)
      local token="${1#stop_human }"
      token="${token%% *}"
      [ -n "$token" ] && printf 'human:%s\n' "$token"
      ;;
    *) : ;;
  esac
}

cmd_path() {
  parse_flags "$@"
  selected_run_file
}

cmd_state() {
  parse_flags "$@"
  local file
  file="$(selected_run_file)"
  # A corrupt or missing run file reads as {}: it cannot prove a live drive.
  python3 -c '
import json, sys
try:
    doc = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    doc = {}
print(json.dumps(doc if isinstance(doc, dict) else {}, indent=2, ensure_ascii=False))
' "$file"
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
    exit 2
  fi
  if ! valid_reason "$reason"; then
    warn "reason '$reason' is outside the closed stop vocabulary (see --help)"
    exit 2
  fi

  # 1. The run file first: it is what resume and the gate read.
  local args=(stop --bank "$BANK" --reason "$reason") file run_id rc
  [ -z "$PARSED_RUN_ID" ] || args+=(--run-id "$PARSED_RUN_ID")
  file="$(python3 "$SCRIPT_DIR/mb_drive_state.py" "${args[@]}")" || { rc=$?; printf '%s\n' "$file" >&2; exit "$rc"; }
  run_id="$(basename "$file" .json)"

  # 2. The mb-flow fence — via its single writer.
  bash "$FLOW_SYNC_BIN" "$BANK" --stop-reason "$reason" >/dev/null 2>&1 ||
    warn "fence write failed (stop recorded in $file)"

  # 3. progress.md — via the append-only single writer.
  local line="- **drive stop** (\`${reason}\`) run=\`${run_id}\`"
  [ -z "$REST_ITEM" ] || line="$line item=\`${REST_ITEM}\`"
  line="$line — drive halted; see the \`mb-flow\` fence in status.md."
  bash "$PROGRESS_APPEND_BIN" --text "$line" --mb "$BANK" >/dev/null 2>&1 ||
    warn "progress append failed (stop recorded in $file)"
  return 0
}

main() {
  if [ "$#" -lt 1 ]; then
    usage >&2
    exit 2
  fi
  case "$1" in
    -h|--help) usage; exit 0 ;;
    record) shift; cmd_record "$@" ;;
    state) shift; cmd_state "$@" ;;
    path) shift; cmd_path "$@" ;;
    *) warn "unknown subcommand '$1'"; usage >&2; exit 2 ;;
  esac
}

main "$@"
