#!/usr/bin/env bash
# mb-sprint-context-guard.sh — PreToolUse hook for Task (subagent dispatch).
#
# Approximates session token spend by accumulating the character length of
# every dispatched Task prompt (estimate: 1 token ≈ 4 chars). Persists state
# to <bank>/.session-spend.json via scripts/mb-session-spend.sh. Reads the
# soft / hard thresholds from pipeline.yaml:sprint_context_guard (defaults
# 150k / 190k tokens).
#
# Bank discovery order:
#   1. $MB_SESSION_BANK env var (explicit override, used by tests + /mb work)
#   2. $PWD/.memory-bank if it exists
#   3. give up (exit 0, advisory only)
#
# Exit codes:
#   0  pass (below soft, or soft warn — warning to stderr only, never blocks)
#   2  hard stop reached — block the dispatch

set -eu

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL" = "Task" ] || exit 0

# Resolve bank
BANK=""
if [ -n "${MB_SESSION_BANK:-}" ] && [ -d "$MB_SESSION_BANK" ]; then
  BANK="$MB_SESSION_BANK"
elif [ -d "${PWD:-}/.memory-bank" ]; then
  BANK="${PWD}/.memory-bank"
fi
[ -z "$BANK" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEND_SH="$SCRIPT_DIR/../scripts/mb-session-spend.sh"
if [ ! -f "$SPEND_SH" ]; then
  exit 0
fi

# Lazy-init if state missing
STATE="$BANK/.session-spend.json"
if [ ! -f "$STATE" ]; then
  bash "$SPEND_SH" init --mb "$BANK" >/dev/null 2>&1 || exit 0
fi

# Estimate dispatched chars: prompt + description
PROMPT_LEN=$(echo "$INPUT" | jq -r '(.tool_input.prompt // "") | length')
DESC_LEN=$(echo "$INPUT" | jq -r '(.tool_input.description // "") | length')
TOTAL_CHARS=$((PROMPT_LEN + DESC_LEN))

if [ "$TOTAL_CHARS" -gt 0 ]; then
  bash "$SPEND_SH" add "$TOTAL_CHARS" --mb "$BANK" >/dev/null 2>&1 || true
fi

# Apply guard
set +e
bash "$SPEND_SH" check --mb "$BANK" 2>/tmp/mb-sprint-guard-check.$$.err
RC=$?
set -e
ERR_OUT=$(cat /tmp/mb-sprint-guard-check.$$.err 2>/dev/null || true)
rm -f /tmp/mb-sprint-guard-check.$$.err

case "$RC" in
  0) exit 0 ;;
  1)
    [ -n "$ERR_OUT" ] && printf '%s\n' "$ERR_OUT" | sed 's/^/[sprint-guard] /' >&2
    echo "[sprint-guard] WARN: approaching session token threshold; consider /mb done or /compact." >&2
    exit 0
    ;;
  2)
    [ -n "$ERR_OUT" ] && printf '%s\n' "$ERR_OUT" | sed 's/^/[sprint-guard] /' >&2
    echo "[sprint-guard] BLOCKED: session token estimate reached pipeline.yaml:sprint_context_guard.hard_stop_tokens." >&2
    echo "[sprint-guard] Run /mb done + /compact + /mb start to continue." >&2
    exit 2
    ;;
  *) exit 0 ;;
esac
