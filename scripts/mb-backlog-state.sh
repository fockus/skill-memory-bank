#!/usr/bin/env bash
# mb-backlog-state.sh — backlog state machine, hierarchy, briefs (design.md C3).
#
# Usage:
#   mb-backlog-state.sh transition <I-NNN> <NEW_STATE> [--reason TEXT] [--mb PATH]
#   mb-backlog-state.sh annotate   <I-NNN> --brief <TEXT> [--parent <I-NNN|none>] [--mb PATH]
#   mb-backlog-state.sh list [--mb PATH]
#
# Machine: NEW → NEEDS-INFO ⇄ TRIAGED → READY → IN-PROGRESS → DONE | WONTFIX.
# `transition` rewrites only the state token (extra detail after it is byte-
# preserved); READY requires a valid `**Brief:**` (behavioral, no file paths /
# line numbers). `annotate` is the single writer of `**Brief:**` / `**Parent:**`.
# `list` is flat (depth=0, numeric I-NNN order, JSON titles); `## Out of scope`
# entries are not listed. `--tree` is NOT accepted here (Task 7) → exit 2.
#
# All mutations serialize on <bank>/.locks/backlog.lock (owner-marker lock, C6)
# and write atomically (temp + rename). stdout carries only the success line;
# diagnostics go to stderr.
#
# Exit codes: 0 success; 1 domain reject (bad edge / gate / cycle / lock
# timeout); 2 usage / not-found.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

LOCK_TIMEOUT="${MB_BACKLOG_LOCK_TIMEOUT:-10}"
LOCK_TTL="${MB_BACKLOG_LOCK_TTL:-120}"

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

# _require_value <flag> [next...] — a dangling option (no value after it) is a
# usage error: exit 2 with a stderr diagnostic, NOT a `shift 2` out-of-range
# under set -e (which leaked an empty exit 1). A following KNOWN option-token in
# the value position is ALSO rejected (exit 2) rather than swallowed as the
# value — `--reason --mb` must not consume `--mb` as the reason and go on to
# mutate the backlog. This runs during arg parsing, BEFORE bank resolve / lock.
# Call as `_require_value "$@"`.
_require_value() {
  if [ "$#" -lt 2 ]; then
    echo "[mb-backlog-state] option $1 requires a value" >&2
    exit 2
  fi
  case "$2" in
    --reason | --brief | --parent | --mb | --tree | --help | -h)
      echo "[mb-backlog-state] option $1 requires a value, got option $2" >&2
      exit 2
      ;;
  esac
}

# Engine dispatcher: getstate / list / annotate. Delegates to the shared,
# stdlib-only state engine (scripts/mb_backlog_state_engine.py) so there is
# exactly ONE authoritative copy of the entry grammar + C3 machine.
run_engine() {
  "${MB_PYTHON:-python3}" "$SCRIPT_DIR/mb_backlog_state_engine.py" "$@"
}

_LOCK_DIR=""
_LOCK_TOKEN=""
_cleanup() {
  [ -n "$_LOCK_DIR" ] && mb_lock_release "$_LOCK_DIR" "$_LOCK_TOKEN" >/dev/null 2>&1 || true
}

_acquire_backlog_lock() {
  local bank="$1"
  mkdir -p "$bank/.locks"
  _LOCK_DIR="$bank/.locks/backlog.lock"
  if ! _LOCK_TOKEN="$(mb_lock_acquire "$_LOCK_DIR" "$LOCK_TIMEOUT" "$LOCK_TTL")"; then
    echo "[mb-backlog-state] could not acquire backlog lock within ${LOCK_TIMEOUT}s" >&2
    _LOCK_DIR=""
    exit 1
  fi
  trap _cleanup EXIT
}

main() {
  local sub="${1:-}"
  case "$sub" in
    -h | --help | "") usage; exit 0 ;;
    transition | annotate | list) shift ;;
    *) echo "[mb-backlog-state] unknown subcommand: $sub" >&2; exit 2 ;;
  esac

  local mb_arg="" id="" state="" reason="" reason_set=0
  local brief="" brief_set=0 parent="" parent_set=0

  case "$sub" in
    transition)
      id="${1:-}"; state="${2:-}"
      if [ -z "$id" ] || [ -z "$state" ]; then
        echo "[mb-backlog-state] usage: transition <I-NNN> <NEW_STATE> [--reason TEXT] [--mb PATH]" >&2
        exit 2
      fi
      shift 2
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --reason) _require_value "$@"; reason="$2"; reason_set=1; shift 2 ;;
          --mb) _require_value "$@"; mb_arg="$2"; shift 2 ;;
          *) echo "[mb-backlog-state] unexpected argument: $1" >&2; exit 2 ;;
        esac
      done
      ;;
    annotate)
      id="${1:-}"
      if [ -z "$id" ]; then
        echo "[mb-backlog-state] usage: annotate <I-NNN> --brief <TEXT> [--parent <I-NNN|none>] [--mb PATH]" >&2
        exit 2
      fi
      shift
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --brief) _require_value "$@"; brief="$2"; brief_set=1; shift 2 ;;
          --parent) _require_value "$@"; parent="$2"; parent_set=1; shift 2 ;;
          --mb) _require_value "$@"; mb_arg="$2"; shift 2 ;;
          *) echo "[mb-backlog-state] unexpected argument: $1" >&2; exit 2 ;;
        esac
      done
      if [ "$brief_set" -ne 1 ]; then
        echo "[mb-backlog-state] usage: annotate requires --brief" >&2
        exit 2
      fi
      ;;
    list)
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --mb) _require_value "$@"; mb_arg="$2"; shift 2 ;;
          *) echo "[mb-backlog-state] unexpected argument: $1" >&2; exit 2 ;;
        esac
      done
      ;;
  esac

  local bank backlog
  bank="$(mb_resolve_path "$mb_arg")"
  backlog="$bank/backlog.md"
  [ -f "$backlog" ] || { echo "[mb-backlog-state] backlog.md not found: $backlog" >&2; exit 1; }

  case "$sub" in
    list)
      run_engine list "$backlog"
      exit 0
      ;;
    transition)
      _acquire_backlog_lock "$bank"
      local old rc=0 err_file
      # Do NOT blanket-discard the engine's stderr: `getstate` is silent for a
      # plain not-found (the friendly message below covers it) but it is the
      # first reader to see a whole-file integrity failure such as
      # `code=duplicate_id`. Swallowing that turned an ambiguous database into a
      # misleading "not found" (finding 8).
      err_file="$(mktemp)"
      if ! old="$(run_engine getstate "$backlog" "$id" 2>"$err_file")"; then
        if [ -s "$err_file" ]; then
          cat "$err_file" >&2
        else
          echo "[mb-backlog-state] $id not found in $backlog" >&2
        fi
        rm -f "$err_file"
        exit 2
      fi
      rm -f "$err_file"
      if [ "$reason_set" -eq 1 ]; then
        mb_backlog_transition_locked "$backlog" "$id" "$state" --reason "$reason" || rc=$?
      else
        mb_backlog_transition_locked "$backlog" "$id" "$state" || rc=$?
      fi
      [ "$rc" -eq 0 ] || exit "$rc"
      printf 'item=%s old_state=%s new_state=%s\n' "$id" "$old" "$state"
      exit 0
      ;;
    annotate)
      _acquire_backlog_lock "$bank"
      local rc=0
      if [ "$parent_set" -eq 1 ]; then
        run_engine annotate "$backlog" "$id" --brief "$brief" --parent "$parent" || rc=$?
      else
        run_engine annotate "$backlog" "$id" --brief "$brief" || rc=$?
      fi
      [ "$rc" -eq 0 ] || exit "$rc"
      printf 'item=%s annotated\n' "$id"
      exit 0
      ;;
  esac
}

main "$@"
