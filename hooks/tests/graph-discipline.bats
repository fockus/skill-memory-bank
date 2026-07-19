#!/usr/bin/env bats
# I-133 — spawn discipline + dirty-queue for the code-graph layer.
# Same contract as the semantic layer (I-132, spawn-discipline.bats): lifecycle
# hooks and git hooks only MARK the graph dirty; the rebuild happens inline in
# the next graph query / SessionEnd catchup, under a non-blocking flock with a
# hard budget. No detached `mb-codegraph.py … &` anywhere, ever.

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REPO="$(cd "$BIN/.." && pwd)"
  TMP="$(mktemp -d)"
  MB="$TMP/.memory-bank"
  mkdir -p "$MB/codebase" "$MB/session"
}

teardown() { [ -n "${TMP:-}" ] && rm -rf "$TMP"; }

_graph() {  # $1 = generated_at ISO
  cat > "$MB/codebase/graph.json" <<EOF
{"type":"meta","generated_at":"$1","commit":null,"nodes":2,"edges":1}
{"type":"node","name":"x","file":"x.py"}
{"type":"node","name":"y","file":"y.py"}
{"type":"edge","src":"x.py","dst":"y","kind":"import"}
EOF
}

@test "no hook or script detaches mb-codegraph.py into the background" {
  run grep -nE 'mb-codegraph\.py[^)]*&' \
    "$BIN/mb-session-start.sh" "$BIN/mb-session-summarize.sh" \
    "$BIN/git/post-commit-codegraph.sh"
  [ "$status" -ne 0 ]
}

@test "file-change-log appends a source edit to the graph dirty-queue" {
  _graph "2026-01-01T00:00:00Z"
  printf 'x' > "$TMP/thing.py"
  run bash -c "printf '%s' '{\"tool_name\":\"Edit\",\"cwd\":\"$TMP\",\"tool_input\":{\"file_path\":\"$TMP/thing.py\"}}' | HOME='$TMP' bash '$BIN/file-change-log.sh'"
  [ "$status" -eq 0 ]
  grep -q "thing.py" "$MB/codebase/.graph-dirty"
}

@test "file-change-log leaves no dirty-queue when the graph does not exist" {
  printf 'x' > "$TMP/thing.py"
  run bash -c "printf '%s' '{\"tool_name\":\"Edit\",\"cwd\":\"$TMP\",\"tool_input\":{\"file_path\":\"$TMP/thing.py\"}}' | HOME='$TMP' bash '$BIN/file-change-log.sh'"
  [ "$status" -eq 0 ]
  [ ! -e "$MB/codebase/.graph-dirty" ]
}

@test "file-change-log ignores non-source edits for the dirty-queue" {
  _graph "2026-01-01T00:00:00Z"
  printf 'x' > "$TMP/notes.md"
  run bash -c "printf '%s' '{\"tool_name\":\"Edit\",\"cwd\":\"$TMP\",\"tool_input\":{\"file_path\":\"$TMP/notes.md\"}}' | HOME='$TMP' bash '$BIN/file-change-log.sh'"
  [ "$status" -eq 0 ]
  [ ! -e "$MB/codebase/.graph-dirty" ]
}

@test "graph-nudge offers a refresh on a STALE graph instead of going silent" {
  _graph "2020-01-01T00:00:00Z"
  run bash -c "printf '%s' '{\"tool_name\":\"Grep\",\"cwd\":\"$TMP\",\"tool_input\":{\"pattern\":\"foo\"}}' | PATH=\"$REPO/.venv/bin:\$PATH\" bash '$BIN/mb-graph-nudge.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale"* ]]
  [[ "$output" == *"graph --apply"* ]]
}

@test "session-summarize wires a bounded graph catchup (marker consumed inline, not detached)" {
  run grep -F 'catchup' "$BIN/mb-session-summarize.sh"
  [ "$status" -eq 0 ]
}

@test "session-start cheat-sheet reports graph freshness when a graph exists" {
  _graph "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '## x\nbody\n' > "$MB/session/_recent.md"
  run bash -c "CLAUDE_PROJECT_DIR='$TMP' PATH=\"$REPO/.venv/bin:\$PATH\" bash '$BIN/mb-session-start.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Code graph"* ]]
}
