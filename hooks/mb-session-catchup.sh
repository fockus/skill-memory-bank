#!/usr/bin/env bash
# mb-session-catchup.sh — SessionStart hook. The REAL fix for "summaries never appear":
# the SessionEnd summarizer spawns `claude -p` (Haiku, 30-90s) which the default ~60s
# SessionEnd window SIGKILLs before it writes `## Summary`. Here, at the START of a fresh
# session — a warm process with NO teardown deadline — we summarize the most recent
# substantive sessions that were left `summarized:false`, dispatched in the BACKGROUND so
# session startup is never delayed.
#
# Fail-safe: any missing dependency / unresolved bank → silent `{}` exit 0.
# Off: MB_SESSION_CAPTURE=off. Tunables: MB_CATCHUP_MAX (default 2).
# Testability seams: MB_SUMMARIZE_BIN overrides the summarizer path; MB_CATCHUP_FOREGROUND=1
# runs it synchronously (tests assert selection deterministically).
set -u

[ -n "${MB_CAPTURE_SUBPROCESS:-}" ] && { printf '{}\n'; exit 0; }
[ "${MB_SESSION_CAPTURE:-auto}" = "off" ] && { printf '{}\n'; exit 0; }

HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || { printf '{}\n'; exit 0; }
JQ="${JQ:-jq}"
CATCHUP_MAX="${MB_CATCHUP_MAX:-2}"

# Read the SessionStart payload (cwd + session_id) so we can exclude the CURRENT session.
INPUT="$(cat 2>/dev/null || true)"
CWD=""
CUR_SID=""
if command -v "$JQ" >/dev/null 2>&1; then
  CWD="$(printf '%s' "$INPUT" | "$JQ" -r '.cwd // empty' 2>/dev/null || true)"
  CUR_SID="$(printf '%s' "$INPUT" | "$JQ" -r '.session_id // empty' 2>/dev/null || true)"
fi
[ -n "$CWD" ] || CWD="${CLAUDE_PROJECT_DIR:-$PWD}"

# shellcheck source=lib/session-common.sh
. "$HOOK_DIR/lib/session-common.sh"

MB="$(sc_resolve_mb "$CWD")"
[ -n "$MB" ] || { printf '{}\n'; exit 0; }

SUMMARIZE_BIN="${MB_SUMMARIZE_BIN:-$HOOK_DIR/mb-session-summarize.sh}"
[ -f "$SUMMARIZE_BIN" ] || { printf '{}\n'; exit 0; }

dispatch() {
  if [ -n "${MB_CATCHUP_FOREGROUND:-}" ]; then
    bash "$SUMMARIZE_BIN" "$1"
  else
    # Detached double-fork (portable; macOS has no setsid): the subshell exits immediately,
    # reparenting the summarizer so it outlives this hook and never blocks startup. Mirrors
    # the background reindex pattern in mb-session-start.sh.
    ( bash "$SUMMARIZE_BIN" "$1" </dev/null >/dev/null 2>&1 & ) >/dev/null 2>&1
  fi
}

cur8="${CUR_SID:0:8}"

# Newest-first by mtime. Session filenames are `<date>_<hhmm>_<sid8>.md` (no spaces/newlines),
# so plain word-splitting of the sorted list is safe.
sorted="$(for f in "$MB"/session/*.md; do
  [ -f "$f" ] || continue
  printf '%s\t%s\n' "$(_sc_mtime "$f")" "$f"
done | sort -rn | cut -f2-)"

n=0
# shellcheck disable=SC2086  # space-free, controlled session filenames (see comment above)
for SF in $sorted; do
  [ "$n" -ge "$CATCHUP_MAX" ] && break
  base="$(basename "$SF")"
  [ "$base" = "_recent.md" ] && continue
  # exclude the current session (filename carries sid8)
  if [ -n "$cur8" ]; then
    case "$base" in *_"$cur8".md) continue ;; esac
  fi
  # skip already-summarized
  [ "$(sc_fm_get "$SF" summarized)" = "true" ] && continue
  # require real content (a non-empty user request OR a real tool)
  grep -qE 'User: "[^"]|tools: [A-Za-z]' "$SF" || continue
  dispatch "$SF"
  n=$((n + 1))
done

printf '{}\n'
exit 0
