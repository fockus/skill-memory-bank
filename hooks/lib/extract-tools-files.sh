#!/usr/bin/env bash
# extract-tools-files.sh — parse the tail of a Claude Code JSONL transcript and emit the
# current turn's salient fields WITHOUT calling an LLM. "Current turn" = from the last REAL
# user message (a text prompt, not a tool_result) to the end of the transcript.
#
# NOTE: this is a PURPOSE-BUILT parser. memsearch's parse-transcript.sh deliberately SKIPS
# tool_use blocks, so it cannot supply tools/files — hence our own implementation.
#
# Usage:   extract-tools-files.sh <transcript.jsonl>
# Output:  three lines (always, even on error — fail-safe REQ-SM-007):
#            user=<last user prompt, single line, truncated>
#            tools=<comma-joined, deduped, sorted>
#            files=<comma-joined, deduped, sorted>
set -u

TRANSCRIPT="${1:-}"

emit_empty() { printf 'user=\ntools=\nfiles=\n'; exit 0; }

[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && [ -s "$TRANSCRIPT" ] || emit_empty
command -v python3 >/dev/null 2>&1 || emit_empty

python3 - "$TRANSCRIPT" <<'PY' || emit_empty
import json, sys

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
    print("user=\ntools=\nfiles=")
    sys.exit(0)

def msg(rec):
    m = rec.get("message")
    return m if isinstance(m, dict) else {}

def text_of(rec):
    """Return prompt text if this record is a REAL user message, else None."""
    if rec.get("type") != "user" or rec.get("isMeta"):
        return None
    content = msg(rec).get("content")
    if isinstance(content, str):
        return content.strip() or None
    if isinstance(content, list):
        parts = [b.get("text", "") for b in content
                 if isinstance(b, dict) and b.get("type") == "text"]
        joined = " ".join(p for p in parts if p).strip()
        return joined or None  # tool_result-only user messages -> None
    return None

last_user = -1
for i, rec in enumerate(recs):
    if text_of(rec) is not None:
        last_user = i

user_text = ""
if last_user >= 0:
    user_text = " ".join((text_of(recs[last_user]) or "").split())[:200]

tools, files = set(), set()
start = last_user + 1 if last_user >= 0 else 0
for rec in recs[start:]:
    if rec.get("type") != "assistant":
        continue
    content = msg(rec).get("content")
    if not isinstance(content, list):
        continue
    for b in content:
        if not isinstance(b, dict) or b.get("type") != "tool_use":
            continue
        name = b.get("name")
        if name:
            tools.add(name)
        inp = b.get("input") or {}
        if isinstance(inp, dict):
            for key in ("file_path", "path", "notebook_path"):
                v = inp.get(key)
                if isinstance(v, str) and v:
                    files.add(v)

print("user=" + user_text)
print("tools=" + ",".join(sorted(tools)))
print("files=" + ",".join(sorted(files)))
PY
