#!/usr/bin/env bash
# mb-lock.sh — named resource locks with a fair ticket queue (specs/mb-team design §5).
#
# Usage:
#   mb-lock.sh run     <res> --owner <id> [--wait S] [--no-maintenance] -- <cmd…>
#   mb-lock.sh acquire <res> --owner <id> --lease S [--wait S]      # prints the token
#   mb-lock.sh release <res> --token T
#   mb-lock.sh maint   <res> --token T                              # maintenance, lock holder only
#   mb-lock.sh status  [<res>] [--json]
#   mb-lock.sh watch   <res> [--interval S]                         # board entries on condition edges
#   mb-lock.sh break   <res> --reason R [--owner <id>]              # dead holders only
# Common: --mb <bank>, --resource-json <file> (else `mb_team_config.py resource <res>`).
#
# Waiters are served oldest ticket first. A lock whose holder or holder child is alive is never removed;
# a provably dead holder (both gone, same host, pid + start time) is reclaimed by the queue head and
# reported on the board. `run` checks the preconditions under the lock, runs maintenance when they fail,
# and watches the stop threshold while the command runs.
#
# Exit: 0 or the command's status · 1 refused/corrupt · 2 usage or config · 75 wait timeout ·
#       76 stop condition hit · 77 preconditions unmet (the command was not run)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PY="$SCRIPT_DIR/mb_lock_queue.py"

say() { printf 'mb-lock: %s\n' "$*" >&2; }
die() {
  say "$1"
  exit "${2:-2}"
}
usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

SUB="${1:-}"
[ $# -gt 0 ] && shift
NAME=""
case "${1:-}" in -* | "") ;; *)
  NAME="$1"
  shift
  ;;
esac
OWNER="" WAIT=0 LEASE=0 TOKEN_ARG="" REASON="" INTERVAL="" JSON="" NO_MAINT=0 BANK="" RES_JSON=""
while [ $# -gt 0 ]; do
  case "$1" in
    --owner | --wait | --lease | --token | --reason | --interval | --mb | --resource-json)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in
        --owner) OWNER="$2" ;; --wait) WAIT="$2" ;; --lease) LEASE="$2" ;; --token) TOKEN_ARG="$2" ;;
        --reason) REASON="$2" ;; --interval) INTERVAL="$2" ;; --mb) BANK="$2" ;; --resource-json) RES_JSON="$2" ;;
      esac
      shift 2
      ;;
    --json) JSON=--json && shift ;;
    --no-maintenance) NO_MAINT=1 && shift ;;
    --) shift && break ;;
    *) die "unknown argument: $1" ;;
  esac
done
for n in "$WAIT" "$LEASE" "${INTERVAL:-0}"; do
  [[ "$n" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "not a number of seconds: $n"
done
if [ -z "$BANK" ] && [ -d .memory-bank ]; then BANK="$PWD/.memory-bank"; fi
COMMON=()
[ -n "$NAME" ] && COMMON+=("$NAME")
[ -n "$BANK" ] && COMMON+=(--mb "$BANK")
[ -n "$RES_JSON" ] && COMMON+=(--resource-json "$RES_JSON")

py() {
  local sub="$1"
  shift
  python3 "$PY" "$sub" "${COMMON[@]}" "$@"
}

# board <type> <title> — fail-open: a board hiccup never changes the lock outcome.
board() {
  local args=(append --type "$1" --title "$2")
  [ -n "$BANK" ] && args+=(--mb "$BANK")
  [[ "$OWNER" =~ ^[A-Za-z][A-Za-z0-9_-]{0,15}$ ]] && args+=(--track "$OWNER")
  bash "$SCRIPT_DIR/mb-coord.sh" "${args[@]}" >/dev/null 2>&1 || say "warning: board entry not written: $2"
}

need_name() { [ -n "$NAME" ] || [ -n "$RES_JSON" ] || usage; }
load_env() {
  local env
  env="$(py env)" || exit 2
  eval "$env"
}

TICKET="" TOKEN="" KEEP=0 WAITER="" WATCHER="" CHILD=0 OUT="" BREACH=""
# shellcheck disable=SC2329  # the cleanup functions run from traps
on_exit() {
  [ -n "$WAITER" ] && kill -TERM "$WAITER" 2>/dev/null
  [ -n "$WATCHER" ] && kill "$WATCHER" 2>/dev/null
  [ -n "$TICKET" ] && rm -f "$TICKET"
  if [ -z "$TOKEN" ] && [ -n "$OUT" ] && [ -s "$OUT" ]; then TOKEN="$(sed -n 's/^token=//p' "$OUT")"; fi
  if [ -n "$TOKEN" ] && [ "$KEEP" = 0 ]; then py release --token "$TOKEN" >/dev/null 2>&1; fi
  rm -f "$OUT" "$BREACH"
}
# shellcheck disable=SC2329
on_signal() {
  if [ "$CHILD" != 0 ]; then
    # The child leads its own process group; every signal becomes TERM for the whole group.
    kill -TERM -- "-$CHILD" 2>/dev/null || kill -TERM "$CHILD" 2>/dev/null
    wait "$CHILD" 2>/dev/null
  fi
  exit "$1"
}

# queue_and_wait <lease> <cmd label> — sets TOKEN or exits (75 timeout).
queue_and_wait() {
  local rc line
  trap on_exit EXIT
  trap 'on_signal 143' TERM
  trap 'on_signal 130' INT
  trap 'on_signal 129' HUP
  OUT="$(mktemp)"
  TICKET="$(py enqueue --owner "$OWNER" --pid $$)" || exit 2
  py wait --ticket "$TICKET" --pid $$ --owner "$OWNER" --wait "$WAIT" --lease "$1" --cmd "$2" >"$OUT" &
  WAITER=$!
  wait "$WAITER"
  rc=$?
  WAITER="" TICKET=""
  while IFS= read -r line; do
    case "$line" in
      token=*) TOKEN="${line#token=}" ;;
      reclaimed=*) board STATUS "resource $R_NAME: reclaimed dead lock of ${line#reclaimed=}" ;;
    esac
  done <"$OUT"
  [ "$rc" = 0 ] || exit "$rc"
  [ -n "$TOKEN" ] || die "no token from the queue" 1
}

cmd_run() {
  local rc setchild
  [ $# -gt 0 ] || die "run needs -- <command>"
  [ -n "$OWNER" ] || die "--owner is required"
  need_name
  load_env
  queue_and_wait 0 "${1##*/}" # program name only: arguments may carry tokens, and meta reaches the board
  if [ "$R_HAS_PRE" = 1 ] && ! py check --phase start; then
    if [ "$R_HAS_MAINT" = 1 ] && [ "$NO_MAINT" = 0 ]; then
      py maint --token "$TOKEN" || say "maintenance exited $?"
    fi
    py check --phase start || die "preconditions unmet for $R_NAME; the command was NOT run" 77
  fi
  say "acquired $R_NAME; running"
  # The child records its own pid before exec, so the command never runs unrecorded in meta.json.
  setchild="$(printf '%q ' python3 "$PY" setchild "${COMMON[@]}" --token "$TOKEN")"
  # Own process group (job control on for this one fork): a stop kills make/gradle workers too.
  set -m
  bash -c "$setchild"' --child $$ && exec "$@"' mb-lock-child "$@" &
  CHILD=$!
  set +m
  if [ "$R_HAS_STOP" = 1 ]; then
    BREACH="$(mktemp)" && rm -f "$BREACH"
    (while sleep "$R_WATCH"; do
      py check --phase stop || {
        : >"$BREACH"
        kill -TERM -- "-$CHILD" 2>/dev/null
        exit 0
      }
    done) >/dev/null 2>&1 &
    WATCHER=$!
  fi
  wait "$CHILD"
  rc=$?
  CHILD=0
  if [ -n "$BREACH" ] && [ -e "$BREACH" ]; then
    board BLOCKED "resource $R_NAME: stop condition"
    die "stop condition hit for $R_NAME; the command was terminated" 76
  fi
  exit "$rc"
}

cmd_acquire() {
  [ -n "$OWNER" ] || die "--owner is required"
  [ "$LEASE" != 0 ] || die "--lease S is required"
  need_name
  load_env
  queue_and_wait "$LEASE" "lease ${LEASE}s"
  KEEP=1
  printf '%s\n' "$TOKEN"
}

cmd_break() {
  local out
  need_name
  [ -n "$REASON" ] || die "--reason is required"
  load_env
  out="$(py break)" || exit $?
  if [ -n "$out" ]; then
    board STATUS "resource $R_NAME: broke dead lock of $out — $REASON"
    say "broke dead lock of $out"
  fi
}

cmd_watch() {
  local interval pre=ok stop=ok cur msg
  need_name
  load_env
  interval="${INTERVAL:-$R_WATCH}"
  while :; do
    if [ "$R_HAS_PRE" = 1 ]; then
      cur=ok && msg="$(py check --phase start 2>&1)" || cur=false
      [ "$cur" = "$pre" ] || board STATUS "resource $R_NAME: preconditions $([ "$cur" = ok ] && echo recovered || echo false): ${msg#*: }"
      pre="$cur"
    fi
    if [ "$R_HAS_STOP" = 1 ]; then
      cur=ok && msg="$(py check --phase stop 2>&1)" || cur=breached
      [ "$cur" = "$stop" ] || board STATUS "resource $R_NAME: stop threshold $([ "$cur" = ok ] && echo recovered || echo breached): ${msg#*: }"
      stop="$cur"
    fi
    sleep "$interval"
  done
}

case "$SUB" in
  run) cmd_run "$@" ;;
  acquire) cmd_acquire ;;
  release) need_name && py release --token "$TOKEN_ARG" ;;
  maint) need_name && py maint --token "$TOKEN_ARG" ;;
  status) py status ${JSON:+"$JSON"} ;;
  watch) cmd_watch ;;
  break) cmd_break ;;
  *) usage ;;
esac
