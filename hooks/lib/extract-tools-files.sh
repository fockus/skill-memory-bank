#!/usr/bin/env bash
# extract-tools-files.sh — parse the tail of a Claude Code JSONL transcript and emit the
# current turn's salient fields WITHOUT calling an LLM. "Current turn" = from the last REAL
# user message (a text prompt, not a tool_result) to the end of the transcript.
#
# NOTE: this is a PURPOSE-BUILT parser. memsearch's parse-transcript.sh deliberately SKIPS
# tool_use blocks, so it cannot supply tools/files — hence our own implementation.
#
# Usage:   extract-tools-files.sh <transcript.jsonl>
# Output:  five lines (always, even on error — fail-safe REQ-SM-007):
#            user=<last user prompt, single line, truncated>
#            tools=<comma-joined, deduped, sorted>
#            files=<comma-joined, deduped, sorted>
#            turn=<uuid of the last REAL user message — the stable per-turn dedup anchor>
#            errors=<count of failed tool calls this turn — tool_result blocks with is_error:true>
set -u

TRANSCRIPT="${1:-}"

emit_empty() { printf 'user=\ntools=\nfiles=\nturn=\nerrors=0\n'; exit 0; }

[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && [ -s "$TRANSCRIPT" ] || emit_empty
command -v python3 >/dev/null 2>&1 || emit_empty

LIBDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" python3 - "$TRANSCRIPT" <<'PY' || emit_empty
import json, os, re, sys

# A3: user-prompt cap (default 1000, was a silent 200 that made Haiku report
# "user request was truncated"). Truncation appends a single `…`. Fail-safe on bad env.
try:
    USER_MAX = int(os.environ.get("MB_SESSION_USER_MAX", "1000"))
except ValueError:
    USER_MAX = 1000

# Redact secrets in the extractor BEFORE the length cap, so a token that would straddle
# the cap boundary can never leak as a partial (the downstream bullet redaction only sees
# the already-cut text). Shares the pattern set with hooks/lib/redact.py (DRY); if the import
# fails, fall back to a no-op — the bullet-level sc_redact_secrets still runs downstream.
try:
    sys.path.insert(0, os.environ.get("LIBDIR", ""))
    from redact import redact_secrets as _redact
except Exception:
    def _redact(t):
        return t

# A4 opt-out: MB_SESSION_FILTER_WRAPPERS=off keeps harness service payloads as turns.
FILTER_WRAPPERS = os.environ.get("MB_SESSION_FILTER_WRAPPERS", "on") != "off"

path = sys.argv[1]
recs = []
try:
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                recs.append(json.loads(line))
            except Exception:
                continue
except Exception:
    print("user=\ntools=\nfiles=\nturn=\nerrors=0")
    sys.exit(0)

def msg(rec):
    m = rec.get("message")
    return m if isinstance(m, dict) else {}

# A4: service payloads the harness injects as `type=user` records are NOT human turns.
# A message wholly composed of these wrappers is dropped; a leading wrapper block on
# otherwise-human text is stripped. Conservative — only whole `<tag>…</tag>` blocks at
# the START match, so prose that merely mentions a tag name is preserved.
_WRAP_TAGS = ("task-notification", "system-reminder", "command-name",
              "command-message", "command-args", "local-command-stdout")
_WRAP_RE = [re.compile(rf"^\s*<{t}(?:\s[^>]*)?>.*?</{t}>\s*", re.DOTALL)
            for t in _WRAP_TAGS]

def _strip_wrappers(text):
    """Strip leading whole service-wrapper blocks; return the human remainder (may be '')."""
    prev = None
    while text and text != prev:
        prev = text
        for rx in _WRAP_RE:
            m = rx.match(text)
            if m:
                text = text[m.end():]
                break
    return text.strip()

def text_of(rec):
    """Return prompt text if this record is a REAL user message, else None."""
    if rec.get("type") != "user" or rec.get("isMeta"):
        return None
    content = msg(rec).get("content")
    if isinstance(content, str):
        raw = content.strip()
    elif isinstance(content, list):
        parts = [b.get("text", "") for b in content
                 if isinstance(b, dict) and b.get("type") == "text"]
        raw = " ".join(p for p in parts if p).strip()  # tool_result-only user messages -> ''
    else:
        return None
    if not raw:
        return None
    if not FILTER_WRAPPERS:
        return raw
    return _strip_wrappers(raw) or None

last_user = -1
for i, rec in enumerate(recs):
    if text_of(rec) is not None:
        last_user = i

user_text = ""
user_uuid = ""
if last_user >= 0:
    full_text = _redact(" ".join((text_of(recs[last_user]) or "").split()))
    user_text = full_text[:USER_MAX]
    if len(full_text) > USER_MAX:
        user_text += "…"
    user_uuid = recs[last_user].get("uuid", "") or ""

tools, files = set(), set()
errors = 0  # failed tool calls this turn = tool_result blocks with is_error:true
start = last_user + 1 if last_user >= 0 else 0
for rec in recs[start:]:
    rtype = rec.get("type")
    content = msg(rec).get("content")
    if not isinstance(content, list):
        continue
    for b in content:
        if not isinstance(b, dict):
            continue
        btype = b.get("type")
        # tool_use blocks live in assistant records → tool + file names
        if rtype == "assistant" and btype == "tool_use":
            name = b.get("name")
            if name:
                tools.add(name)
            inp = b.get("input") or {}
            if isinstance(inp, dict):
                for key in ("file_path", "path", "notebook_path"):
                    v = inp.get(key)
                    if isinstance(v, str) and v:
                        files.add(v)
        # tool_result blocks live in user records → outcome signal (REQ-009)
        elif rtype == "user" and btype == "tool_result" and b.get("is_error") is True:
            errors += 1

print("user=" + user_text)
print("tools=" + ",".join(sorted(tools)))
print("files=" + ",".join(sorted(files)))
print("turn=" + user_uuid)
print("errors=" + str(errors))
PY
