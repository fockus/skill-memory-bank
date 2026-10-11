#!/usr/bin/env bash
# mb-team.sh — /mb team dispatcher (specs/mb-team design §10). The orchestrator is the runtime;
# this script is the stateless brain plus the single writer of reports/<topic>/team.json.
#
# Usage: mb-team.sh [--mb <bank>] [--topic T] <subcommand> …
#   init <topic> · track add|set <id> · plan · prompt <id> · known-red add|list   (mb_team_tracks.py)
#   next · status                                                                  (mb_team_status.py)
#   collect · commit · checkpoint · close                                          (mb_team_ops.py)
#   review gate --cycle N       → mb-team-review.sh gate, recorded in team.json reviews[]
#   review start|external|ingest … → mb-team-review.sh with --team/--mb
# `next` only prints actions; it never dispatches. There is no push path.
# Refuses to run with the working directory inside a Memory Bank (no nested bank).
# Exit: 0 ok · 1 refused / step failed · 2 usage or bad input · review gate passes its own code.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

case "$PWD/" in
  */.memory-bank/*)
    echo "mb-team: the working directory is inside a Memory Bank ($PWD); run from the project root or pass --mb <bank>" >&2
    exit 2
    ;;
esac

mb=""
topic=()
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --mb) mb="${2:?--mb needs a path}"; shift 2 ;;
    --mb=*) mb="${1#--mb=}"; shift ;;
    --topic) topic=(--topic "${2:?--topic needs a name}"); shift 2 ;;
    --topic=*) topic=(--topic "${1#--topic=}"); shift ;;
    *) args+=("$1"); shift ;;
  esac
done
[ "${#args[@]}" -gt 0 ] || { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

bank="$(mb_resolve_path "$mb")"
[ -d "$bank" ] || { echo "mb-team: no Memory Bank at $bank (run /mb init or pass --mb)" >&2; exit 2; }
bank="$(cd "$bank" && pwd)"
tail_args=(${topic[@]+"${topic[@]}"} --mb "$bank")

case "${args[0]}" in
  init | track | plan | prompt | known-red) exec python3 "$SCRIPT_DIR/mb_team_tracks.py" "${args[@]}" "${tail_args[@]}" ;;
  next | status) exec python3 "$SCRIPT_DIR/mb_team_status.py" "${args[@]}" "${tail_args[@]}" ;;
  collect | commit | checkpoint | close) exec python3 "$SCRIPT_DIR/mb_team_ops.py" "${args[@]}" "${tail_args[@]}" ;;
  review)
    [ "${#args[@]}" -gt 1 ] || { echo "mb-team: review start|gate|external|ingest" >&2; exit 2; }
    if [ "${args[1]}" = gate ]; then
      exec python3 "$SCRIPT_DIR/mb_team_ops.py" review-gate "${args[@]:2}" "${tail_args[@]}"
    fi
    team_json="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import mb_team_state as s
try:
    print(s.team_file(sys.argv[2], s.find_topic(sys.argv[2], sys.argv[3])))
except s.TeamError as e:
    sys.exit(f"[team] {e}")' "$SCRIPT_DIR" "$bank" "${topic[1]:-}")"
    exec bash "$SCRIPT_DIR/mb-team-review.sh" "${args[@]:1}" --team "$team_json" --mb "$bank"
    ;;
  *) echo "mb-team: unknown subcommand '${args[0]}'" >&2; exit 2 ;;
esac
