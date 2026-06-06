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

# dedup: skip if this exact turn was already captured (e.g. duplicate hook
# registration from project-local + global settings firing the same Stop event)
turn_uuid=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  turn_uuid="$(tail -n 1 "$TRANSCRIPT" 2>/dev/null | "$JQ" -r '.uuid // empty' 2>/dev/null || true)"
fi
if [ -n "$turn_uuid" ] && [ "$(sc_fm_get "$SF" last_turn)" = "$turn_uuid" ]; then
  printf '{}\n'
  exit 0
fi

# extract this turn's user text + tools + files (no LLM)
fields="$(bash "$HOOK_DIR/lib/extract-tools-files.sh" "$TRANSCRIPT" 2>/dev/null || true)"
user_line="$(printf '%s\n' "$fields" | sed -n 's/^user=//p')"
tools="$(printf '%s\n' "$fields" | sed -n 's/^tools=//p')"
files="$(printf '%s\n' "$fields" | sed -n 's/^files=//p')"
[ -n "$tools" ] || tools="(none)"
[ -n "$files" ] || files="(none)"

printf -- '- %s — User: "%s" · tools: %s · files: %s\n' "$hm" "$user_line" "$tools" "$files" >> "$SF"

# bump turn counter + record this turn's uuid for dedup
cur="$(sc_fm_get "$SF" turns)"
[ -n "$cur" ] || cur=0
sc_fm_set "$SF" turns "$((cur + 1))"
[ -n "$turn_uuid" ] && sc_fm_set "$SF" last_turn "$turn_uuid"

printf '{}\n'
exit 0
