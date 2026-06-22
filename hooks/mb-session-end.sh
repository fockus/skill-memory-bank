#!/usr/bin/env bash
# mb-session-end.sh — SessionEnd hook.
#   Step 1 (Stage 3): generate a Haiku ## Summary for the session and update _recent.md.
#   Step 2 (Stage 4): gated Sonnet judge → 0–2 auto-notes.
# Idempotent by full session_id (frontmatter `summarized`). Fail-safe: any missing dependency
# or unresolved bank → silent exit 0. Anti-recursion: our own claude -p runs with
# CLAUDECODE= MB_CAPTURE_SUBPROCESS=1 + --no-session-persistence --strict-mcp-config --no-chrome.
set -u

[ -n "${MB_CAPTURE_SUBPROCESS:-}" ] && exit 0

HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
JQ="${JQ:-jq}"
CLAUDE="${CLAUDE:-claude}"
HAIKU_MODEL="${HAIKU_MODEL:-haiku}"
JUDGE_MODEL="${JUDGE_MODEL:-sonnet}"
JUDGE_MIN_TURNS="${MB_JUDGE_MIN_TURNS:-4}"

command -v "$JQ" >/dev/null 2>&1 || exit 0
[ "${MB_SESSION_CAPTURE:-auto}" = "off" ] && exit 0

INPUT="$(cat 2>/dev/null || true)"
CWD="$(printf '%s' "$INPUT" | "$JQ" -r '.cwd // empty' 2>/dev/null || true)"
SID="$(printf '%s' "$INPUT" | "$JQ" -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$CWD" ] || CWD="$PWD"

# shellcheck source=lib/session-common.sh
. "$HOOK_DIR/lib/session-common.sh"

MB="$(sc_resolve_mb "$CWD")"
[ -n "$MB" ] || exit 0
[ -n "$SID" ] || exit 0

# locate session file by full session_id (filename carries only sid8)
sid8="${SID:0:8}"
SF="$(sc_find_session_file "$MB" "$SID")"
[ -n "$SF" ] || exit 0

# Decoupled idempotency. `summarized` gates the Haiku summary; `judged` gates the Sonnet
# judge independently, so a later run can re-do ONLY the still-pending judge. The summarizer
# (below) acquires session/.lock itself; we deliberately do NOT hold it here (self-deadlock).
already_summarized=false; [ "$(sc_fm_get "$SF" summarized)" = "true" ] && already_summarized=true
already_judged=false;     [ "$(sc_fm_get "$SF" judged)" = "true" ]     && already_judged=true
[ "$already_summarized" = true ] && [ "$already_judged" = true ] && exit 0
command -v "$CLAUDE" >/dev/null 2>&1 || exit 0

# === Step 1: Haiku summary — delegated to mb-session-summarize.sh (the SAME summarizer the
# SessionStart lazy catch-up uses). It locks session/.lock internally, self-gates on
# `summarized`, applies the empty-session guard, writes `## Summary` + summary_schema, and
# rotates _recent.md. Run WITHOUT the lock held here so the two never deadlock.
if [ "$already_summarized" != true ]; then
  CLAUDE="$CLAUDE" HAIKU_MODEL="$HAIKU_MODEL" bash "$HOOK_DIR/mb-session-summarize.sh" "$SF"
fi

# === Step 2: gated Sonnet judge -> 0-2 auto-notes ===
# Already judged on an earlier run -> nothing left to do (decoupled idempotency).
[ "$already_judged" = true ] && exit 0
# Operator kill-switch for note-noise: MB_SESSION_JUDGE=off skips the judge (summary still ran).
[ "${MB_SESSION_JUDGE:-on}" = "off" ] && exit 0
# judge-gate: only spend Sonnet on "significant" sessions (had Write/Edit, or long enough).
significant=false
grep -qE 'tools: [^·]*(Edit|Write|NotebookEdit)' "$SF" && significant=true
turns="$(sc_fm_get "$SF" turns)"
[ -n "$turns" ] || turns=0
[ "$turns" -ge "$JUDGE_MIN_TURNS" ] && significant=true
[ "$significant" = true ] || exit 0

# Build the judge source (shared formula with the summarizer); take the lock for the note
# writes (the summarizer released its own lock when it returned).
SRC="$(sc_build_summary_src "$SF")"
[ -n "$SRC" ] || exit 0
LOCK="$MB/session/.lock"
sc_lock "$LOCK" 30 || exit 0
trap 'sc_unlock "$LOCK"' EXIT INT TERM

# existing note titles (dedup signal for the judge)
titles=""
if [ -d "$MB/notes" ]; then
  titles="$(grep -rh '^# ' "$MB/notes"/*.md 2>/dev/null | sed 's/^# //' | head -50)"
fi

JUDGE_PROMPT="You are a strict judge deciding whether this Claude Code session produced durable, reusable knowledge worth a Memory Bank note. Qualify ONLY for: a new reusable pattern; a non-trivial architectural decision with rationale; a gotcha that saves future time; a non-trivial bug fix with a non-obvious root cause; an important project convention/config. Exclude routine edits, renames, formatting, trivial answers/translations, and anything already covered by these existing note titles:
${titles:-(none)}

Output ONLY a JSON array (no prose, no code fences) of 0 to 2 objects, each {\"title\": short title, \"body\": 3-8 lines of markdown}. If nothing qualifies, output [].

Session:
$SRC"

JUDGE_OUT="$(printf '%s' "$JUDGE_PROMPT" | env -u CLAUDECODE MB_CAPTURE_SUBPROCESS=1 "$CLAUDE" -p \
  --model "$JUDGE_MODEL" --strict-mcp-config --no-session-persistence --no-chrome 2>/dev/null || true)"

# Extract the first top-level JSON array from the judge output. The output usually carries a
# preamble: most often `[MEMORY BANK: ACTIVE]`, which the `claude -p` subprocess emits because
# it obeys the project CLAUDE.md guard — also possibly ```json fences or prose. A plain jq
# parse and a line-based sed both miss the array behind such a preamble, so we scan for the
# first position that decodes as a JSON array. jq is the fallback when python3 is unavailable.
notes_json="$(printf '%s' "$JUDGE_OUT" | python3 -c '
import sys, json
s = sys.stdin.read()
dec = json.JSONDecoder()
i, n = 0, len(s)
while i < n:
    if s[i] == "[":
        try:
            val, _ = dec.raw_decode(s, i)
        except ValueError:
            val = None
        if isinstance(val, list):
            sys.stdout.write(json.dumps(val)); break
    i += 1
' 2>/dev/null || true)"
if [ -z "$notes_json" ]; then
  notes_json="$(printf '%s' "$JUDGE_OUT" | "$JQ" -c 'if type=="array" then . else empty end' 2>/dev/null || true)"
fi
[ -n "$notes_json" ] || exit 0

count="$(printf '%s' "$notes_json" | "$JQ" 'length' 2>/dev/null || echo 0)"
[ "$count" -gt 2 ] && count=2

linklist="$MB/session/.links.$$"
: > "$linklist"
mkdir -p "$MB/notes"
i=0
while [ "$i" -lt "$count" ]; do
  title="$(printf '%s' "$notes_json" | "$JQ" -r ".[$i].title // empty")"
  body="$(printf '%s' "$notes_json" | "$JQ" -r ".[$i].body // empty")"
  if [ -n "$title" ]; then
    # Clean slug: lowercase, spaces→dash, drop non-[a-z0-9-], squeeze repeated dashes,
    # trim leading/trailing dashes (before AND after the length cap so truncation never
    # leaves a trailing "-"). Prevents junk slugs like "adr-3-gate-rule-----".
    slug="$(printf '%s' "$title" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-' \
      | tr -s '-' | sed 's/^-*//; s/-*$//' | cut -c1-50 | sed 's/-*$//')"
    [ -n "$slug" ] || slug="note"
    notefile="$MB/notes/$(date +%Y-%m-%d)_$(date +%H%M)_${slug}.md"
    [ -e "$notefile" ] && notefile="${notefile%.md}-$i.md"
    {
      printf -- '---\ntype: note\ntags: [session-memory]\nimportance: medium\nsource: session-memory\n---\n\n'
      printf '# %s\n\n' "$title"
      printf '%s\n\n' "$body"
      printf -- '---\n*Auto-captured by MB session-memory (session %s).*\n' "$sid8"
    } > "$notefile"
    printf -- '- notes/%s\n' "$(basename "$notefile")" >> "$linklist"
  fi
  i=$((i + 1))
done

if [ -s "$linklist" ]; then
  { printf '\n## Auto-notes emitted\n'; cat "$linklist"; } >> "$SF"
fi
rm -f "$linklist"

# Judge produced a valid verdict (notes, or a deliberate empty []) — mark judged so it is not
# re-run. An errored/killed judge returns no parseable array and exits above WITHOUT this flag,
# leaving the judge retryable on a later SessionEnd.
sc_fm_set "$SF" judged true

exit 0
