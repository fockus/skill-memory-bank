#!/usr/bin/env bats
# master-completion Stage 2 — graph nudge suggests only real graph symbols,
# keeps one budget per subagent, and clears its own stale markers.

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REPO="$(cd "$BIN/.." && pwd)"
  TMP="$(mktemp -d)"
  MB="$TMP/.memory-bank"
  mkdir -p "$MB/codebase" "$MB/.index"
  cat > "$MB/codebase/graph.json" <<EOG
{"type": "meta", "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)", "commit": null, "nodes": 2, "edges": 0}
{"type": "node", "kind": "function", "name": "mb_resolve_path", "file": "scripts/_lib.sh", "line": 1}
{"type": "node", "kind": "class", "name": "WorkResolver", "file": "a.py", "line": 1}
EOG
}

teardown() { [ -n "${TMP:-}" ] && rm -rf "$TMP"; }

_nudge() {  # $1 = stdin JSON
  printf '%s' "$1" | PATH="$REPO/.venv/bin:$PATH" bash "$BIN/mb-graph-nudge.sh"
}

_grep_cmd() {  # $1 = shell command, $2 = extra JSON fields (leading comma)
  printf '{"tool_name":"Bash","cwd":"%s","session_id":"s1"%s,"tool_input":{"command":"%s"}}' "$TMP" "${2:-}" "$1"
}

@test "nudge never suggests a shell command as the symbol" {
  run _nudge "$(_grep_cmd 'grep -rn sed foo src/')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"who-calls <Name>"* ]]
  [[ "$output" != *"who-calls sed"* ]]
}

@test "nudge never suggests plain words like graph or pack" {
  run _nudge "$(_grep_cmd 'grep -rn graph pack src/')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"who-calls <Name>"* ]]
}

@test "nudge suggests an identifier that exists in the graph" {
  run _nudge "$(_grep_cmd 'grep -rn mb_resolve_path src/')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"who-calls mb_resolve_path"* ]]
}

@test "nudge skips an identifier that is not in the graph" {
  run _nudge "$(_grep_cmd 'grep -rn some_unknown_name src/')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"who-calls <Name>"* ]]
}

@test "two agent_ids in one session each get their own nudge budget" {
  local a b a2
  a="$(_nudge "$(_grep_cmd 'grep -rn mb_resolve_path src/' ',"agent_id":"agent-a"')")"
  b="$(_nudge "$(_grep_cmd 'grep -rn mb_resolve_path src/' ',"agent_id":"agent-b"')")"
  a2="$(_nudge "$(_grep_cmd 'grep -rn mb_resolve_path src/' ',"agent_id":"agent-a"')")"
  [[ "$a" == *"who-calls"* ]]
  [[ "$b" == *"who-calls"* ]]
  [ "$a2" = "{}" ]
  [ -f "$MB/.index/.graph-nudge.agent-a" ]
  [ -f "$MB/.index/.graph-nudge.agent-b" ]
}

@test "without agent_id the marker is keyed by session_id" {
  run _nudge "$(_grep_cmd 'grep -rn mb_resolve_path src/')"
  [ "$status" -eq 0 ]
  [ -f "$MB/.index/.graph-nudge.s1" ]
}

@test "a nudge marker older than 24 hours is removed on the next run" {
  printf '3\n' > "$MB/.index/.graph-nudge.old-session"
  touch -t 202001010000 "$MB/.index/.graph-nudge.old-session"
  run _nudge "$(_grep_cmd 'grep -rn mb_resolve_path src/')"
  [ "$status" -eq 0 ]
  [ ! -e "$MB/.index/.graph-nudge.old-session" ]
  [ -f "$MB/.index/.graph-nudge.s1" ]
}

@test "a recent nudge marker of another session survives" {
  printf '3\n' > "$MB/.index/.graph-nudge.other"
  run _nudge "$(_grep_cmd 'grep -rn mb_resolve_path src/')"
  [ "$status" -eq 0 ]
  [ -f "$MB/.index/.graph-nudge.other" ]
}
