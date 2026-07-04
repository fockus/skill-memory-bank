#!/usr/bin/env bash
# PreToolUse (Grep|Bash) nudge toward the Memory Bank code graph.
#
# Non-blocking: emits `additionalContext` ONLY when a structural query is
# detected AND the code graph exists AND is fresh AND we have not already nudged
# this session. Every other path prints `{}` and exits 0 — it never blocks the
# tool. Off-switch: MB_GRAPH_NUDGE=off. Coexists with block-dangerous.sh.
#
# Cheap-first ordering: off-switch + structural + graph-existence are checked
# BEFORE spawning python for the freshness gate, so the common non-code Bash call
# pays almost nothing.

set -uo pipefail

_silent() { printf '{}\n'; exit 0; }

# Anti-recursion (subprocess Claude runs) + off-switch.
[ -n "${MB_CAPTURE_SUBPROCESS:-}" ] && _silent
[ "${MB_GRAPH_NUDGE:-on}" = "off" ] && _silent

JQ="${JQ:-jq}"
command -v "$JQ" >/dev/null 2>&1 || _silent

INPUT="$(cat)"
[ -n "$INPUT" ] || _silent

TOOL="$(printf '%s' "$INPUT" | "$JQ" -r '.tool_name // empty' 2>/dev/null)" || _silent
[ -n "$TOOL" ] || _silent

# ── Structural-query detection ──
_is_structural() {
  case "$TOOL" in
    Grep) return 0 ;;  # the Grep tool is always a structural query
    Bash)
      local cmd
      cmd="$(printf '%s' "$INPUT" | "$JQ" -r '.tool_input.command // empty' 2>/dev/null)"
      [ -n "$cmd" ] || return 1
      # ripgrep is recursive by default → any `rg <pattern>` (optionally rtk-wrapped)
      # is a structural code search on its own.
      if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(rtk[[:space:]]+)?rg([[:space:]]|$)'; then
        return 0
      fi
      # grep/egrep are NOT recursive by default → only structural with a recursive
      # flag, an include filter, or an explicit source path/extension.
      printf '%s' "$cmd" \
        | grep -qE '(^|[;&|[:space:]])(rtk[[:space:]]+)?(grep|egrep)([[:space:]]|$)' || return 1
      printf '%s' "$cmd" \
        | grep -qE '(-[a-zA-Z]*[rR]|--include|--glob|src/|\.py|\.ts|\.go|\.js|\.rs|\.java)' || return 1
      return 0
      ;;
    *) return 1 ;;
  esac
}
_is_structural || _silent

# ── Resolve project + graph (honor MB_PATH override for global-mode storage) ──
CWD="$(printf '%s' "$INPUT" | "$JQ" -r '.cwd // empty' 2>/dev/null)"
[ -n "$CWD" ] || CWD="$PWD"
MB="${MB_PATH:-$CWD/.memory-bank}"
GRAPH="$MB/codebase/graph.json"
[ -f "$GRAPH" ] || _silent   # absent graph → cheap exit, no python

# ── Freshness gate (only past the cheap guards) ──
PY="${PYTHON:-python3}"
command -v "$PY" >/dev/null 2>&1 || _silent
HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || _silent
GQ="$HOOK_DIR/../scripts/mb-graph-query.py"
[ -f "$GQ" ] || GQ="$HOME/.claude/skills/memory-bank/scripts/mb-graph-query.py"
[ -f "$GQ" ] || _silent

STATUS="$("$PY" "$GQ" status --graph "$GRAPH" --src-root "$CWD" --json 2>/dev/null || true)"
printf '%s' "$STATUS" | "$JQ" -e '.exists==true and .stale==false' >/dev/null 2>&1 || _silent

# ── Throttle: at most one nudge per session ──
SESSION="${CLAUDE_SESSION_ID:-$(date +%Y%m%d%H 2>/dev/null || echo bucket)}"
MARKER="$MB/.index/.graph-nudge.$SESSION"
[ -e "$MARKER" ] && _silent
mkdir -p "$MB/.index" 2>/dev/null || true
: > "$MARKER" 2>/dev/null || true

MSG="Structural query detected. If the code graph is fresh, prefer:
  python3 ~/.claude/skills/memory-bank/scripts/mb-graph-query.py impact|neighbors|tests --graph .memory-bank/codebase/graph.json --symbol <Name>
(deterministic who-calls/blast-radius/tests). Grep stays fine for regex/raw text."

# shellcheck disable=SC2016 # $c is a jq variable bound via --arg, not a shell expansion.
"$JQ" -n --arg c "$MSG" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}'
exit 0
