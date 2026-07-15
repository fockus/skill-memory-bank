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

cur8="${CLAUDE_CODE_SESSION_ID:-}"; cur8="${cur8:0:8}"   # set -u safe when unset (e.g. CI)
ARCHIVE="$SESS/archive/stubs"

# A7: does this file carry turn-bullets AFTER the first `## ` heading following `## Live log`?
# That is the signature of the pre-A1 append-after-Summary bloat that prune must repair.
_has_post_summary_bullets() {
  awk '
    /^## Live log/ { ll=1; next }
    ll && /^## /   { past=1 }
    past && /^- [0-9][0-9]:[0-9][0-9] / { found=1; exit }
    END { exit(found ? 0 : 1) }
  ' "$1"
}

stubs=0
kept=0
repair_candidates=0
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
    # A7: a substantive file over the bloat threshold WITH post-Summary bullets is a
    # repair candidate (runaway pre-A1 append). Flag on dry-run; repair on --apply.
    bloat_bytes="${MB_SESSION_BLOAT_BYTES:-40000}"
    if [ "$(wc -c < "$f" | tr -d ' ')" -gt "$bloat_bytes" ] && _has_post_summary_bullets "$f"; then
      repair_candidates=$((repair_candidates + 1))
      if [ "$APPLY" -eq 1 ]; then
        bash "$(dirname "$0")/mb-session-repair.sh" --apply "$f" >/dev/null 2>&1 || true
        echo "repaired: $base"
      else
        echo "repair-candidate: $base ($(wc -c < "$f" | tr -d ' ') bytes)"
      fi
    fi
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

# A20: best-effort, backgrounded semantic-index prune. After --apply removes
# contentless stubs, the on-disk index still references those gone sources.
# Fire-and-forget: never block, never fail this script (fail-open, exit 0 always).
reindex=0
if [ "$APPLY" -eq 1 ] && [ "$stubs" -gt 0 ]; then
  HOOK_DIR="$(cd "$(dirname "$0")/../hooks" 2>/dev/null && pwd)" || HOOK_DIR=""
  if [ -n "$HOOK_DIR" ] && [ -f "$HOOK_DIR/mb-semantic.py" ]; then
    # shellcheck source=lib/session-common.sh
    . "$HOOK_DIR/lib/session-common.sh" 2>/dev/null || true
    if command -v sc_semantic_py >/dev/null 2>&1; then
      PRUNE_PY="$(sc_semantic_py "$HOOK_DIR" "$MB_PATH")"
      if command -v "$PRUNE_PY" >/dev/null 2>&1; then
        ( MB_ROOT="$MB_PATH" "$PRUNE_PY" "$HOOK_DIR/mb-semantic.py" prune >/dev/null 2>&1 & )
        reindex=1
      fi
    fi
  fi
fi

echo "[prune] mode=$mode stubs=$stubs substantive_kept=$kept repair_candidates=$repair_candidates archive=$ARCHIVE reindex=$reindex"
