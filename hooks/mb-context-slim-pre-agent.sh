#!/usr/bin/env bash
# mb-context-slim-pre-agent.sh — PreToolUse hook for Task (subagent dispatch).
#
# Sprint 1: advisory only.
# Sprint 2 (this version): when MB_WORK_MODE=slim and the prompt advertises
# `Plan: <path.md>` and `Stage: <N>`, run scripts/mb-context-slim.py to trim
# the prompt down to the active stage block + DoD + REQs + git diff. The
# trimmed text is emitted via JSON `hookSpecificOutput.additionalContext`
# so Claude Code surfaces it to the orchestrator without mutating the
# original tool_input (some Claude Code versions do not allow rewriting
# tool_input from a hook; additionalContext is the safe portable form).
#
# Falls open on any failure (missing trimmer, unparseable prompt, etc.) so a
# slim mode never breaks the session.

set -eu

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL" = "Task" ] || exit 0

if [ "${MB_WORK_MODE:-}" != "slim" ]; then
  exit 0
fi

PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')
if [ -z "$PROMPT" ]; then
  exit 0
fi

# Detect plan path + stage number from the prompt.
PLAN_PATH=$(printf '%s' "$PROMPT" | grep -oE '^Plan:\s*[^[:space:]]+\.md' | head -1 | sed 's/^Plan:\s*//')
STAGE_NO=$(printf '%s' "$PROMPT" | grep -oE 'Stage:\s*[0-9]+' | head -1 | sed 's/^Stage:\s*//')

if [ -z "$PLAN_PATH" ] || [ -z "$STAGE_NO" ]; then
  echo "[context-slim] MB_WORK_MODE=slim but prompt has no 'Plan: <path.md>' / 'Stage: N' markers — staying advisory." >&2
  exit 0
fi

if [ ! -f "$PLAN_PATH" ]; then
  echo "[context-slim] plan not found at '$PLAN_PATH' — staying advisory." >&2
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRIMMER="$SCRIPT_DIR/../scripts/mb-context-slim.py"
if [ ! -f "$TRIMMER" ]; then
  echo "[context-slim] trimmer missing at $TRIMMER — staying advisory." >&2
  exit 0
fi

SLIM_OUTPUT=$(printf '%s' "$PROMPT" | python3 "$TRIMMER" --plan "$PLAN_PATH" --stage "$STAGE_NO" --diff 2>/dev/null) || {
  echo "[context-slim] trimmer failed — staying advisory." >&2
  exit 0
}

if [ -z "$SLIM_OUTPUT" ]; then
  exit 0
fi

# Emit JSON output Claude Code can append as additionalContext.
SLIM_OUTPUT="$SLIM_OUTPUT" python3 - <<'PY'
import json, os, sys
slim = os.environ.get("SLIM_OUTPUT", "")
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "additionalContext": "[mb-work --slim] Trimmed context for the active stage:\n\n" + slim,
    }
}))
PY
exit 0
