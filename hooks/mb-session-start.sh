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

# Managed project blocks (CLAUDE.md / AGENTS.md / rule files) with a stale mb-stamp
# (I-251): one hint line naming the refresh command; MB_AUTO_REFRESH=on refreshes in
# place. Local files only, no python on the fresh path.
BLOCKS_HINT=""
_mb_lib="$HOOK_DIR/../adapters/_lib_agents_md.sh"
[ -f "$_mb_lib" ] || _mb_lib="$HOME/.claude/skills/memory-bank/adapters/_lib_agents_md.sh"
if [ -f "$_mb_lib" ]; then
  # shellcheck source=../adapters/_lib_agents_md.sh
  BLOCKS_HINT="$(. "$_mb_lib" && mb_project_blocks_hint "${MB%/.memory-bank}" 2>/dev/null)" || BLOCKS_HINT=""
fi

# _emit CONTEXT — the SessionStart JSON; the blocks hint leads the context and is also
# shown to the user (systemMessage). Nothing at all → {}.
_emit() {
  local c="$1" esc
  if [ -n "$BLOCKS_HINT" ]; then
    c="$BLOCKS_HINT${c:+$(printf '\n\n%s' "$c")}"
  fi
  [ -n "$c" ] || { printf '{}\n'; exit 0; }
  if command -v "${JQ:-jq}" >/dev/null 2>&1; then
    # shellcheck disable=SC2016  # $c/$m are jq variables, not shell expansions
    "${JQ:-jq}" -n --arg c "$c" --arg m "$BLOCKS_HINT" \
      '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}
       + (if $m == "" then {} else {systemMessage:$m} end)'
  elif command -v python3 >/dev/null 2>&1; then
    esc="$(printf '%s' "$c" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))' 2>/dev/null || true)"
    if [ -n "$esc" ]; then
      printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$esc"
    else
      printf '{}\n'
    fi
  else
    printf '{}\n'
  fi
  exit 0
}

# Opt-in code-graph freshness marking (MB_GRAPH_AUTO, default off). Runs BEFORE the
# _recent.md early-exit so it fires on any active bank, not just ones with session
# history. I-133 discipline: session-start NEVER spawns a rebuild (the old detached
# builder spawn is gone) — it only marks `.graph-dirty` on an existing +
# stale graph; the next graph query / SessionEnd catchup rebuilds inline, bounded,
# under a flock. Fail-safe: never blocks startup, always continues.
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
  if [ -n "${MB_GRAPH_AUTO_DRYRUN:-}" ]; then
    printf 'mark-dirty %s/codebase/.graph-dirty\n' "$MB"
  else
    : >> "$MB/codebase/.graph-dirty" 2>/dev/null || true
  fi
fi

# Background code-graph catch-up (AGR-044): the graph is only useful to
# implementer/verifier/reviewer if it is fresh, and nobody refreshes it by hand.
# `mb-graph-query.py catchup` is the bounded single-consumer path (non-blocking
# flock, hard MB_GRAPH_CATCHUP_BUDGET, cooldown after failure), so I-131/I-133
# hold: the hook only DISPATCHES it detached and returns immediately — no
# synchronous heavy work, no unbounded builder. Absent graph → nothing (the
# first build stays manual). Off: MB_GRAPH_CATCHUP=off.
if [ "${MB_GRAPH_CATCHUP:-on}" != "off" ] && [ -f "$MB/codebase/graph.json" ] \
  && command -v python3 >/dev/null 2>&1; then
  _cgq="$HOOK_DIR/../scripts/mb-graph-query.py"
  [ -f "$_cgq" ] || _cgq="$HOME/.claude/skills/memory-bank/scripts/mb-graph-query.py"
  if [ -f "$_cgq" ]; then
    # Detached double-fork (macOS has no setsid). The result — including an
    # honest `timed_out`/`cooldown` — lands in .graph-catchup.log instead of
    # /dev/null, so a graph that never catches up is visible, not silent.
    ( python3 "$_cgq" catchup --graph "$MB/codebase/graph.json" --src-root "$CWD" --json \
        </dev/null > "$MB/codebase/.graph-catchup.log" 2>&1 & ) >/dev/null 2>&1
  fi
fi

RECENT="$MB/session/_recent.md"
[ -f "$RECENT" ] || _emit ""
content="$(cat "$RECENT")"
[ -n "$content" ] || _emit ""

# A5: hard-cap the injected _recent.md so a bloated file can't silently inflate every
# session start's context. head -c is byte-based (bash-3.2 safe). Opt-out: large MB_RECENT_MAX_BYTES.
rmax="${MB_RECENT_MAX_BYTES:-4000}"
if [ "$(printf '%s' "$content" | wc -c)" -gt "$rmax" ]; then
  content="$(printf '%s' "$content" | head -c "$rmax")
…[recent truncated]…"
fi

# semantic: mark the index dirty — the next recall reindexes inline under a
# non-blocking flock (I-132: lifecycle hooks spawn NO detached indexers, ever)
if [ "${MB_SEMANTIC:-auto}" != "off" ]; then
  _IDX="${MB_INDEX_DIR:-$MB/.index}"
  mkdir -p "$_IDX" 2>/dev/null && : > "$_IDX/.dirty" 2>/dev/null
fi

# Quick-reference cheat-sheet on how to use the project's memory tools.
# Rides along with the Recent Sessions injection; disable with MB_SESSION_CHEATSHEET=off.
recent_block="$(printf '# Recent Sessions\n\n%s' "$content")"
if [ "${MB_SESSION_CHEATSHEET:-on}" = "off" ]; then
  ctx="$recent_block"
else
  cheat="$(cat <<'EOF'
# How to use project memory (quick ref)
- Code structure ("who calls/imports X", "how does X relate to Y") → `/mb graph` queries (`mb-graph.sh`); Grep stays fine for regex and raw text.
- Past chats & decisions ("what did we decide about X", "was this done before") → `/mb recall <query>` — model-free BM25 over agreements/progress/notes/sessions, ~50 ms, so run it before asking the user about past decisions; `/mb recall --expand <id>` opens a hit in full.
- Project state (status / plans / decisions / lessons) → Memory Bank core files via `/mb context`.
- The `# Relevant Memory` (per-prompt) and `# Recent Sessions` (below) blocks are auto-injected past-session context — use them.
EOF
)"
  # I-133: graph-freshness line — only for projects that HAVE a graph, so
  # everyone else pays nothing. Stale graphs are announced, not hidden.
  _GRAPH="$MB/codebase/graph.json"
  if [ -f "$_GRAPH" ] && command -v python3 >/dev/null 2>&1; then
    _gq="$HOOK_DIR/../scripts/mb-graph-query.py"
    [ -f "$_gq" ] || _gq="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}/scripts/mb-graph-query.py"
    if [ -f "$_gq" ]; then
      _mgs="$(cd "$(dirname "$_gq")" && pwd)/mb-graph.sh"   # resolved path: runs on any host
      gline="$(python3 "$_gq" status --graph "$_GRAPH" --src-root "$CWD" 2>/dev/null | head -1)"
      # shellcheck disable=SC2016 # literal backticks for markdown, no expansion wanted
      [ -n "$gline" ] && cheat="$(printf '%s\n- %s — query it: `bash %s who-calls|impact|tests <Name>`; refresh: `/mb graph --apply`.' "$cheat" "$gline" "$_mgs")"
    fi
  fi
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

_emit "$ctx"
