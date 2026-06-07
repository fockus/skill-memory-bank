#!/usr/bin/env bash
# mb-semantic-recall.sh — UserPromptSubmit: inject semantically relevant past-chat snippets.
# Fail-safe: any problem → print {} and exit 0; never block the prompt.
set -u
exec 2>/dev/null
[ -n "${MB_CAPTURE_SUBPROCESS:-}" ] && { printf '{}\n'; exit 0; }
[ "${MB_SEMANTIC:-auto}" = "off" ] && { printf '{}\n'; exit 0; }

HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || { printf '{}\n'; exit 0; }
. "$HOOK_DIR/lib/session-common.sh" 2>/dev/null || { printf '{}\n'; exit 0; }
JQ="${JQ:-jq}"; command -v "$JQ" >/dev/null 2>&1 || { printf '{}\n'; exit 0; }

INPUT="$(cat 2>/dev/null || true)"
PROMPT="$(printf '%s' "$INPUT" | "$JQ" -r '.prompt // empty' 2>/dev/null)"
CWD="$(printf '%s' "$INPUT" | "$JQ" -r '.cwd // empty' 2>/dev/null)"; [ -n "$CWD" ] || CWD="$PWD"
[ -n "$PROMPT" ] || { printf '{}\n'; exit 0; }

MB="$(sc_resolve_mb "$CWD")"; [ -n "$MB" ] || { printf '{}\n'; exit 0; }
PY="$MB/.venv/bin/python"; [ -x "$PY" ] || PY="python3"
command -v "$PY" >/dev/null 2>&1 || { printf '{}\n'; exit 0; }

# Time budget is enforced inside the CLI (portable; GNU timeout/gtimeout absent on macOS).
RESULT="$("$PY" "$MB/bin/mb-semantic.py" search "$PROMPT" \
          --top-k "${MB_SEMANTIC_TOPK:-5}" --min-score "${MB_SEMANTIC_MIN_SCORE:-0.35}" \
          --timeout "${MB_SEMANTIC_TIMEOUT:-3}" --json 2>/dev/null || true)"
[ -n "$RESULT" ] || { printf '{}\n'; exit 0; }

COUNT="$(printf '%s' "$RESULT" | "$JQ" 'length' 2>/dev/null || echo 0)"
[ "$COUNT" -gt 0 ] 2>/dev/null || { printf '{}\n'; exit 0; }

CTX="$(printf '%s' "$RESULT" | "$JQ" -r '
  "# Relevant Memory\n\n(from past sessions — semantic match)\n" +
  ([.[] | "- [" + (.kind) + "] " + (.source) + " (" + (.score|tostring) + ")\n  " +
    (.text | gsub("\n";" ") | .[0:280])] | join("\n"))' 2>/dev/null)"
[ -n "$CTX" ] || { printf '{}\n'; exit 0; }

"$JQ" -n --arg c "$CTX" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}'
exit 0
