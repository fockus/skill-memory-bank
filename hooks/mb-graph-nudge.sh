#!/usr/bin/env bash
# PreToolUse (Grep|Bash) nudge toward the Memory Bank code graph.
#
# Non-blocking: emits `additionalContext` ONLY when a structural query is
# detected AND the code graph exists AND the per-session counter says it is due.
# Every other path prints `{}` and exits 0 — it never blocks the tool.
# Off-switch: MB_GRAPH_NUDGE=off. Coexists with block-dangerous.sh.
#
# Throttle (v2): one nudge per MB_GRAPH_NUDGE_EVERY structural calls (default 25)
# instead of one per session — a single nudge scrolls out of context long before
# the 7400-grep-vs-43-graph-query habit changes. The counter lives in the marker
# file itself (no new state). `--reset` wipes the counters and is wired to
# SessionStart:compact, because compaction drops the nudge from context.
#
# The message carries a candidate symbol lifted from the actual grep pattern, so
# it is a runnable command, not a generic reminder.
#
# Cheap-first ordering: off-switch + structural + graph-existence + the counter
# are checked BEFORE spawning python for the freshness gate, so the common
# non-code Bash call pays almost nothing — and 24 of every 25 structural calls
# skip python too.

set -uo pipefail

_silent() { printf '{}\n'; exit 0; }

# Anti-recursion (subprocess Claude runs) + off-switch.
[ -n "${MB_CAPTURE_SUBPROCESS:-}" ] && _silent
[ "${MB_GRAPH_NUDGE:-on}" = "off" ] && _silent

# ── SessionStart:compact reset (no stdin read: a SessionStart hook that blocks
# on `cat` hangs `claude --resume` on macOS — see mb-session-start.sh). ──
if [ "${1:-}" = "--reset" ]; then
  _RESET_MB="${MB_PATH:-${CLAUDE_PROJECT_DIR:-$PWD}/.memory-bank}"
  rm -f "$_RESET_MB"/.index/.graph-nudge.* 2>/dev/null || true
  _silent
fi

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

# ── Throttle: one nudge per N structural calls (counter in the marker file) ──
# Marker absent → nudge now; otherwise count up and stay silent until N.
EVERY="${MB_GRAPH_NUDGE_EVERY:-25}"
case "$EVERY" in '' | *[!0-9]*) EVERY=25 ;; esac
[ "$EVERY" -lt 1 ] && EVERY=1
SESSION="${CLAUDE_SESSION_ID:-$(date +%Y%m%d%H 2>/dev/null || echo bucket)}"
MARKER="$MB/.index/.graph-nudge.$SESSION"
mkdir -p "$MB/.index" 2>/dev/null || true
if [ -f "$MARKER" ]; then
  SEEN="$(head -1 "$MARKER" 2>/dev/null || echo 0)"
  case "$SEEN" in '' | *[!0-9]*) SEEN=0 ;; esac
  SEEN=$((SEEN + 1))
  if [ "$SEEN" -lt "$EVERY" ]; then
    { printf '%s\n' "$SEEN" > "$MARKER"; } 2>/dev/null || true
    _silent                        # not due → no python, no output
  fi
fi

# Due → restart the count HERE, before the freshness gate. Two reasons, both
# measured in verify Stage 1: a gate failure used to leave the counter parked at
# N, so every later call re-spawned python (WARNING-4); and a counter we cannot
# persist at all used to nudge on EVERY structural call while paying for python
# each time (WARNING-2). An unpersistable counter degrades to silence — no nudge
# is honest, a nudge on every grep is context spam. The braces matter: without
# them the redirect's own failure prints to stderr despite `2>/dev/null`.
{ printf '0\n' > "$MARKER"; } 2>/dev/null || _silent

# ── Freshness gate (only past the cheap guards) ──
PY="${PYTHON:-python3}"
command -v "$PY" >/dev/null 2>&1 || _silent
HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || _silent
GQ="$HOOK_DIR/../scripts/mb-graph-query.py"
[ -f "$GQ" ] || GQ="$HOME/.claude/skills/memory-bank/scripts/mb-graph-query.py"
[ -f "$GQ" ] || _silent

STATUS="$("$PY" "$GQ" status --graph "$GRAPH" --src-root "$CWD" --json 2>/dev/null || true)"
printf '%s' "$STATUS" | "$JQ" -e '.exists==true' >/dev/null 2>&1 || _silent
IS_STALE=0
printf '%s' "$STATUS" | "$JQ" -e '.stale==true' >/dev/null 2>&1 && IS_STALE=1

# ── Candidate symbol, so the printed command is runnable as-is. First choice: the
# identifier being DEFINED (`def foo`, `class Foo(Base)`) — on the two commonest
# real patterns the plain "last identifier" rule picked the argument or the base
# class (`--symbol target`, `--symbol Base`), which answers nothing and sends the
# agent straight back to grep (verify Stage 1, WARNING-1). Fallback: the last
# identifier, minus path-ish tokens, flags and language keywords; nothing
# survives → the generic `<Name>` placeholder stays. ──
if [ "$TOOL" = "Grep" ]; then
  RAW="$(printf '%s' "$INPUT" | "$JQ" -r '.tool_input.pattern // empty' 2>/dev/null || true)"
else
  RAW="$(printf '%s' "$INPUT" | "$JQ" -r '.tool_input.command // empty' 2>/dev/null || true)"
fi
SYMBOL="$(printf '%s' "$RAW" \
  | grep -oE '(def|class|func|function|struct|interface|type)[[:space:]]+[A-Za-z_][A-Za-z0-9_]{2,}' \
  | tail -1 | awk '{print $NF}' 2>/dev/null || true)"
[ -n "$SYMBOL" ] || SYMBOL="$(printf '%s' "$RAW" \
  | tr -c 'A-Za-z0-9_/.-' ' ' | tr ' ' '\n' \
  | grep -vE '/|\.|^-' \
  | grep -E '^[A-Za-z_][A-Za-z0-9_]{2,}$' \
  | grep -vwE 'grep|egrep|rg|rtk|xargs|head|tail|sort|uniq|cat|find|def|class|function|const|let|var|import|from|return|async|await|func|type|struct|interface|public|private|static|void' \
  | tail -1 2>/dev/null || true)"
[ -n "$SYMBOL" ] || SYMBOL="<Name>"

if [ "$IS_STALE" -eq 1 ]; then
  # I-133: a stale graph must NOT silence the nudge — the old fresh-only gate
  # created the vicious circle (stale → silent → never used → never rebuilt).
  REASON="$(printf '%s' "$STATUS" | "$JQ" -r '.reason // "unknown"' 2>/dev/null || echo unknown)"
  # Honest promise (codex I-133 r1): catch-up only fires on the dirty-queue or
  # git-HEAD drift; age-only staleness needs a manual refresh — say which.
  if [ "$REASON" = "commits" ] || [ -e "$MB/codebase/.graph-dirty" ]; then
    MSG="The code graph exists but is stale (reason: $REASON). Structural queries still work and trigger a bounded auto-catchup on the next graph query; for full freshness + analytics run: /mb graph --apply
  (or: python3 ~/.claude/skills/memory-bank/scripts/mb-codegraph.py --apply .memory-bank .). Grep stays fine for regex/raw text."
  else
    MSG="The code graph exists but is stale (reason: $REASON — no pending edits or commit drift, so an automatic refresh will not fire). Refresh manually: /mb graph --apply
  (or: python3 ~/.claude/skills/memory-bank/scripts/mb-codegraph.py --apply .memory-bank .). Queries still work on the stale graph; Grep stays fine for regex/raw text."
  fi
else
  MSG="Structural query detected — the fresh code graph answers it deterministically. Run this instead:
  python3 ~/.claude/skills/memory-bank/scripts/mb-graph-query.py impact --graph .memory-bank/codebase/graph.json --symbol $SYMBOL
(swap impact for neighbors|tests: who-calls/blast-radius vs relations vs covering tests). Grep stays fine for regex/raw text."
fi

# shellcheck disable=SC2016 # $c is a jq variable bound via --arg, not a shell expansion.
"$JQ" -n --arg c "$MSG" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}'
exit 0
