#!/usr/bin/env bash
# mb-drive.sh — the /mb drive CLI (drive-autopilot design C3): a thin dispatcher over
# scripts/mb_drive_state.py (run files) and scripts/mb_drive_decide.py (gate, next, status).
#
# Usage:
#   mb-drive.sh start    [--bank B] [--goal PATH] [--budget TOK] [--serial] [--host-serial] [--session ID]
#                        → prints the run id (phase planning)
#   mb-drive.sh resume   [--bank B] [--run-id R]   → run_id=<id> goal=<path> phase=<phase>
#   mb-drive.sh phase execution [--bank B] [--run-id R] [--approve t1,t2]
#                        → exit 0, or exit 1 with one stderr line per planning gap
#   mb-drive.sh next     [--bank B] [--run-id R]   → ONE action line
#   mb-drive.sh returned --action "<line>" [--tokens N] [--outcome O] [--item-outcome <plan>=O]...
#                        [--work-run ID]... [--bank B] [--run-id R]
#   mb-drive.sh status   [--bank B] [--run-id R]   → JSON; never runs checks or the firewall
#
# Actions printed by `next`: plan · work <plan> · team <plan> <plan>… · pivot <plan> · qa <plan> ·
# wait <plan>… · final_qa · stop_success · stop_budget · stop_human <why>. Drive never prints
# implement, repair or a review action: item cycles belong to /mb work, tracks to /mb team.
#
# State: one file per drive run, <bank>/.drive/<run_id>.json (mbw_drive_slot). Without --run-id a
# subcommand takes the only live run; several live runs → exit 2 with one `run_id goal phase` line
# each. Several drives share a bank on distinct goal files (--goal).
#
# Exit: 0 ok · 1 refused (no bank, gate gaps, stopped run, goal already driven) · 2 usage.
# Env: MB_FLOW_VERIFY_BIN overrides the firewall binary (tests).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

if [ "$#" -lt 1 ]; then
  usage >&2
  exit 2
fi

sub="$1"
shift
case "$sub" in
  -h | --help | help) usage; exit 0 ;;
  start | resume | returned) module="mb_drive_state.py" ;;
  phase | next | status) module="mb_drive_decide.py" ;;
  *)
    echo "[drive] unknown subcommand '$sub'" >&2
    usage >&2
    exit 2
    ;;
esac

bank_arg=""
args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bank)
      [ "$#" -ge 2 ] || { echo "[drive] --bank needs a path" >&2; exit 2; }
      bank_arg="$2"
      shift 2
      ;;
    --bank=*) bank_arg="${1#--bank=}"; shift ;;
    -h | --help) usage; exit 0 ;;
    *) args+=("$1"); shift ;;
  esac
done

bank="$(mb_resolve_path "$bank_arg")"
if [ ! -d "$bank" ]; then
  echo "[drive] no Memory Bank at $bank — run /mb init first" >&2
  exit 1
fi

exec python3 "$SCRIPT_DIR/$module" "$sub" --bank "$bank" ${args[@]+"${args[@]}"}
