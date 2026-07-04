#!/usr/bin/env bash
# mb-session-turn.sh — Stop hook. Append one Live-log bullet for the current turn (no LLM)
# and persist the transcript path into the session-file frontmatter.
# Fail-safe: any missing dependency or unresolved Memory Bank → silent exit 0.
set -u

# 1) anti-recursion sentinel (our own claude -p subprocesses set this)
[ -n "${MB_CAPTURE_SUBPROCESS:-}" ] && exit 0

HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
JQ="${JQ:-jq}"
command -v "$JQ" >/dev/null 2>&1 || exit 0

INPUT="$(cat 2>/dev/null || true)"

# 2) Stop-recursion guard (Claude Code sets stop_hook_active on re-entrant Stop)
SHA="$(printf '%s' "$INPUT" | "$JQ" -r '.stop_hook_active // false' 2>/dev/null || echo false)"
[ "$SHA" = "true" ] && exit 0

# 3) global off-switch
[ "${MB_SESSION_CAPTURE:-auto}" = "off" ] && exit 0

CWD="$(printf '%s' "$INPUT" | "$JQ" -r '.cwd // empty' 2>/dev/null || true)"
SID="$(printf '%s' "$INPUT" | "$JQ" -r '.session_id // empty' 2>/dev/null || true)"
TRANSCRIPT="$(printf '%s' "$INPUT" | "$JQ" -r '.transcript_path // empty' 2>/dev/null || true)"
[ -n "$CWD" ] || CWD="$PWD"

# shellcheck source=lib/session-common.sh
. "$HOOK_DIR/lib/session-common.sh"

MB="$(sc_resolve_mb "$CWD")"
[ -n "$MB" ] || exit 0
[ -n "$SID" ] || exit 0

date_s="$(date +%Y-%m-%d)"
hhmm="$(date +%H%M)"
hm="$(date +%H:%M)"

mkdir -p "$MB/session" 2>/dev/null || exit 0
LOCK="$MB/session/.lock"
sc_lock "$LOCK" 10 || exit 0
trap 'sc_unlock "$LOCK"' EXIT INT TERM

# Locate this session's file by session_id (the filename minute is cosmetic only);
# create it with frontmatter on the first turn. Looking up by id — not by the current
# wall-clock minute — keeps every turn of one session in ONE file even when turns
# straddle a minute boundary. Done under the lock so find-or-create is atomic.
SF="$(sc_find_session_file "$MB" "$SID")"
[ -n "$SF" ] || SF="$(sc_session_file "$MB" "$SID" "$date_s" "$hhmm")"

# extract this turn's user text + tools + files (no LLM). The extractor also yields the turn
# ANCHOR — the uuid of the last REAL user message — which is the dedup key. The previous key
# (uuid of the transcript's LAST line) is empty whenever that line is a uuid-less record such
# as `permission-mode`/`summary`, so duplicate Stop firings from project-local + global hook
# registration slipped past the dedup and double-logged the same turn.
fields="$(bash "$HOOK_DIR/lib/extract-tools-files.sh" "$TRANSCRIPT" 2>/dev/null || true)"
user_line="$(printf '%s\n' "$fields" | sed -n 's/^user=//p')"
tools="$(printf '%s\n' "$fields" | sed -n 's/^tools=//p')"
files="$(printf '%s\n' "$fields" | sed -n 's/^files=//p')"
turn_uuid="$(printf '%s\n' "$fields" | sed -n 's/^turn=//p')"
errors="$(printf '%s\n' "$fields" | sed -n 's/^errors=//p')"
[ -n "$tools" ] || tools="(none)"
[ -n "$files" ] || files="(none)"

# Stub guard: do NOT create a session file for a contentless first turn (empty user request,
# no real tool, no file). These are short/aborted/sub-agent sessions whose transcripts are
# often already gone; a 340-byte stub per such turn just floods session/ with noise and buries
# real sessions. Once a real turn exists the file is created and every later turn is logged as
# before. Off-switch: MB_SESSION_STUB_GUARD=off.
if [ "${MB_SESSION_STUB_GUARD:-on}" != "off" ] && [ ! -f "$SF" ] \
   && [ -z "$user_line" ] && [ "$tools" = "(none)" ] && [ "$files" = "(none)" ]; then
  printf '{}\n'
  exit 0
fi

# create session file with frontmatter on first turn
if [ ! -f "$SF" ]; then
  branch="$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')"
  {
    printf -- '---\n'
    printf 'session_id: %s\n' "$SID"
    printf 'transcript: %s\n' "$TRANSCRIPT"
    printf 'started: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
    printf 'branch: %s\n' "$branch"
    printf 'turns: 0\n'
    printf 'last_turn:\n'
    printf 'summarized: false\n'
    printf -- '---\n\n## Live log\n'
  } > "$SF"
fi

# backfill transcript path if it was unknown at creation time
if [ -z "$(sc_fm_get "$SF" transcript)" ] && [ -n "$TRANSCRIPT" ]; then
  sc_fm_set "$SF" transcript "$TRANSCRIPT"
fi


# Outcome signal (REQ-009): `ok` when every tool call succeeded, `err(N)` when N
# tool_result blocks this turn carried is_error:true (counted by the extractor in
# the same turn-scoped window). No LLM call.
case "$errors" in
  ''|0|*[!0-9]*) outcome="ok" ;;
  *)             outcome="err($errors)" ;;
esac

# Aggregate diffstat (REQ-009): `+A/-B` summed from `git diff --numstat` (unstaged
# tracked changes). Contract via a SINGLE git invocation: `git diff` FAILS outside a
# work tree AND in a bare repo, so the segment is omitted entirely there (and on any
# git/missing-git failure) — those turns stay exit 0. Inside a repo it succeeds; empty
# output ⇒ `+0/-0`, which correctly means "nothing changed". Exactly one git call,
# zero git calls outside repos. Binary files report `-` in numstat; awk treats as 0.
diffstat=""
if out="$(git -C "$CWD" diff --numstat 2>/dev/null)"; then
  diffstat="$(printf '%s' "$out" | awk '{a+=($1=="-"?0:$1); d+=($2=="-"?0:$2)} END{printf "+%d/-%d", a, d}')"
fi

# Final bullet format (documented for downstream parsers — B2/C1 consume it):
#   - HH:MM — User: "<text>" · tools: <T> · files: <F> · <ok|err(N)>[ · +A/-B]
# The diffstat segment is appended only when inside a git work tree.

# dedup: skip if this turn anchor was already captured (duplicate hook registration from
# project-local + global settings firing the same Stop event, or a re-fire)
if [ -n "$turn_uuid" ] && [ "$(sc_fm_get "$SF" last_turn)" = "$turn_uuid" ]; then
  printf '{}\n'
  exit 0
fi

# Redact API keys/tokens before the bullet reaches disk (regression: an OpenRouter
# key quoted in a user message was persisted verbatim). MB_REDACT_SECRETS=off disables.
bullet="$(printf -- '- %s — User: "%s" · tools: %s · files: %s · %s' \
  "$hm" "$user_line" "$tools" "$files" "$outcome")"
[ -n "$diffstat" ] && bullet="$bullet · $diffstat"
# Splice the bullet INSIDE `## Live log` (before any `## Summary` from a resumed session),
# never blindly at EOF. On a fresh session this is a plain EOF append (identical output).
redacted_bullet="$(printf -- '%s\n' "$bullet" | sc_redact_secrets)"
sc_livelog_append "$SF" "$redacted_bullet"

# A resumed session was already summarized before this new turn arrived → invalidate the
# stale summary so the SessionStart lazy catch-up rebuilds it from the full Live log.
# `judged` is deliberately NOT reset (avoids re-spending Sonnet).
if [ "$(sc_fm_get "$SF" summarized)" = "true" ]; then
  sc_fm_set "$SF" summarized false
fi

# bump turn counter + record this turn's anchor uuid for dedup
cur="$(sc_fm_get "$SF" turns)"
[ -n "$cur" ] || cur=0
sc_fm_set "$SF" turns "$((cur + 1))"
[ -n "$turn_uuid" ] && sc_fm_set "$SF" last_turn "$turn_uuid"

printf '{}\n'
exit 0
