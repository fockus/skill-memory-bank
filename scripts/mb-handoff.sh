#!/usr/bin/env bash
# mb-handoff.sh — handoff capsule manager (handoff-v2, Stage 1).
#
# Usage:
#   mb-handoff.sh --actualize [mb_path] [trigger]   build handoff/latest.md
#   mb-handoff.sh --read      [mb_path]             print latest.md (exit 1 if absent)
#   mb-handoff.sh --rotate [N] [mb_path]            prune archive/ to N newest (default 10)
#
# --actualize collects active_plan, recent progress, unchecked checklist items and
# HIGH backlog items into a <=1500-char capsule. Any pre-existing latest.md is moved
# to archive/<ISO>.md before the new one is written.
#
# `trigger` defaults to manual_update; override via the positional arg or
# MB_HANDOFF_TRIGGER. session_id comes from $MB_SESSION_ID when set.
#
# Portability: the single-writer lock is mkdir-based (macOS has no flock / timeout) —
# it mirrors hooks/lib/session-common.sh::sc_lock (atomic mkdir + stale-TTL break).
# Bank resolution goes through _lib.sh::mb_resolve_path so an explicit path arg wins.

set -euo pipefail

# Use BASH_SOURCE (not $0) so the script resolves its own dir even when sourced
# (e.g. by bats unit tests via MB_HANDOFF_SOURCE_ONLY=1 source ...).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

LOCK_TIMEOUT="${MB_HANDOFF_LOCK_TIMEOUT:-10}"
LOCK_TTL="${MB_HANDOFF_LOCK_TTL:-120}"
CAP=1500
ROTATE_KEEP_DEFAULT=10

# Portable mtime (epoch seconds); empty if missing.
_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# Atomic mkdir lock (no flock on macOS). Breaks a lock older than LOCK_TTL.
# Returns 0 on acquire, non-zero on timeout. On acquire, writes a unique owner
# token to "$lock/owner" and echoes it on stdout so the caller can prove
# ownership at release time (see _lock_release). Token = "<pid>-<rand>".
_lock_acquire() {
  local lock="$1" timeout="$2" ttl="$3" waited=0 age now token
  token="$$-${RANDOM:-0}"
  while true; do
    if mkdir "$lock" 2>/dev/null; then
      printf '%s' "$token" > "$lock/owner" 2>/dev/null || true
      printf '%s' "$token"
      return 0
    fi
    age="$(_mtime "$lock")"
    if [ -n "$age" ]; then
      now="$(date +%s)"
      if [ "$((now - age))" -gt "$ttl" ]; then
        rm -rf "$lock" 2>/dev/null || true
        continue
      fi
    fi
    if [ "$waited" -ge "$timeout" ]; then
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
}

# Release a lock ONLY if we still own it. The owner token written at acquire is
# compared against the on-disk token; a mismatch means a newer writer took over
# (a slow original must not delete a fresh owner's lock), so we leave it alone.
_lock_release() {
  local lock="$1" token="${2:-}" current
  if [ -z "$token" ]; then
    # No token to prove ownership → conservatively do nothing.
    return 0
  fi
  current="$(cat "$lock/owner" 2>/dev/null || true)"
  if [ "$current" = "$token" ]; then
    rm -rf "$lock" 2>/dev/null || true
  fi
}

# ISO-8601 UTC instant for the `created:` frontmatter, e.g. 2026-06-15T12:34:56Z.
_iso_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# Colon-free archive-filename stamp (design.md:107,128), e.g. 2026-06-15T123456Z.
# Colons are illegal on some filesystems and break the rotate test's glob.
_archive_stamp() {
  date -u +%Y-%m-%dT%H%M%SZ
}

# Build latest.md, archiving a pre-existing one first. Locked single-writer.
cmd_actualize() {
  local mb="$1" trigger="$2"
  local hdir="$mb/handoff"
  local lock="$hdir/.lock"
  local latest="$hdir/latest.md"
  local archive="$hdir/archive"

  mkdir -p "$hdir"

  local token
  if ! token="$(_lock_acquire "$lock" "$LOCK_TIMEOUT" "$LOCK_TTL")"; then
    printf '[mb-handoff] could not acquire lock %s within %ss\n' "$lock" "$LOCK_TIMEOUT" >&2
    return 1
  fi
  # shellcheck disable=SC2064
  trap "_lock_release '$lock' '$token'" EXIT

  local session_id="${MB_SESSION_ID:-null}"
  local created
  created="$(_iso_now)"

  # Render the capsule body (data collection + 1500-char truncation in Python).
  local tmp="$hdir/.latest.tmp.$$"
  if ! "${MB_PYTHON:-python3}" -m memory_bank_skill.handoff_capsule build \
        --bank "$mb" \
        --created "$created" \
        --trigger "$trigger" \
        --session-id "$session_id" \
        --cap "$CAP" >"$tmp"; then
    rm -f "$tmp" 2>/dev/null || true
    _lock_release "$lock" "$token"
    trap - EXIT
    printf '[mb-handoff] capsule build failed\n' >&2
    return 1
  fi

  # Archive the previous capsule WITHOUT destroying it first: copy the old latest
  # into archive/, then atomically replace latest with the new render. If an
  # interrupt strikes before the final rename, the old latest.md is still intact.
  if [ -f "$latest" ]; then
    mkdir -p "$archive"
    local stamp
    stamp="$(_archive_stamp)"
    local dest="$archive/$stamp.md"
    # Guard against same-second collisions with a colon-free numeric suffix.
    if [ -e "$dest" ]; then
      dest="$archive/${stamp%Z}-$$Z.md"
    fi
    cp -p "$latest" "$dest"
  fi

  mv -f "$tmp" "$latest"

  _lock_release "$lock" "$token"
  trap - EXIT
  return 0
}

# Print latest.md or exit 1.
cmd_read() {
  local mb="$1"
  local latest="$mb/handoff/latest.md"
  if [ -f "$latest" ]; then
    cat "$latest"
    return 0
  fi
  return 1
}

# Prune archive/ to the N newest files by mtime.
cmd_rotate() {
  local mb="$1" keep="$2"
  local archive="$mb/handoff/archive"
  [ -d "$archive" ] || return 0

  # Sort files newest-first by mtime, drop the first $keep, delete the rest.
  local f age
  local sorted=""
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    age="$(_mtime "$f")"
    [ -n "$age" ] || age=0
    sorted+="$age	$f"$'\n'
  done < <(find "$archive" -maxdepth 1 -type f -name '*.md')

  [ -n "$sorted" ] || return 0

  printf '%s' "$sorted" \
    | sort -rn -k1,1 \
    | tail -n +"$((keep + 1))" \
    | cut -f2- \
    | while IFS= read -r f; do
        [ -n "$f" ] && rm -f "$f" 2>/dev/null || true
      done
  return 0
}

usage() {
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    --actualize)
      shift
      local mb_arg="" trigger_arg=""
      # Remaining args: optional [mb_path] [trigger], order-tolerant — a value that
      # looks like a known trigger is treated as the trigger, otherwise as the path.
      local a
      for a in "$@"; do
        case "$a" in
          manual_update|pre_compact) trigger_arg="$a" ;;
          *) [ -z "$mb_arg" ] && mb_arg="$a" || trigger_arg="$a" ;;
        esac
      done
      local mb trigger
      mb="$(mb_resolve_path "$mb_arg")"
      trigger="${trigger_arg:-${MB_HANDOFF_TRIGGER:-manual_update}}"
      ( cd "$REPO_ROOT" && cmd_actualize "$mb" "$trigger" )
      ;;
    --read)
      shift
      local mb
      mb="$(mb_resolve_path "${1:-}")"
      cmd_read "$mb"
      ;;
    --rotate)
      shift
      local keep="$ROTATE_KEEP_DEFAULT" mb_arg=""
      local a
      for a in "$@"; do
        if printf '%s' "$a" | grep -qE '^[0-9]+$'; then
          keep="$a"
        else
          mb_arg="$a"
        fi
      done
      local mb
      mb="$(mb_resolve_path "$mb_arg")"
      cmd_rotate "$mb" "$keep"
      ;;
    -h|--help|"")
      usage
      ;;
    *)
      printf '[mb-handoff] unknown subcommand: %s\n' "$cmd" >&2
      usage >&2
      return 2
      ;;
  esac
}

# Allow tests to source this file for unit-testing helper functions without
# executing the CLI entrypoint (set MB_HANDOFF_SOURCE_ONLY=1 before sourcing).
if [ -z "${MB_HANDOFF_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
