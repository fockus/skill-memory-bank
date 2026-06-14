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
RECENT_KEEP="${MB_RECENT_KEEP:-5}"

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

LOCK="$MB/session/.lock"
sc_lock "$LOCK" 30 || exit 0
trap 'sc_unlock "$LOCK"' EXIT INT TERM

# Decoupled idempotency. `summarized` gates the Haiku summary; `judged` gates the Sonnet
# judge — independently. Older hook versions (and runs whose judge was killed by the
# SessionEnd 180s budget) leave summarized=true but judged unset; a single shared flag used
# to short-circuit the judge forever. Tracking them apart lets a later SessionEnd re-run ONLY
# the still-pending judge with the full budget.
already_summarized=false; [ "$(sc_fm_get "$SF" summarized)" = "true" ] && already_summarized=true
already_judged=false;     [ "$(sc_fm_get "$SF" judged)" = "true" ]     && already_judged=true
[ "$already_summarized" = true ] && [ "$already_judged" = true ] && exit 0
command -v "$CLAUDE" >/dev/null 2>&1 || exit 0

# ── Empty-session guard ──────────────────────────────────────────────────────
# Skip trivial sessions before spending any LLM call. A session is substantive only
# if its Live log carries at least one non-empty user request OR at least one real
# tool call (anything other than "(none)"). Empty-prompt turns (User: "" · tools:
# (none)) would otherwise get a full Haiku summary and flood _recent.md and the
# semantic index with "no substantive work" noise. Only gates not-yet-summarized
# sessions, so a substantive session whose judge was killed can still be re-judged
# on a later SessionEnd. Off-switch: MB_SESSION_EMPTY_GUARD=off.
if [ "${MB_SESSION_EMPTY_GUARD:-on}" != "off" ] && [ "$already_summarized" != true ]; then
  _livelog="$(awk '/^## Live log/{f=1; next} f && /^## /{f=0} f' "$SF")"
  printf '%s\n' "$_livelog" | grep -qE 'User: "[^"]|tools: [A-Za-z]' || exit 0
fi

# Summary source (REQ-011). The PRIMARY input is the session's own distilled `## Live log`
# (frontmatter + per-turn bullets: request · tools · files · ok|err(N)[ · +A/-B]) plus the
# outcome signals it already carries — a structured, deterministic, redacted-at-write-time
# record. We deliberately do NOT feed the raw transcript tail: it is lossy, oversized (raw
# JSONL reaches tens of MB, which made `claude -p` emit "Prompt is too long"), and unstructured.
# Raw-transcript fallback: a session whose Live log is contentless falls back to the raw
# transcript. Under the DEFAULT config this branch is unreachable — the empty-session guard
# above (MB_SESSION_EMPTY_GUARD=on) already exits for exactly the same condition (no real
# request and no real tool in the Live log). The fallback therefore serves only the documented
# MB_SESSION_EMPTY_GUARD=off toggle: with the guard disabled, a contentless Live log still gets
# summarized from the raw transcript instead of being silently dropped.
MAX_CHARS="${MB_SUMMARY_MAX_CHARS:-200000}"
# Frontmatter block (between the first two `---`) + the `## Live log` section ONLY.
# Stop printing at the NEXT `## ` heading after Live log: a re-run session file may already
# carry a generated `## Summary` / `## Auto-notes emitted` section below the Live log, and
# feeding those back in would let a previously generated summary masquerade as per-turn bullets.
LIVELOG="$(awk '
  NR==1 && /^---$/ { print; fm=1; next }
  fm && /^---$/    { print; fm=0; next }
  fm               { print; next }
  ll && /^## / && !/^## Live log/ { ll=0 }
  /^## Live log/   { ll=1 }
  ll               { print }
' "$SF")"
if printf '%s\n' "$LIVELOG" | grep -qE 'User: "[^"]|tools: [A-Za-z]'; then
  SRC="$LIVELOG"
else
  # Empty/contentless Live log → fall back to the raw transcript when it fits the window.
  TRANSCRIPT="$(sc_fm_get "$SF" transcript)"
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && [ "$(wc -c < "$TRANSCRIPT")" -le "$MAX_CHARS" ]; then
    SRC="$(cat "$TRANSCRIPT")"
  else
    SRC="$LIVELOG"
  fi
fi
[ -n "$SRC" ] || exit 0

# Redact API keys/tokens BEFORE the source ever reaches the summarizer or the judge —
# a secret that never enters the prompt cannot reappear in a persisted summary/note.
# MB_REDACT_SECRETS=off disables. (Live-log lines are already redacted at write time;
# this covers the raw-transcript path.)
SRC="$(printf '%s' "$SRC" | sc_redact_secrets)"

# Final guard: bound even the Live-log (cheap no-op when already small) so the prompt always fits.
if [ "${#SRC}" -gt "$MAX_CHARS" ]; then
  head_n=$(( MAX_CHARS * 6 / 10 ))
  tail_n=$(( MAX_CHARS - head_n ))
  tail_start=$(( ${#SRC} - tail_n ))
  SRC="$(printf '%s\n…[transcript truncated for summary]…\n%s' "${SRC:0:head_n}" "${SRC:tail_start}")"
fi

# ── Step 1: Haiku summary + _recent rotation (only when not already summarized) ──────────────
if [ "$already_summarized" != true ]; then
  # Structured summary (REQ-010): demand EXACTLY these four markdown sections so downstream
  # consumers can parse the result deterministically. The input below is the distilled Live log.
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

  # Reject error-shaped output (context overflow, API/auth/rate errors). Defense-in-depth on
  # top of the cap above: never store an error string as a summary, and leave summarized=false
  # so a later SessionEnd can retry. Patterns are error signatures, not prose, to avoid
  # false-rejecting a legitimate summary that merely discusses limits or errors.
  _sl="$(printf '%s' "$SUMMARY" | tr '[:upper:]' '[:lower:]')"
  case "$_sl" in
    *"prompt is too long"*|*"tokens (limit "*|*"execution error"*|*"api error:"*|\
    *"overloaded_error"*|*"rate_limit_error"*|*"authentication_error"*|*"invalid api key"*|\
    *"context_length_exceeded"*)
      exit 0 ;;
  esac

  # Defense-in-depth: redact the summary too before persisting (the model could in
  # principle echo a secret it saw in an earlier, unredacted context).
  SUMMARY="$(printf '%s' "$SUMMARY" | sc_redact_secrets)"

  # ── Schema validation (REQ-010): the `summary_schema: v2` flag must never lie ─────────────
  # The flag's contract is "present ⇒ the stored summary really carries the four headings, in
  # order", so downstream consumers (the _recent rebuild, the code-graph wiki) can parse it
  # deterministically. The summarizer output is NOT trusted blindly: a known preamble such as
  # `[MEMORY BANK: ACTIVE]` (the user's global CLAUDE.md mandates it as the first response line)
  # or any malformed response would otherwise be stamped v2 and break that parser contract.
  #
  # When the four headings appear in the exact required order, strip any leading preamble lines
  # before the first `### What changed` (status line / stray prose) and accept as v2. Otherwise
  # store the summary as-is with NO flag — legacy treatment, fully parseable, the flag stays
  # honest. Pure awk; no new dependency, no extra LLM call.
  #
  # Strict heading state machine (I-069): the four recognized v2 headings must each appear AT
  # MOST ONCE and in the canonical order What changed → Decisions → Open questions → Files. A
  # duplicate recognized heading, or a recognized heading that appears out of canonical position
  # (e.g. ### Decisions before ### What changed, or ### Files before ### Decisions), rejects v2 —
  # otherwise the lying flag would break the deterministic single-section parser downstream.
  # Unrecognized `### ...` lines and ordinary prose are NOT headings: they are printed through
  # and never advance or trip the machine.
  SUMMARY_V2=false
  if STRIPPED="$(printf '%s\n' "$SUMMARY" | awk '
      BEGIN {
        rank["### What changed"]=1
        rank["### Decisions"]=2
        rank["### Open questions"]=3
        rank["### Files"]=4
        want=1   # canonical rank of the next recognized heading we expect
      }
      # A line is a recognized v2 heading only if it matches one of the four exactly.
      ($0 in rank) {
        r = rank[$0]
        # Start at the first "### What changed"; any recognized heading before it is out of order.
        if (!started) {
          if (r != 1) { bad=1 }
          else        { started=1; want=2; print; next }
        } else {
          if (seen[r])      { bad=1 }   # duplicate recognized heading
          else if (r != want) { bad=1 } # out-of-canonical-order recognized heading
          else { seen[r]=1; want++ }
        }
      }
      # Print only from the first recognized "### What changed" onward (drops leading preamble).
      started { print }
      # Reject as soon as any rule is violated, or unless all four were consumed in order.
      END { exit ((bad || want != 5) ? 1 : 0) }
  ')"; then
    SUMMARY="$STRIPPED"
    SUMMARY_V2=true
  fi

  # append Summary section and mark summarized (under the held lock)
  printf '\n## Summary\n%s\n' "$SUMMARY" >> "$SF"
  sc_fm_set "$SF" summarized true
  # Mark the schema ONLY for a validated four-section summary so consumers know it follows the
  # fixed template. Malformed/legacy-shaped output is stored as-is and carries no flag (it stays
  # fully parseable); the flag must never advertise a structure that is not actually present.
  [ "$SUMMARY_V2" = true ] && sc_fm_set "$SF" summary_schema v2

  # prepend to _recent.md, keep newest N sections
  RECENT="$MB/session/_recent.md"
  branch="$(sc_fm_get "$SF" branch)"
  [ -n "$branch" ] || branch="-"
  today="$(date +%Y-%m-%d)"
  hm="$(date +%H:%M)"
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
fi

# ── Step 2: gated Sonnet judge → 0–2 auto-notes ──────────────────────────────
# Already judged on an earlier SessionEnd → nothing left to do (decoupled idempotency).
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
