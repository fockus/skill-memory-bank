#!/usr/bin/env bash
# mb-console.sh — orchestrator-console.md helpers (references/orchestrator-console.md).
#
# Usage:
#   mb-console.sh line <track> <status> <note> [--mb <bank>]   # replace the track's line under "## Tracks"
#   mb-console.sh check [--mb <bank>]                          # exit 1 above MB_CONSOLE_MAX_LINES (default 40)
# `line` runs under the built-in `console` lock (mb-lock.sh), so parallel tracks never lose a line.
# Exit: 0 ok · 1 over the cap · 2 usage · mb-lock.sh codes for `line` (75 wait timeout).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

mb="" args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --mb) mb="${2:?--mb needs a path}"; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
[ "${#args[@]}" -gt 0 ] || { sed -n '4,6p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
bank="$(mb_resolve_path "$mb")"
[ -d "$bank" ] || { echo "mb-console: no Memory Bank at $bank" >&2; exit 2; }
bank="$(cd "$bank" && pwd)"

case "${args[0]}" in
  line)
    [ "${#args[@]}" -eq 4 ] || { echo "mb-console: line <track> <status> <note>" >&2; exit 2; }
    exec bash "$SCRIPT_DIR/mb-lock.sh" run console --owner "console:${args[1]}" --wait 60 --mb "$bank" -- \
      python3 "$SCRIPT_DIR/mb_team_console.py" line "$bank" "${args[1]}" "${args[2]}" "${args[3]}"
    ;;
  check) exec python3 "$SCRIPT_DIR/mb_team_console.py" check "$bank" ;;
  *) echo "mb-console: unknown subcommand '${args[0]}'" >&2; exit 2 ;;
esac
