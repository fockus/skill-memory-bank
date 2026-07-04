#!/usr/bin/env bash
# mb-work-progress-append.sh — locked, atomic, append-only writer for <bank>/progress.md.
#
# Usage:
#   mb-work-progress-append.sh --text "..." [--mb <path>]
#   mb-work-progress-append.sh --file <src> [--mb <path>]
#
# Confirmed gap (I-094 S6): the /mb work loop appends to progress.md via
# free-form edits (commands/work.md 5d/end-of-run); under intra-plan
# self-claim there is no single-writer primitive, so two concurrent appends
# can interleave/clobber. This script is that primitive.
#
# Contract:
#   - Append-only: existing content is never rewritten or removed.
#   - Atomic: builds the new file content in a `mktemp` temp file, then `mv`s
#     it over progress.md — no partial write is ever visible to a reader.
#   - Serialized: an owner-token `mkdir` lock at <bank>/.work-progress.lock
#     (mirrors scripts/mb-handoff.sh::_lock_acquire/_lock_release; the
#     hooks/lib/session-common.sh lock is untouched).
#   - Fail-safe: a lock that cannot be acquired within the timeout, or any
#     write/mv error, degrades to a stderr warning + exit 0 — this helper
#     must never wedge a /mb work loop.
#
# Exit codes:
#   0  appended, or fail-safe: warned to stderr and skipped (lock/write busy)
#   2  usage error (empty/missing --text, missing/unreadable --file, both
#      --text and --file given, or neither given) — nothing is appended
#
# Env overrides (mirror MB_HANDOFF_LOCK_TIMEOUT/TTL):
#   MB_PROGRESS_APPEND_LOCK_TIMEOUT   seconds to wait for the lock (default 10)
#   MB_PROGRESS_APPEND_LOCK_TTL       seconds before a held lock is stale (default 120)

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

LOCK_TIMEOUT="${MB_PROGRESS_APPEND_LOCK_TIMEOUT:-10}"
LOCK_TTL="${MB_PROGRESS_APPEND_LOCK_TTL:-120}"

usage() {
  sed -n '2,28p' "$0" >&2
}

warn() {
  printf '[work-progress-append] %s\n' "$1" >&2
}

# Portable mtime (epoch seconds); empty if missing.
_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || true
}

# Atomic mkdir lock (no flock on macOS). Breaks a lock older than $ttl.
# Echoes an owner token ("<pid>-<rand>") on stdout on success; returns 1 on
# timeout without touching a still-fresh lock owned by someone else.
_lock_acquire() {
  local lock="$1" timeout="$2" ttl="$3" waited=0 age now token
  token="$$-${RANDOM:-0}"
  while true; do
    if mkdir "$lock" 2>/dev/null; then
      printf '%s' "$token" >"$lock/owner" 2>/dev/null || true
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

# Release a lock ONLY if we still own it (owner-token compare), mirroring
# mb-handoff.sh — a slow original must never delete a newer owner's lock.
_lock_release() {
  local lock="$1" token="${2:-}" current
  if [ -z "$token" ]; then
    return 0
  fi
  current="$(cat "$lock/owner" 2>/dev/null || true)"
  if [ "$current" = "$token" ]; then
    rm -rf "$lock" 2>/dev/null || true
  fi
}

main() {
  local text="" file="" mb_arg="" have_text=0 have_file=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --text)
        text="${2:-}"
        have_text=1
        shift 2
        ;;
      --text=*)
        text="${1#--text=}"
        have_text=1
        shift
        ;;
      --file)
        file="${2:-}"
        have_file=1
        shift 2
        ;;
      --file=*)
        file="${1#--file=}"
        have_file=1
        shift
        ;;
      --mb)
        mb_arg="${2:-}"
        shift 2
        ;;
      --mb=*)
        mb_arg="${1#--mb=}"
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        warn "unexpected arg '$1'"
        usage
        exit 2
        ;;
    esac
  done

  if [ "$have_text" -eq 1 ] && [ "$have_file" -eq 1 ]; then
    warn "--text and --file are mutually exclusive"
    usage
    exit 2
  fi

  local block=""
  if [ "$have_file" -eq 1 ]; then
    if [ -z "$file" ] || [ ! -f "$file" ] || [ ! -r "$file" ]; then
      warn "--file '$file' is missing or unreadable"
      usage
      exit 2
    fi
    block="$(cat "$file")"
  elif [ "$have_text" -eq 1 ]; then
    block="$text"
  else
    warn "one of --text or --file is required"
    usage
    exit 2
  fi

  if [ -z "$block" ]; then
    warn "nothing to append (empty --text/--file)"
    exit 2
  fi

  local bank
  bank="$(mb_resolve_path "$mb_arg")"

  if ! mkdir -p "$bank" 2>/dev/null; then
    warn "cannot create bank dir '$bank' — skipping append (fail-safe)"
    exit 0
  fi

  local progress="$bank/progress.md"
  local lock="$bank/.work-progress.lock"

  local token=""
  if ! token="$(_lock_acquire "$lock" "$LOCK_TIMEOUT" "$LOCK_TTL")"; then
    warn "could not acquire lock '$lock' within ${LOCK_TIMEOUT}s — skipping append (fail-safe, never wedges the loop)"
    exit 0
  fi
  # shellcheck disable=SC2064
  trap "_lock_release '$lock' '$token'" EXIT

  local tmp=""
  if ! tmp="$(mktemp "$bank/.progress.append.XXXXXX" 2>/dev/null)"; then
    warn "mktemp failed in '$bank' — skipping append (fail-safe)"
    exit 0
  fi

  if [ -f "$progress" ]; then
    if ! cp -p "$progress" "$tmp" 2>/dev/null; then
      warn "could not read existing progress.md — skipping append (fail-safe)"
      rm -f "$tmp" 2>/dev/null || true
      exit 0
    fi
  else
    : >"$tmp"
  fi

  if ! printf '\n%s\n' "$block" >>"$tmp" 2>/dev/null; then
    warn "write failed — skipping append (fail-safe)"
    rm -f "$tmp" 2>/dev/null || true
    exit 0
  fi

  if ! mv -f "$tmp" "$progress" 2>/dev/null; then
    warn "mv failed — could not publish append (fail-safe)"
    rm -f "$tmp" 2>/dev/null || true
    exit 0
  fi
}

main "$@"
