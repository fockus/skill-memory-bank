#!/usr/bin/env bash
# mb-work-codex-preflight.sh — fail-safe codex CLI availability/auth health-check.
#
# Runs BEFORE a cross-model review wave (`/mb work` step 5d dispatches
# aspect/lead reviewers through the `codex` CLI). A missing, unauthenticated,
# or misbehaving codex CLI must degrade that wave gracefully — it must never
# wedge the calling session and never fail it either. This probe is advisory
# ONLY: it ALWAYS exits 0, no matter what it finds (I-093 S8).
#
# Usage:
#   mb-work-codex-preflight.sh [--json] [--mb <path>]
#
#   --json        emit {"available":bool,"reason":str} instead of a
#                 human-readable one-line message.
#   --mb <path>   accepted for CLI parity with the other mb-work-*.sh
#                 dispatch scripts; this probe carries no bank-scoped
#                 state today, so the value is parsed and discarded.
#
# Env overrides:
#   MB_CODEX_PREFLIGHT_TIMEOUT_SECS   bound (seconds) on the auth probe
#                                     (default 5). Lower it in tests/CI
#                                     to fail fast against a hung stub.
#
# Exit code: ALWAYS 0 (advisory + fail-safe by design).

set -eu

# Bound on the `codex login status` probe. Kept short — this only guards a
# review wave dispatch decision, it must never become the slow part of a
# session.
PREFLIGHT_TIMEOUT_SECS="${MB_CODEX_PREFLIGHT_TIMEOUT_SECS:-5}"

usage() {
  cat <<'USAGE' >&2
Usage: mb-work-codex-preflight.sh [--json] [--mb <path>]

Fail-safe codex CLI availability/auth health-check for the /mb work
cross-model review wave (step 5d). ALWAYS exits 0 (advisory only).

  --json        emit {"available":bool,"reason":str}
  --mb <path>   accepted for CLI parity with other mb-work-*.sh
                dispatch scripts; parsed and currently unused.
USAGE
}

# ── portable bounded-execution helper ───────────────────────────────────────
# Prefers a native `timeout`/`gtimeout` when present. macOS ships neither by
# default (no GNU coreutils), so we fall back to a pure-bash background-
# process watchdog: race the probe against a sleeper that TERMs, then KILLs,
# it if it outlives the bound. Standard signal-derived exit codes (143 on
# TERM, 137 on KILL, matching what a native `timeout` would report as 124)
# are what the caller below classifies as "timed out" — no extra bookkeeping
# needed. Output (stdout+stderr) is inherited as usual; it is the caller's
# responsibility to redirect (e.g. `2>&1`) around the whole invocation.
mb_bounded_run() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
    return $?
  fi

  # Monitor mode (`set -m`) gives the backgrounded job its OWN process group
  # (pgid == cmd_pid), inherited by anything it forks in turn. Signalling the
  # negative pid (the whole group) is what lets us reap a probe that has
  # spawned its own children (e.g. `codex` shelling out) — signalling just
  # `cmd_pid` would leave any grandchild running, still holding the capture
  # pipe open, and the surrounding `$(...)` would then block until IT exits.
  local had_monitor=0
  case "$-" in *m*) had_monitor=1 ;; esac
  set -m
  "$@" &
  local cmd_pid=$!
  [ "$had_monitor" -eq 1 ] || set +m
  # The watchdog's own `sleep` must NOT inherit the caller's stdout/stderr:
  # if it did, that fd would stay open (a background process holding the
  # write end) for the watchdog's full duration even after cmd_pid exits on
  # its own — and `$(...)` capture at the call site waits for EOF on every
  # holder of that pipe, not just cmd_pid. Redirecting to /dev/null here
  # means the watchdog never blocks the fast (probe-finished-early) path.
  (
    sleep "$secs" 2>/dev/null || true
    kill -TERM -"$cmd_pid" 2>/dev/null || kill -TERM "$cmd_pid" 2>/dev/null || true
    sleep 0.2 2>/dev/null || true
    kill -KILL -"$cmd_pid" 2>/dev/null || kill -KILL "$cmd_pid" 2>/dev/null || true
  ) >/dev/null 2>&1 &
  local watchdog_pid=$!

  local status=0
  if wait "$cmd_pid" 2>/dev/null; then
    status=0
  else
    status=$?
  fi
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  return "$status"
}

mb_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# ── probe ────────────────────────────────────────────────────────────────────
AVAILABLE="false"
REASON=""

run_probe() {
  if ! command -v codex >/dev/null 2>&1; then
    REASON="codex CLI not found"
    return 0
  fi

  local out status
  out=$(mb_bounded_run "$PREFLIGHT_TIMEOUT_SECS" codex login status 2>&1) && status=0 || status=$?

  # 124 = native `timeout`'s convention; 137/143 = our bash watchdog's
  # SIGKILL/SIGTERM-derived exit codes for the same condition.
  if [ "$status" -eq 124 ] || [ "$status" -eq 137 ] || [ "$status" -eq 143 ]; then
    REASON="codex auth probe timed out after ${PREFLIGHT_TIMEOUT_SECS}s"
    return 0
  fi

  case "$out" in
    *403*|*Unauthorized*|*unauthorized*|*"not logged in"*|*"not authenticated"*)
      REASON="$(printf '%s' "$out" | head -n1)"
      [ -n "$REASON" ] || REASON="codex auth probe reported an authentication error"
      return 0
      ;;
  esac

  if [ "$status" -ne 0 ]; then
    REASON="$(printf '%s' "$out" | head -n1)"
    [ -n "$REASON" ] || REASON="codex auth probe exited with status $status"
    return 0
  fi

  AVAILABLE="true"
}

main() {
  local json=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json)
        json=1
        shift
        ;;
      --mb)
        shift
        if [ "$#" -gt 0 ]; then
          shift
        fi
        ;;
      --mb=*)
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        shift
        ;;
    esac
  done

  # Fail-safe wrapper: ANY unexpected failure inside run_probe (bad stub,
  # unforeseen shell error, ...) still reports available:false with a
  # generic reason and exits 0 — this health-check must never itself
  # become the reason a session blocks.
  local probe_status=0
  set +e
  run_probe
  probe_status=$?
  set -e
  if [ "$probe_status" -ne 0 ]; then
    AVAILABLE="false"
    [ -n "$REASON" ] || REASON="codex preflight probe failed unexpectedly (status $probe_status)"
  fi

  if [ "$json" -eq 1 ]; then
    printf '{"available":%s,"reason":"%s"}\n' "$AVAILABLE" "$(mb_json_escape "$REASON")"
  elif [ "$AVAILABLE" = "true" ]; then
    echo "[codex-preflight] available: codex CLI present and authenticated"
  else
    echo "[codex-preflight] unavailable: $REASON"
  fi

  exit 0
}

main "$@"
