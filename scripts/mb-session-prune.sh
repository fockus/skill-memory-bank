#!/usr/bin/env bash
# mb-session-prune.sh — archive contentless session stubs out of `<bank>/session/`.
#
# The Stop hook used to create a 340-byte session file for every contentless turn
# (empty user request, no real tool) — short/aborted/sub-agent sessions whose
# transcripts are often already gone. Those stubs bury the real sessions and drag
# `/mb recall` signal/noise toward zero. This archives them.
#
# Dry-run is the DEFAULT (prints, writes nothing). `--apply` MOVES each stub VERBATIM to
# `session/archive/stubs/` (many session files are untracked → `rm` would be unrecoverable).
# `--hard` deletes instead of archiving (only with --apply, use deliberately).
#
# Never touches `_recent.md`, substantive sessions, or the current session
# (CLAUDE_CODE_SESSION_ID). Idempotent.
#
# Usage: mb-session-prune.sh [--apply] [--hard] [mb_path]
set -u

source "$(dirname "$0")/_lib.sh"

APPLY=0
HARD=0
MB_ARG=""
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    --hard)  HARD=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) MB_ARG="$a" ;;
  esac
done

MB_PATH="$(mb_resolve_path "$MB_ARG")"
SESS="$MB_PATH/session"
[ -d "$SESS" ] || { echo "[prune] no session dir: $SESS"; exit 0; }

cur8="${CLAUDE_CODE_SESSION_ID:0:8}"
ARCHIVE="$SESS/archive/stubs"

stubs=0
kept=0
for f in "$SESS"/*.md; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"
  [ "$base" = "_recent.md" ] && continue
  # never touch the current session
  if [ -n "$cur8" ]; then
    case "$base" in *_"$cur8".md) continue ;; esac
  fi
  # substantive = a non-empty user request OR a real tool somewhere in the file
  if grep -qE 'User: "[^"]|tools: [A-Za-z]' "$f"; then
    kept=$((kept + 1))
    continue
  fi
  # contentless stub
  stubs=$((stubs + 1))
  if [ "$APPLY" -eq 1 ]; then
    if [ "$HARD" -eq 1 ]; then
      rm -f "$f"
    else
      mkdir -p "$ARCHIVE"
      mv "$f" "$ARCHIVE/$base"
    fi
  else
    echo "stub: $base"
  fi
done

mode="dry-run"
[ "$APPLY" -eq 1 ] && { mode="apply"; [ "$HARD" -eq 1 ] && mode="apply-hard"; }
echo "[prune] mode=$mode stubs=$stubs substantive_kept=$kept archive=$ARCHIVE"
