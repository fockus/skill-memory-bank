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

# Opt-in background code-graph rebuild (MB_GRAPH_AUTO, default off). Runs BEFORE the
# _recent.md early-exit so it fires on any active bank, not just ones with session
# history. Unlike the gitignored semantic index, graph.json is a committable /
# git-tracked artifact — a surprise background mutation would dirty the working tree,
# so this is OFF by default. When on, rebuild ONLY an existing + stale graph,
# incrementally, against the SAME tree freshness was checked against ($CWD), under a
# lock, in the background. Fail-safe: never blocks startup, always continues.
_mb_graph_auto_should_rebuild() {
  case "${MB_GRAPH_AUTO:-off}" in
    on | auto) ;;
    *) return 1 ;;
  esac
  [ -f "$MB/codebase/graph.json" ] || return 1        # first build stays manual
  command -v python3 >/dev/null 2>&1 || return 1
  local gq="$HOOK_DIR/../scripts/mb-graph-query.py"
  [ -f "$gq" ] || gq="$HOME/.claude/skills/memory-bank/scripts/mb-graph-query.py"
  [ -f "$gq" ] || return 1
  python3 "$gq" status --graph "$MB/codebase/graph.json" --src-root "$CWD" --json 2>/dev/null \
    | "${JQ:-jq}" -e '.stale==true' >/dev/null 2>&1 || return 1
  return 0
}
if _mb_graph_auto_should_rebuild; then
  _cg="$HOOK_DIR/../scripts/mb-codegraph.py"
  [ -f "$_cg" ] || _cg="$HOME/.claude/skills/memory-bank/scripts/mb-codegraph.py"
  if [ -n "${MB_GRAPH_AUTO_DRYRUN:-}" ]; then
    printf 'python3 %s --apply --docs %s %s\n' "$_cg" "$MB" "$CWD"
  else
    LOCK="$MB/.index/.graph-rebuild.lock"
    mkdir -p "$MB/.index" 2>/dev/null || true
    # mkdir is atomic → lock; a stale lock from a prior crash just skips this session
    # (a TTL cleanup is a follow-up — do NOT delete a possibly-live lock here).
    if mkdir "$LOCK" 2>/dev/null; then
      ( trap 'rmdir "$LOCK" 2>/dev/null' EXIT
        python3 "$_cg" --apply --docs "$MB" "$CWD" >/dev/null 2>&1
      ) >/dev/null 2>&1 &
    fi
  fi
fi

RECENT="$MB/session/_recent.md"
[ -f "$RECENT" ] || { printf '{}\n'; exit 0; }
content="$(cat "$RECENT")"
[ -n "$content" ] || { printf '{}\n'; exit 0; }

# A5: hard-cap the injected _recent.md so a bloated file can't silently inflate every
# session start's context. head -c is byte-based (bash-3.2 safe). Opt-out: large MB_RECENT_MAX_BYTES.
rmax="${MB_RECENT_MAX_BYTES:-4000}"
if [ "$(printf '%s' "$content" | wc -c)" -gt "$rmax" ]; then
  content="$(printf '%s' "$content" | head -c "$rmax")
…[recent truncated]…"
fi

# semantic: warm + catch-up reindex in background (never blocks startup)
if [ "${MB_SEMANTIC:-auto}" != "off" ]; then
  _PY="$(sc_semantic_py "$HOOK_DIR" "$MB")"
  if command -v "$_PY" >/dev/null 2>&1; then
    ( MB_ROOT="$MB" "$_PY" "$HOOK_DIR/mb-semantic.py" reindex --incremental >/dev/null 2>&1 & ) >/dev/null 2>&1
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

# B1: prepend a drift banner when the bank is materially behind code / dirty (empty when
# fresh — mirrors the MB_SESSION_CHEATSHEET opt-out pattern). Fail-safe: any error → no banner.
if [ "${MB_FRESHNESS_BANNER:-on}" != "off" ]; then
  FRESH="$HOOK_DIR/../scripts/mb-freshness.sh"
  [ -f "$FRESH" ] || FRESH="$HOME/.claude/skills/memory-bank/scripts/mb-freshness.sh"
  if [ -f "$FRESH" ]; then
    banner="$(bash "$FRESH" --banner "$MB" 2>/dev/null || true)"
    [ -n "$banner" ] && ctx="$(printf '%s\n\n%s' "$banner" "$ctx")"
  fi
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
