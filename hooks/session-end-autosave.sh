#!/bin/bash
# SessionEnd hook: Memory Bank auto-capture.
#   - If .memory-bank/.session-lock is fresh (<1h), /mb done already ran;
#     clear the lock and exit.
#   - Otherwise (when MB_AUTO_CAPTURE=auto), append a placeholder entry
#     to progress.md (append-only, idempotent by session_id).
#   - MB_AUTO_CAPTURE=off → full noop. =strict → skip with a hint.
#   - Concurrent-safe: .auto-lock protects against duplicate quick invocations.
#   - Full actualization remains part of manual /mb done (Sonnet); this hook writes
#     a Haiku-ready placeholder that MB Manager can expand in the next session.

set -u

command -v jq >/dev/null 2>&1 || exit 0   # without jq — silently noop

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -z "$CWD" ] && CWD="$PWD"

MB="$CWD/.memory-bank"
[ -d "$MB" ] || exit 0

MODE="${MB_AUTO_CAPTURE:-auto}"
LOCK="$MB/.session-lock"
AUTO_LOCK="$MB/.auto-lock"
MAX_LOCK_AGE=3600  # 1 hour
MAX_AUTO_LOCK_AGE=30

# Portable mtime
mtime() {
  stat -f%m "$1" 2>/dev/null || stat -c%Y "$1" 2>/dev/null || echo 0
}

now=$(date +%s)

# ═══ Lock file: marker for manual /mb done ═══
if [ -f "$LOCK" ]; then
  age=$(( now - $(mtime "$LOCK") ))
  if [ "$age" -lt "$MAX_LOCK_AGE" ]; then
    rm -f "$LOCK"
    exit 0
  fi
  # Stale lock — remove it and continue with auto-capture.
  rm -f "$LOCK"
fi

# ═══ Mode dispatch ═══
case "$MODE" in
  off)
    exit 0
    ;;
  strict)
    printf '[MB strict] explicit /mb done expected (no .session-lock), auto-capture skipped\n' >&2
    exit 0
    ;;
  auto)
    ;;  # fall through
  *)
    printf '[MB] unknown MB_AUTO_CAPTURE=%s (expected auto|strict|off), skipping\n' "$MODE" >&2
    exit 0
    ;;
esac

# ═══ Concurrent guard ═══
if [ -f "$AUTO_LOCK" ]; then
  auto_age=$(( now - $(mtime "$AUTO_LOCK") ))
  if [ "$auto_age" -lt "$MAX_AUTO_LOCK_AGE" ]; then
    exit 0
  fi
  rm -f "$AUTO_LOCK"
fi
touch "$AUTO_LOCK"
trap 'rm -f "$AUTO_LOCK"' EXIT INT TERM

# ═══ progress.md ═══
PROGRESS="$MB/progress.md"
[ -f "$PROGRESS" ] || exit 0   # do not create it here — that is /mb init's job

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
SID_PREFIX=$(printf '%s' "$SID" | cut -c1-8)
TODAY=$(date +%Y-%m-%d)

# Idempotency: if the same session/day is already recorded, do nothing.
if grep -q "Auto-capture.*${SID_PREFIX}" "$PROGRESS" 2>/dev/null; then
  exit 0
fi

{
  printf '\n## %s\n\n' "$TODAY"
  printf '### Auto-capture %s (session %s)\n' "$TODAY" "$SID_PREFIX"
  printf -- '- Session ended without an explicit /mb done\n'
  printf -- '- Details will be reconstructed on the next /mb start (MB Manager can read the transcript)\n'
} >> "$PROGRESS"

exit 0
