#!/usr/bin/env bash
# mb-session-repair.sh — repair a session file corrupted by the pre-A1 append-after-Summary
# bug. Moves every turn-bullet that landed AFTER `## Summary` back into `## Live log`
# (preserving order + any `## Auto-notes` section), resets summarized=false so the
# SessionStart catch-up rebuilds the summary (judged left untouched), re-caps over-long
# bullets (parity with A2), and keeps a verbatim backup under session/archive/pre-repair/.
#
# Dry-run is the DEFAULT (prints, writes nothing). `--apply` performs the rewrite. Idempotent
# — a file with no post-Summary bullets is a no-op. Fail-safe: bad/missing file → message,
# exit 0 (never wedges a caller).
#
# Usage: mb-session-repair.sh [--apply] <session_file>
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
# shellcheck source=../hooks/lib/session-common.sh
. "$SCRIPT_DIR/../hooks/lib/session-common.sh"

APPLY=0
FILE=""
for a in "$@"; do
  case "$a" in
    --apply)   APPLY=1 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *)         FILE="$a" ;;
  esac
done

[ -n "$FILE" ] || { echo "[repair] usage: mb-session-repair.sh [--apply] <session_file>"; exit 0; }
[ -f "$FILE" ] || { echo "[repair] no such file: $FILE"; exit 0; }

BMAX="${MB_SESSION_BULLET_MAX:-600}"
base="$(basename "$FILE")"

# Count turn-bullets sitting AFTER the first `## ` heading that follows `## Live log`.
post="$(awk '
  /^## Live log/ { ll=1; next }
  ll && /^## /   { past=1 }
  past && /^- [0-9][0-9]:[0-9][0-9] / { c++ }
  END { print c+0 }
' "$FILE" 2>/dev/null || echo 0)"

if [ "$post" -eq 0 ]; then
  echo "[repair] clean (no post-Summary bullets): $base"
  exit 0
fi

echo "[repair] $base: $post post-Summary bullet(s) to move back into Live log"
if [ "$APPLY" -ne 1 ]; then
  echo "[repair] mode=dry-run (pass --apply to rewrite)"
  exit 0
fi

# 1) verbatim backup (session files are often untracked → never rm the original)
BACKUP_DIR="$(cd "$(dirname "$FILE")" 2>/dev/null && pwd)/archive/pre-repair"
mkdir -p "$BACKUP_DIR" 2>/dev/null || { echo "[repair] cannot create backup dir"; exit 0; }
ts="$(date +%Y%m%d%H%M%S)"
cp "$FILE" "$BACKUP_DIR/$base.$ts" 2>/dev/null || { echo "[repair] backup failed"; exit 0; }

# 2) move post-Summary turn-bullets into Live log + re-cap over-long bullets (parity A2).
# The file is redacted FIRST (sc_redact_secrets), so the re-cap substr below can never split a
# secret across the cut — any raw token a legacy bullet still carries becomes [REDACTED] before
# any truncation. Idempotent (already-[REDACTED] text is unchanged). Then a single awk pass
# splices moved bullets just before the first `## ` heading following Live log.
tmp="${FILE}.repair.$$"
if sc_redact_secrets < "$FILE" | awk -v bmax="$BMAX" '
    function recap(s){ return (length(s) > bmax) ? substr(s, 1, bmax) "…" : s }
    function fix(s){ return (s ~ /^- [0-9][0-9]:[0-9][0-9] /) ? recap(s) : s }
    { line[NR] = $0 }
    END {
      n = NR; ll = 0; cut = 0
      for (i = 1; i <= n; i++) {
        if (line[i] ~ /^## Live log/) { ll = 1; continue }
        if (ll && line[i] ~ /^## /)   { cut = i; break }
      }
      if (cut == 0) { for (i = 1; i <= n; i++) print fix(line[i]); exit }
      m = 0
      for (i = cut; i <= n; i++)
        if (line[i] ~ /^- [0-9][0-9]:[0-9][0-9] /) { moved[++m] = line[i]; skip[i] = 1 }
      for (i = 1; i < cut; i++)        print fix(line[i])
      for (j = 1; j <= m; j++)         print recap(moved[j])
      for (i = cut; i <= n; i++)       if (!skip[i]) print fix(line[i])
    }
  ' > "$tmp" 2>/dev/null; then
  mv "$tmp" "$FILE" 2>/dev/null || { rm -f "$tmp"; echo "[repair] write failed"; exit 0; }
else
  rm -f "$tmp"; echo "[repair] transform failed"; exit 0
fi

# 3) invalidate the stale summary so catch-up rebuilds from the repaired Live log;
#    judged is deliberately NOT reset (avoids re-spending Sonnet).
sc_fm_set "$FILE" summarized false

echo "[repair] done: $base (backup: $BACKUP_DIR/$base.$ts)"
exit 0
