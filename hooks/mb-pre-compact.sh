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
BUDGET="${MB_PRECOMPACT_BUDGET:-2}"

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

# Kill an entire process group/tree portably (macOS + Linux, no flock/timeout).
# Tries: SIGTERM the group (setsid was used) → SIGKILL descendants via pkill -P
# (Linux) or pgrep/kill tree walk → finally SIGKILL the direct PID.  Always
# returns 0; callers must `wait` to reap.
_kill_tree() {
  local pid="$1"
  # 1. Try SIGTERM to the process group (set via setsid below).
  kill -- "-$pid" 2>/dev/null || true
  sleep 0.1 2>/dev/null || true
  # 2. Kill descendants by parent PID (pkill -P is available on both platforms).
  pkill -9 -P "$pid" 2>/dev/null || true
  # 3. SIGKILL the direct PID in case it was not in its own group.
  kill -9 "$pid" 2>/dev/null || true
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
