#!/usr/bin/env bats
# Stage 10 — mb-graph-nudge.sh: non-blocking PreToolUse nudge toward the code
# graph, firing ONLY when the graph exists + is fresh, throttled 1×/session,
# off-switchable, fail-safe (always {} + exit 0 on any problem; never blocks).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/mb-graph-nudge.sh"
  CWD="$(mktemp -d)"
  MB="$CWD/.memory-bank"
  mkdir -p "$MB/codebase" "$MB/.index"
}

teardown() {
  [ -n "${CWD:-}" ] && rm -rf "$CWD"
}

_graph() {  # $1 = generated_at ISO
  cat > "$MB/codebase/graph.json" <<EOF
{"type":"meta","generated_at":"$1","commit":null,"nodes":2,"edges":1}
{"type":"node","name":"x","file":"x.py"}
{"type":"node","name":"y","file":"y.py"}
{"type":"edge","src":"x.py","dst":"y","kind":"import"}
EOF
}

_fresh() { _graph "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; }
_stale() { _graph "2020-01-01T00:00:00Z"; }

_run_hook() {  # $1 = stdin JSON
  printf '%s' "$1" | PATH="$REPO_ROOT/.venv/bin:$PATH" bash "$HOOK"
}

@test "nudge fires on Grep tool when graph is fresh" {
  _fresh
  run _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mb-graph-query"* ]]
}

@test "nudge fires on rtk grep Bash when graph is fresh" {
  _fresh
  run _run_hook "{\"tool_name\":\"Bash\",\"cwd\":\"$CWD\",\"tool_input\":{\"command\":\"rtk grep -rn foo src/\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mb-graph-query"* ]]
}

@test "nudge silent when graph absent" {
  rm -f "$MB/codebase/graph.json"
  run _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" != *"mb-graph-query"* ]]
}

@test "nudge silent when graph stale" {
  _stale
  run _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" != *"mb-graph-query"* ]]
}

@test "nudge off-switch silences it" {
  _fresh
  run bash -c "printf '%s' '{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}' | MB_GRAPH_NUDGE=off PATH=\"$REPO_ROOT/.venv/bin:\$PATH\" bash \"$HOOK\""
  [ "$status" -eq 0 ]
  [[ "$output" != *"mb-graph-query"* ]]
}

@test "nudge throttled on second call in same session" {
  _fresh
  export CLAUDE_SESSION_ID="sess-abc"
  run _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mb-graph-query"* ]]
  run _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" != *"mb-graph-query"* ]]
}

@test "nudge fires on bare rg (recursive by default) when fresh" {
  _fresh
  run _run_hook "{\"tool_name\":\"Bash\",\"cwd\":\"$CWD\",\"tool_input\":{\"command\":\"rg Foo\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mb-graph-query"* ]]
}

@test "nudge ignores non-structural Bash" {
  _fresh
  run _run_hook "{\"tool_name\":\"Bash\",\"cwd\":\"$CWD\",\"tool_input\":{\"command\":\"ls -la\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" != *"mb-graph-query"* ]]
}

@test "nudge fail-safe on malformed stdin" {
  run _run_hook "not json at all {{{"
  [ "$status" -eq 0 ]
  [[ "$output" != *"mb-graph-query"* ]]
}
