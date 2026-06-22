#!/usr/bin/env bash
# mb-session-summarize.sh — generate the Haiku `## Summary` for ONE session file and rotate
# `_recent.md`. Extracted from mb-session-end.sh Step 1 (DRY) so it can be driven by BOTH the
# SessionEnd hook AND the SessionStart lazy catch-up (mb-session-catchup.sh).
#
# Usage: mb-session-summarize.sh <session_file>
# Idempotent by frontmatter `summarized`. Fail-safe: any missing dependency / unresolved bank /
# already-summarized → silent exit 0. Anti-recursion: skip when MB_CAPTURE_SUBPROCESS is set.
set -u

[ -n "${MB_CAPTURE_SUBPROCESS:-}" ] && exit 0

HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
JQ="${JQ:-jq}"
CLAUDE="${CLAUDE:-claude}"
HAIKU_MODEL="${HAIKU_MODEL:-haiku}"
RECENT_KEEP="${MB_RECENT_KEEP:-5}"

command -v "$JQ" >/dev/null 2>&1 || exit 0
[ "${MB_SESSION_CAPTURE:-auto}" = "off" ] && exit 0

SF="${1:-}"
[ -n "$SF" ] && [ -f "$SF" ] || exit 0

# shellcheck source=lib/session-common.sh
. "$HOOK_DIR/lib/session-common.sh"

# Memory Bank root = parent of the session/ directory holding this file.
MB="$(cd "$(dirname "$SF")/.." 2>/dev/null && pwd)" || exit 0

LOCK="$MB/session/.lock"
sc_lock "$LOCK" 30 || exit 0
trap 'sc_unlock "$LOCK"' EXIT INT TERM

# Idempotency: `summarized` gates the Haiku summary.
[ "$(sc_fm_get "$SF" summarized)" = "true" ] && exit 0
command -v "$CLAUDE" >/dev/null 2>&1 || exit 0

# ── Empty-session guard ──────────────────────────────────────────────────────
# Skip trivial sessions before spending any LLM call: substantive only if the Live log
# carries at least one non-empty user request OR at least one real tool call. Off: MB_SESSION_EMPTY_GUARD=off.
if [ "${MB_SESSION_EMPTY_GUARD:-on}" != "off" ]; then
  _livelog="$(awk '/^## Live log/{f=1; next} f && /^## /{f=0} f' "$SF")"
  printf '%s\n' "$_livelog" | grep -qE 'User: "[^"]|tools: [A-Za-z]' || exit 0
fi

# Summary source: distilled `## Live log` (preferred) with raw-transcript fallback,
# redacted + capped — built by the single shared helper (DRY with the judge in mb-session-end.sh).
SRC="$(sc_build_summary_src "$SF")"
[ -n "$SRC" ] || exit 0

# Structured summary (REQ-010): demand EXACTLY these four markdown sections, in order.
PROMPT="Summarize this Claude Code session for a project Memory Bank. The input is a distilled per-turn log (each turn: the user request, the tools used, the files touched, the outcome, and the diffstat). Output ONLY these four markdown sections, in this exact order, with these exact headings — no preamble, no other text:

### What changed
### Decisions
### Open questions
### Files

Rules: one concise bullet per item (or a short line); be specific and factual; under each heading write \"(none)\" if there is nothing to report; never invent content not supported by the log. List concrete file paths under ### Files.

$SRC"

SUMMARY="$(printf '%s' "$PROMPT" | env -u CLAUDECODE MB_CAPTURE_SUBPROCESS=1 "$CLAUDE" -p \
  --model "$HAIKU_MODEL" --strict-mcp-config --no-session-persistence --no-chrome 2>/dev/null || true)"
[ -n "$SUMMARY" ] || exit 0

# Reject error-shaped output (context overflow, API/auth/rate errors): never store an error
# string as a summary, leave summarized=false so a later run can retry.
_sl="$(printf '%s' "$SUMMARY" | tr '[:upper:]' '[:lower:]')"
case "$_sl" in
  *"prompt is too long"*|*"tokens (limit "*|*"execution error"*|*"api error:"*|\
  *"overloaded_error"*|*"rate_limit_error"*|*"authentication_error"*|*"invalid api key"*|\
  *"context_length_exceeded"*)
    exit 0 ;;
esac

# Defense-in-depth: redact the summary too before persisting.
SUMMARY="$(printf '%s' "$SUMMARY" | sc_redact_secrets)"

# ── Schema validation (REQ-010): the `summary_schema: v2` flag must never lie ─────────────
# When the four headings appear exactly once and in canonical order, strip any leading preamble
# (e.g. a `[MEMORY BANK: ACTIVE]` status line) before `### What changed` and accept as v2.
# Otherwise store as-is with NO flag (legacy, fully parseable). Pure awk, no extra LLM call.
SUMMARY_V2=false
if STRIPPED="$(printf '%s\n' "$SUMMARY" | awk '
    BEGIN {
      rank["### What changed"]=1
      rank["### Decisions"]=2
      rank["### Open questions"]=3
      rank["### Files"]=4
      want=1
    }
    ($0 in rank) {
      r = rank[$0]
      if (!started) {
        if (r != 1) { bad=1 }
        else        { started=1; want=2; print; next }
      } else {
        if (seen[r])      { bad=1 }
        else if (r != want) { bad=1 }
        else { seen[r]=1; want++ }
      }
    }
    started { print }
    END { exit ((bad || want != 5) ? 1 : 0) }
')"; then
  SUMMARY="$STRIPPED"
  SUMMARY_V2=true
fi

# append Summary section and mark summarized (under the held lock)
printf '\n## Summary\n%s\n' "$SUMMARY" >> "$SF"
sc_fm_set "$SF" summarized true
[ "$SUMMARY_V2" = true ] && sc_fm_set "$SF" summary_schema v2

# prepend to _recent.md, keep newest N sections
RECENT="$MB/session/_recent.md"
branch="$(sc_fm_get "$SF" branch)"
[ -n "$branch" ] || branch="-"
today="$(date +%Y-%m-%d)"
hm="$(date +%H:%M)"
sid8="$(basename "$SF" .md)"; sid8="${sid8##*_}"
tmp="$RECENT.tmp.$$"
{
  printf '## %s %s (%s) — %s\n%s\n\n' "$today" "$hm" "$branch" "$sid8" "$SUMMARY"
  [ -f "$RECENT" ] && cat "$RECENT"
} | awk -v keep="$RECENT_KEEP" '
/^## /{ n++ }
{ if (n <= keep) print }
' > "$tmp"
mv "$tmp" "$RECENT"

# semantic: incremental reindex (picks up this new session) — best-effort, backgrounded
if [ "${MB_SEMANTIC:-auto}" != "off" ]; then
  _PY="$(sc_semantic_py "$HOOK_DIR" "$MB")"
  if command -v "$_PY" >/dev/null 2>&1; then
    ( MB_ROOT="$MB" "$_PY" "$HOOK_DIR/mb-semantic.py" reindex --incremental >/dev/null 2>&1 & ) >/dev/null 2>&1
  fi
fi

exit 0
