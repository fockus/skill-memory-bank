#!/usr/bin/env bash
# mb-session-start.sh — SessionStart hook. Inject _recent.md as `# Recent Sessions`.
# Read-only: runs even while MB_SESSION_CAPTURE=off. macOS-safe: drains stdin first
# (common.sh-style `INPUT=$(cat)` would block on `claude --resume` without EOF on macOS).
set -u
exec < /dev/null

HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || { printf '{}\n'; exit 0; }
# shellcheck source=lib/session-common.sh
. "$HOOK_DIR/lib/session-common.sh"

CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
MB="$(sc_resolve_mb "$CWD")"
[ -n "$MB" ] || { printf '{}\n'; exit 0; }

RECENT="$MB/session/_recent.md"
[ -f "$RECENT" ] || { printf '{}\n'; exit 0; }
content="$(cat "$RECENT")"
[ -n "$content" ] || { printf '{}\n'; exit 0; }

# semantic: warm + catch-up reindex in background (never blocks startup)
if [ "${MB_SEMANTIC:-auto}" != "off" ]; then
  _PY="$MB/.venv/bin/python"; [ -x "$_PY" ] || _PY="python3"
  if command -v "$_PY" >/dev/null 2>&1; then
    ( "$_PY" "$MB/bin/mb-semantic.py" reindex --incremental >/dev/null 2>&1 & ) >/dev/null 2>&1
  fi
fi

# Quick-reference cheat-sheet on how to use the project's memory tools.
# Rides along with the Recent Sessions injection; disable with MB_SESSION_CHEATSHEET=off.
recent_block="$(printf '# Recent Sessions\n\n%s' "$content")"
if [ "${MB_SESSION_CHEATSHEET:-on}" = "off" ]; then
  ctx="$recent_block"
else
  cheat="$(cat <<'EOF'
# How to use project memory (quick ref)
- Code structure ("who calls/imports X", "how does X relate to Y") → graph/code-graph queries (graphify / `/mb graph`), not raw grep.
- Past chats ("what did we decide about X", "was this done before") → `/mb recall <query>` (semantic + lexical over session/ + notes/).
- Project state (status / plans / decisions / lessons) → Memory Bank core files via `/mb context`.
- The `# Relevant Memory` (per-prompt) and `# Recent Sessions` (below) blocks are auto-injected past-session context — use them.
EOF
)"
  ctx="$(printf '%s\n\n%s' "$cheat" "$recent_block")"
fi

JQ="${JQ:-jq}"
if command -v "$JQ" >/dev/null 2>&1; then
  # shellcheck disable=SC2016  # $c is a jq variable (--arg c), not a shell expansion
  "$JQ" -n --arg c "$ctx" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
elif command -v python3 >/dev/null 2>&1; then
  esc="$(printf '%s' "$ctx" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))' 2>/dev/null || true)"
  if [ -n "$esc" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$esc"
  else
    printf '{}\n'
  fi
else
  printf '{}\n'
fi
exit 0
