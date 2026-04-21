#!/bin/bash
# SessionEnd hook: weekly /mb compact reminder.
#
# Trigger: after a manual `/mb compact --apply`, `.memory-bank/.last-compact` is created.
# If >7 days have passed since then AND `mb-compact.sh --dry-run` reports `candidates > 0`,
# this hook prints a reminder to stderr.
#
# Opt-in by design:
#   - No `.memory-bank/.last-compact` → silent (the user has never run compact)
#   - `MB_COMPACT_REMIND=off` → full noop (env opt-out)
#   - Read-only: creates/changes no files

set -u

command -v jq >/dev/null 2>&1 || exit 0   # without jq — silently noop

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -z "$CWD" ] && CWD="$PWD"

MB="$CWD/.memory-bank"
[ -d "$MB" ] || exit 0

MODE="${MB_COMPACT_REMIND:-auto}"
[ "$MODE" = "off" ] && exit 0

LAST="$MB/.last-compact"
# Opt-in: if `.last-compact` does not exist, stay silent (user is not subscribed to the feature)
[ -f "$LAST" ] || exit 0

# Portable mtime
mtime() {
  stat -f%m "$1" 2>/dev/null || stat -c%Y "$1" 2>/dev/null || echo 0
}

now=$(date +%s)
age=$(( now - $(mtime "$LAST") ))
WEEK=$((7 * 24 * 3600))

# Fresh `.last-compact` → silent
[ "$age" -lt "$WEEK" ] && exit 0

# Stale → run dry-run and parse `candidates`
COMPACT_SCRIPT="$HOME/.claude/skills/memory-bank/scripts/mb-compact.sh"
# Fallback for in-repo tests: use the nearby script (`../scripts/`)
if [ ! -x "$COMPACT_SCRIPT" ]; then
  HOOK_DIR=$(cd "$(dirname "$0")" && pwd)
  REPO_COMPACT="$HOOK_DIR/../scripts/mb-compact.sh"
  [ -x "$REPO_COMPACT" ] && COMPACT_SCRIPT="$REPO_COMPACT"
fi

[ -x "$COMPACT_SCRIPT" ] || exit 0   # script unavailable — silent skip

# Run dry-run in CWD and parse `candidates=N`
OUTPUT=$(cd "$CWD" && bash "$COMPACT_SCRIPT" --dry-run 2>/dev/null; true)
CANDIDATES=$(printf '%s\n' "$OUTPUT" | grep -E '^candidates=' | head -1 | cut -d= -f2)
CANDIDATES="${CANDIDATES:-0}"

# 0 candidates — silent
[ "$CANDIDATES" = "0" ] && exit 0

# There is something to compact → reminder to stderr
age_days=$(( age / 86400 ))
{
  echo ""
  echo "[memory-bank] Compaction reminder:"
  echo "  ${CANDIDATES} candidate(s) ready for /mb compact (last compact: ${age_days}d ago)"
  echo "  Run: /mb compact --dry-run  (or /mb compact --apply to archive)"
  echo "  Silence: export MB_COMPACT_REMIND=off"
} >&2

exit 0
