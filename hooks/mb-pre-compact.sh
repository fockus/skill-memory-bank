#!/usr/bin/env bash
# PreCompact hook (handoff-v2): actualize the handoff capsule before compaction.
#
# On the `preCompact` event this hook invokes
#   bash scripts/mb-handoff.sh --actualize <bank> pre_compact
# which (re)writes <bank>/handoff/latest.md so the NEXT session can restore
# context from a fresh capsule instead of stale progress.md.
#
# HARD CONTRACT (design.md §9) — the hook MUST NEVER block compaction:
#   - bounded to ~2 seconds (portable: background + poll + kill, no `timeout`)
#   - on timeout / actualize failure / missing bank → one-line stderr WARN, exit 0
#   - NEVER exits non-zero.
#
# On success it prints a one-line marker to stderr so the user sees the action.
#
# Opt-out: MB_PRECOMPACT_HANDOFF=off → full noop (exit 0).
# Override the handoff script for testing via MB_HANDOFF_SCRIPT.

set -uo pipefail

# Global off-switch.
[ "${MB_PRECOMPACT_HANDOFF:-on}" = "off" ] && exit 0

# Time budget (seconds) for the actualize subprocess.
# Validate that the budget is a positive integer before using it in arithmetic.
# Any value that survives validation MUST be safe for `$(( BUDGET * 100 ))`, else a
# fatal arithmetic error leaves `deadline` unbound and aborts under `set -u` —
# violating the never-block-compaction contract.  Three traps must all be closed:
#   1. non-digit chars — use a WHOLE-STRING `case` glob, NOT line-based
#      `grep -qE '^[0-9]+$'` (grep matches per line, so $'1\nabc' would pass).
#   2. overflow — a value with >6 digits can exceed bash's 64-bit `$(( ))`
#      (wraps to garbage, no error).  Reject by STRING LENGTH (never errors) first.
#   3. octal — a leading-zero all-digit value like 08/09 is parsed as octal by
#      `$(( ))` ("value too great for base") → abort.  Normalize with `10#`.
_DEFAULT_BUDGET=2
BUDGET="${MB_PRECOMPACT_BUDGET:-$_DEFAULT_BUDGET}"
_budget_raw="$BUDGET"   # preserve the original for the warning before normalization
_budget_valid=1
case "$BUDGET" in
  '' | *[!0-9]*) _budget_valid=0 ;;   # empty or any non-digit char (newlines included)
esac
# Reject absurd lengths BEFORE any numeric op — `${#BUDGET}` (length) never errors.
[ "$_budget_valid" -eq 1 ] && [ "${#BUDGET}" -gt 6 ] && _budget_valid=0
if [ "$_budget_valid" -eq 1 ]; then
  # All-digit, ≤6 chars: force base-10 so a leading zero is not read as octal,
  # then reject zero (0 / 00 / 000).
  BUDGET=$(( 10#$BUDGET ))
  [ "$BUDGET" -le 0 ] && _budget_valid=0
fi
if [ "$_budget_valid" -eq 0 ]; then
  echo "[mb] WARN pre-compact: MB_PRECOMPACT_BUDGET='$_budget_raw' is not a positive integer; using default ${_DEFAULT_BUDGET}s" >&2
  BUDGET="$_DEFAULT_BUDGET"
fi

# Read the hook payload (JSON). Tolerate missing jq / empty input.
INPUT=$(cat 2>/dev/null || true)
CWD=""
if command -v jq >/dev/null 2>&1; then
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
fi
[ -z "$CWD" ] && CWD="$PWD"

HOOK_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
# shellcheck source=hooks/_skill_root.sh
. "$HOOK_DIR/_skill_root.sh"

# Resolve the active bank (registry-aware, honors MB_PATH/MB_AGENT). No bank → WARN + silent.
MB=""
if hit="$(mb_hook_resolve_mb_path "$CWD" 2>/dev/null || true)" && [ -n "$hit" ]; then
  MB="$hit"
fi
if [ -z "$MB" ] || [ ! -d "$MB" ]; then
  echo "[mb] WARN pre-compact: no resolvable memory bank; skipping actualize" >&2
  exit 0
fi

# Locate the handoff script (test override → bundled scripts/ → repo-relative).
HANDOFF_SCRIPT="${MB_HANDOFF_SCRIPT:-}"
if [ -z "$HANDOFF_SCRIPT" ]; then
  HANDOFF_SCRIPT="$(mb_skill_script_path "mb-handoff.sh" "$HOOK_DIR" 2>/dev/null || true)"
fi
if [ -z "$HANDOFF_SCRIPT" ] || [ ! -f "$HANDOFF_SCRIPT" ]; then
  echo "[mb] WARN pre-compact: handoff script unavailable; skipping actualize" >&2
  exit 0
fi

# Kill an entire process tree portably (macOS + Linux, no flock/timeout/setsid).
# Uses a BFS walk via `pgrep -P` to collect ALL descendants at every depth level,
# then SIGTERMs the whole set, waits briefly, then SIGKILLs any survivors.
# `pkill -P` only kills DIRECT children — that is NOT used here because it leaves
# deeper grandchildren alive when the direct child spawns its own children.
# Always returns 0; callers must `wait` the original PID to reap it.
_kill_tree() {
  local root="$1"
  # BFS: accumulate the full descendant list level by level.
  local all_pids="$root"
  local frontier="$root"
  local next_level
  while [ -n "$frontier" ]; do
    next_level=""
    for p in $frontier; do
      local children
      children=$(pgrep -P "$p" 2>/dev/null || true)
      if [ -n "$children" ]; then
        all_pids="$all_pids $children"
        next_level="$next_level $children"
      fi
    done
    frontier="$next_level"
  done

  # 1. SIGTERM the whole set (graceful shutdown attempt).
  for p in $all_pids; do
    kill -TERM "$p" 2>/dev/null || true
  done
  sleep 0.1 2>/dev/null || true

  # 2. SIGKILL survivors.
  for p in $all_pids; do
    kill -9 "$p" 2>/dev/null || true
  done
  return 0
}

# Run the actualize in its own process group so the whole tree can be killed on
# timeout.  `setsid` creates a new session+group (Linux + macOS 10.12+). When
# absent, fall back to a plain backgrounded subshell (best-effort on old platforms).
if command -v setsid >/dev/null 2>&1; then
  setsid bash "$HANDOFF_SCRIPT" --actualize "$MB" pre_compact >/dev/null 2>&1 &
else
  bash "$HANDOFF_SCRIPT" --actualize "$MB" pre_compact >/dev/null 2>&1 &
fi
worker=$!

# Poll in small slices. We track elapsed time in hundredths of a second so the
# budget stays accurate whether sub-second `sleep` is supported or not.
waited=0
deadline=$(( BUDGET * 100 ))
slice_supported=1
while kill -0 "$worker" 2>/dev/null; do
  if [ "$waited" -ge "$deadline" ]; then
    # Over budget — kill the worker tree and warn, but never block compaction.
    _kill_tree "$worker"
    wait "$worker" 2>/dev/null || true
    echo "[mb] WARN pre-compact: handoff actualize exceeded ${BUDGET}s budget; skipped (compaction not blocked)" >&2
    exit 0
  fi
  if [ "$slice_supported" -eq 1 ] && sleep 0.05 2>/dev/null; then
    waited=$(( waited + 5 ))
  else
    # No sub-second sleep on this platform — fall back to whole seconds.
    slice_supported=0
    sleep 1
    waited=$(( waited + 100 ))
  fi
done

# Worker finished within budget — reap it and read its exit status.
rc=0
wait "$worker" 2>/dev/null || rc=$?

if [ "$rc" -ne 0 ]; then
  echo "[mb] WARN pre-compact: handoff actualize failed (rc=$rc); compaction not blocked" >&2
  exit 0
fi

echo "[mb] handoff capsule actualized (pre_compact)" >&2
exit 0
