#!/usr/bin/env bash
# mb-recap.sh — /mb recap <sid>: reconstruct a full progress.md entry from a
# session file via ONE Haiku `claude -p` call, replacing that session's
# auto-capture *stub* idempotently.
#
# Usage: mb-recap.sh <sid> [mb_path]
#   <sid>    session id or date (resolves to <bank>/session/<sid>*.md)
#   mb_path  optional explicit Memory Bank path (default: resolver)
#
# Contract (spec tier1-graph-memory — REQ-020, REQ-021, Scenario 8):
#   - Missing session file              → exit 2, NO writes.
#   - Ambiguous sid (matches >1 session
#     and none is an exact stem/sid8)   → exit 2, NO writes; stderr lists the
#                                         matching files so the caller can pass the
#                                         full stem or the unique sid8.
#   - Missing progress.md               → exit 2, NO writes (never created here).
#   - No `claude` binary                → exit 3, install hint, NO writes.
#   - Session already `recapped: true`  → exit 0, no-op message (idempotent).
#   - No auto-capture stub for the sid  → exit 4 (a REAL entry already exists, or
#                                         no entry at all): refuse with hint, NO writes.
#   - Stub found                        → ONE Haiku call renders a full entry; the
#                                         stub block (and only it) is replaced.
#
# Append-only discipline: only the auto-capture stub block for this session may be
# rewritten — every other progress.md entry is left byte-for-byte intact.
# Anti-recursion: the `claude -p` call runs with CLAUDECODE unset and
# MB_CAPTURE_SUBPROCESS=1 + --no-session-persistence --strict-mcp-config --no-chrome,
# exactly like hooks/mb-session-end.sh, so it never re-enters the capture hooks.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

CLAUDE="${CLAUDE:-claude}"
HAIKU_MODEL="${HAIKU_MODEL:-haiku}"
MAX_CHARS="${MB_SUMMARY_MAX_CHARS:-200000}"

# ── Self-contained frontmatter read/write (no hooks/lib dependency) ──────────
# Read a frontmatter key (between the first two `---` fences). Echoes value or nothing.
recap_fm_get() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  awk -v k="$key" '
    NR==1 && /^---$/ { infm=1; next }
    infm && /^---$/  { exit }
    infm {
      pos=index($0, ":")
      if (pos>0) {
        kk=substr($0,1,pos-1)
        gsub(/^[ \t]+/,"",kk); gsub(/[ \t]+$/,"",kk)
        if (kk==k) {
          v=substr($0,pos+1)
          gsub(/^[ \t]+/,"",v); gsub(/[ \t]+$/,"",v)
          print v; exit
        }
      }
    }
  ' "$file"
}

# Redact API keys/tokens from stdin before they reach the model or progress.md.
# Mirrors hooks/lib/session-common.sh::sc_redact_secrets (kept in sync); POSIX ERE
# only (BSD sed on macOS). Default ON; disable with MB_REDACT_SECRETS=off.
recap_redact_secrets() {
  if [ "${MB_REDACT_SECRETS:-on}" = "off" ]; then
    cat
    return 0
  fi
  sed -E \
    -e 's/sk-[A-Za-z0-9_-]{20,}/[REDACTED]/g' \
    -e 's/gh[pousr]_[A-Za-z0-9]{20,}/[REDACTED]/g' \
    -e 's/github_pat_[A-Za-z0-9_]{22,}/[REDACTED]/g' \
    -e 's/(AKIA|ASIA)[A-Z0-9]{16}/[REDACTED]/g' \
    -e 's/xox[baprs]-[A-Za-z0-9-]{10,}/[REDACTED]/g' \
    -e 's/AIza[A-Za-z0-9_-]{30,}/[REDACTED]/g' \
    -e 's/hf_[A-Za-z0-9]{30,}/[REDACTED]/g' \
    -e 's/npm_[A-Za-z0-9]{30,}/[REDACTED]/g' \
    -e 's/pypi-[A-Za-z0-9_-]{20,}/[REDACTED]/g' \
    -e 's|eyJ[A-Za-z0-9_=-]{10,}\.[A-Za-z0-9_=-]{10,}\.[A-Za-z0-9_.+/=-]{5,}|[REDACTED]|g' \
    -e 's/([Bb]earer[[:space:]]+)[A-Za-z0-9._~+/=-]{20,}/\1[REDACTED]/g' \
    -e "s/([A-Z0-9_]*(API_?KEY|TOKEN|SECRET|PASSWORD|PASSWD)[A-Z0-9_]*[[:space:]]*[=:][[:space:]]*)['\"]?[^[:space:]'\"]{8,}['\"]?/\1[REDACTED]/g"
}

# Set/replace a frontmatter key (atomic temp->mv). Assumes a frontmatter block exists.
recap_fm_set() {
  local file="$1" key="$2" value="$3"
  local tmp="${file}.tmp.$$"
  awk -v k="$key" -v v="$value" '
    BEGIN { infm=0; done=0 }
    NR==1 && /^---$/ { infm=1; print; next }
    infm && /^---$/ {
      if (!done) { print k": "v; done=1 }
      infm=0; print; next
    }
    infm {
      pos=index($0, ":")
      kk=(pos>0)?substr($0,1,pos-1):""
      gsub(/^[ \t]+/,"",kk); gsub(/[ \t]+$/,"",kk)
      if (kk==k) { print k": "v; done=1; next }
      print; next
    }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

SID="${1:-}"
if [ -z "$SID" ]; then
  echo "Usage: mb-recap.sh <sid> [mb_path]" >&2
  exit 64
fi

MB_PATH="$(mb_resolve_path "${2:-}")"
SESSION_DIR="$MB_PATH/session"
PROGRESS="$MB_PATH/progress.md"

# ── Resolve the session file ─────────────────────────────────────────────────
# Accept a date prefix (2026-06-11), an 8-char session id (431491af), or any
# unique filename stem. Match either `<sid>*.md` (date/stem prefix) or
# `*_<sid>.md` (the trailing sid8 the filename carries). Collect ALL candidates
# from both globs and de-duplicate (one file can match both patterns).
#
# Resolution rules (no silent wrong-target writes):
#   - exactly one candidate           → use it;
#   - an exact stem/sid8 match exists  → prefer it even if the prefix is ambiguous
#     (basename == "<sid>.md", or basename == "*_<sid>.md");
#   - zero candidates                  → exit 2 (no match);
#   - multiple ambiguous candidates    → exit 2, REFUSE, list the matches.
CANDIDATES=()
for f in "$SESSION_DIR/$SID"*.md "$SESSION_DIR"/*_"$SID".md; do
  [ -f "$f" ] || continue
  dup=0
  for seen in ${CANDIDATES[@]+"${CANDIDATES[@]}"}; do
    [ "$seen" = "$f" ] && { dup=1; break; }
  done
  [ "$dup" -eq 0 ] && CANDIDATES+=("$f")
done

SF=""
if [ "${#CANDIDATES[@]}" -eq 0 ]; then
  echo "mb-recap: no session file matches '$SID' under $SESSION_DIR" >&2
  exit 2
elif [ "${#CANDIDATES[@]}" -eq 1 ]; then
  SF="${CANDIDATES[0]}"
else
  # Prefer an exact filename-stem / sid8 match before declaring ambiguity —
  # but only when it is UNIQUE. A session resumed past midnight leaves two
  # files carrying the same sid8; silently picking the first glob-ordered one
  # would be a wrong-target write, so duplicate exact matches refuse too.
  EXACT=()
  for f in "${CANDIDATES[@]}"; do
    base="$(basename "$f")"
    case "$base" in
      "$SID".md|*_"$SID".md) EXACT+=("$f") ;;
    esac
  done
  if [ "${#EXACT[@]}" -eq 1 ]; then
    SF="${EXACT[0]}"
  else
    if [ "${#EXACT[@]}" -gt 1 ]; then
      AMBIG=("${EXACT[@]}")
    else
      AMBIG=("${CANDIDATES[@]}")
    fi
    echo "mb-recap: '$SID' is ambiguous — it matches multiple sessions:" >&2
    for f in "${AMBIG[@]}"; do
      echo "          - $(basename "$f")" >&2
    done
    echo "          Pass the full filename stem or the unique 8-char session id; nothing written." >&2
    exit 2
  fi
fi

# ── Idempotency: a recapped session is a no-op ───────────────────────────────
if [ "$(recap_fm_get "$SF" recapped)" = "true" ]; then
  echo "mb-recap: session $(basename "$SF") already recapped — nothing to do."
  exit 0
fi

# ── progress.md must already exist; never create it here (that is /mb init's job)
if [ ! -f "$PROGRESS" ]; then
  echo "mb-recap: $PROGRESS not found — run /mb init first; nothing written." >&2
  exit 2
fi

# ── Locate the auto-capture stub for this session ────────────────────────────
# The stub heading written by hooks/session-end-autosave.sh is:
#   ### Auto-capture <date> (session <sid8>)
# Match on the sid8 (first 8 chars of the session_id frontmatter) so the lookup
# is independent of how the caller spelled <sid>.
SID8="$(recap_fm_get "$SF" session_id)"
SID8="${SID8:0:8}"
[ -n "$SID8" ] || SID8="$SID"

if ! grep -q "^### Auto-capture .* (session ${SID8})$" "$PROGRESS" 2>/dev/null; then
  echo "mb-recap: no auto-capture stub for session ${SID8} in progress.md." >&2
  echo "          A real entry already exists, or this session was never auto-captured —" >&2
  echo "          refusing to touch progress.md (append-only)." >&2
  exit 4
fi

# ── `claude` binary required before any write ────────────────────────────────
if ! command -v "$CLAUDE" >/dev/null 2>&1; then
  echo "mb-recap: the 'claude' CLI is not installed or not on PATH; nothing written." >&2
  echo "          Install Claude Code (https://claude.com/claude-code) or set CLAUDE=<path>." >&2
  exit 3
fi

# ── Build the prompt source from the session file (redacted) ─────────────────
# Prefer the structured `## Summary` section (schema v2) when present; otherwise
# fall back to the whole session file. Redact secrets before they reach the model.
SRC="$(awk '
  /^## Summary/ { s=1; next }
  s && /^## / { s=0 }
  s { print }
' "$SF")"
if ! printf '%s' "$SRC" | grep -q '[^[:space:]]'; then
  SRC="$(cat "$SF")"
fi
SRC="$(printf '%s' "$SRC" | recap_redact_secrets)"
if [ "${#SRC}" -gt "$MAX_CHARS" ]; then
  SRC="${SRC:0:$MAX_CHARS}"
fi
[ -n "$SRC" ] || { echo "mb-recap: session $(basename "$SF") has no content to recap." >&2; exit 2; }

PROMPT="Reconstruct a single Memory Bank progress-log entry from this Claude Code session record. Output ONLY markdown bullet lines (\"- ...\"), no heading, no preamble, no code fences. Be specific and factual; cite concrete file paths when the record names them; never invent work not present in the record. If nothing substantive happened, output a single bullet saying so.

$SRC"

ENTRY="$(printf '%s' "$PROMPT" | env -u CLAUDECODE MB_CAPTURE_SUBPROCESS=1 "$CLAUDE" -p \
  --model "$HAIKU_MODEL" --strict-mcp-config --no-session-persistence --no-chrome 2>/dev/null || true)"

if ! printf '%s' "$ENTRY" | grep -q '[^[:space:]]'; then
  echo "mb-recap: the Haiku call returned no recap; progress.md left unchanged." >&2
  exit 5
fi

# Reject error-shaped output (context overflow / API errors) — never persist it.
_el="$(printf '%s' "$ENTRY" | tr '[:upper:]' '[:lower:]')"
case "$_el" in
  *"prompt is too long"*|*"tokens (limit "*|*"execution error"*|*"api error:"*|\
  *"overloaded_error"*|*"rate_limit_error"*|*"authentication_error"*|*"invalid api key"*|\
  *"context_length_exceeded"*)
    echo "mb-recap: the Haiku call returned an error response; progress.md left unchanged." >&2
    exit 5 ;;
esac

# Defense-in-depth: redact the generated entry too before persisting.
ENTRY="$(printf '%s' "$ENTRY" | recap_redact_secrets)"

# ── Replace the stub block (and only it) with the generated entry ────────────
# The stub block = the matched `### Auto-capture ...` heading through every line
# up to (but not including) the next `## ` / `### ` heading or EOF. The replacement
# keeps a `### Recap <date> (session <sid8>)` heading so the entry stays anchored
# to the session and a later run cannot mistake it for a fresh stub.
RECAP_DATE="$(recap_fm_get "$SF" started)"
RECAP_DATE="${RECAP_DATE:0:10}"
[ -n "$RECAP_DATE" ] || RECAP_DATE="$(date +%Y-%m-%d)"

ENTRY_FILE="$PROGRESS.entry.$$"
printf '### Recap %s (session %s)\n%s\n*Recap of the auto-captured session %s.*\n\n' \
  "$RECAP_DATE" "$SID8" "$ENTRY" "$SID8" > "$ENTRY_FILE"

tmp="$PROGRESS.tmp.$$"
awk -v sid8="$SID8" -v entryfile="$ENTRY_FILE" '
  BEGIN { in_stub=0; replaced=0 }
  /^### Auto-capture .* \(session / {
    if (index($0, "(session " sid8 ")") > 0 && !replaced) {
      in_stub=1; replaced=1
      while ((getline line < entryfile) > 0) print line
      close(entryfile)
      next
    }
  }
  in_stub && /^#{2,3} / { in_stub=0 }
  in_stub { next }
  { print }
' "$PROGRESS" > "$tmp"
mv "$tmp" "$PROGRESS"
rm -f "$ENTRY_FILE"

# ── Flag the session as recapped (idempotency) ───────────────────────────────
recap_fm_set "$SF" recapped true

echo "mb-recap: replaced the auto-capture stub for session ${SID8} in $PROGRESS"
exit 0
