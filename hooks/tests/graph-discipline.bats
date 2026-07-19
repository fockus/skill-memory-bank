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

@test "no command/agent instruction layer detaches mb-codegraph or uses the legacy rebuild lock" {
  # codex I-133 r1 blocker: commands/work.md + agents/mb-tooling-core.md still
  # instructed agents to spawn detached rebuilds on the OLD .graph-rebuild.lock
  # — the instruction layer must follow the same discipline as the shell hooks.
  run grep -rF '.graph-rebuild.lock' "$REPO/commands" "$REPO/agents"
  [ "$status" -ne 0 ]
  run grep -rnE 'mb-codegraph\.py[^)]*&' "$REPO/commands" "$REPO/agents"
  [ "$status" -ne 0 ]
}

@test "no ACTIVE plan instructs the legacy detached rebuild pattern" {
  # codex I-133 r2 major: a queued plan with executable mb-stage blocks still
  # carried the pre-I-133 detached-rebuild snippet — an agent resuming it via
  # /mb work would reintroduce the anti-pattern. Scan every plan that is not
  # done/superseded/archived, same invariant as the commands/+agents/ scan.
  # codex r3: literal shell signatures are not enough — semantically-equivalent
  # PROSE ("run the rebuild in the background", "stdout contains
  # mb-codegraph.py --apply") instructs the same violation, so flag it too.
  local viol=0
  for f in "$REPO/.memory-bank/plans"/*.md; do
    [ -f "$f" ] || continue
    head -20 "$f" | grep -qE '^status: *(done|superseded|archived)' && continue
    if grep -qE 'mb-codegraph\.py[^)]*&|\.graph-rebuild\.lock' "$f" \
      || grep -qiE 'rebuild[^.]*\bbackground|background[^.]*\brebuild' "$f" \
      || grep -qiE 'stdout contains .{0,3}mb-codegraph' "$f"; then
      echo "violation in active plan: $f"
      viol=1
    fi
  done
  [ "$viol" -eq 0 ]
}

@test "graph-nudge offers a refresh on a STALE graph instead of going silent" {
  _graph "2020-01-01T00:00:00Z"
  run bash -c "printf '%s' '{\"tool_name\":\"Grep\",\"cwd\":\"$TMP\",\"tool_input\":{\"pattern\":\"foo\"}}' | PATH=\"$REPO/.venv/bin:\$PATH\" bash '$BIN/mb-graph-nudge.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale"* ]]
  [[ "$output" == *"graph --apply"* ]]
}

@test "graph-nudge is honest about age-only staleness (no auto-catchup promise)" {
  # codex I-133 r1 minor: age-only staleness (commit matches, no dirty marker)
  # never triggers maybe_catchup — the nudge must not promise an automatic fix.
  _graph "2020-01-01T00:00:00Z"
  run bash -c "printf '%s' '{\"tool_name\":\"Grep\",\"cwd\":\"$TMP\",\"tool_input\":{\"pattern\":\"foo\"}}' | PATH=\"$REPO/.venv/bin:\$PATH\" bash '$BIN/mb-graph-nudge.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"auto-catchup"* ]]
}

@test "graph-nudge promises auto-catchup when the dirty-queue is non-empty" {
  _graph "2020-01-01T00:00:00Z"
  : > "$MB/codebase/.graph-dirty"
  run bash -c "printf '%s' '{\"tool_name\":\"Grep\",\"cwd\":\"$TMP\",\"tool_input\":{\"pattern\":\"foo\"}}' | PATH=\"$REPO/.venv/bin:\$PATH\" bash '$BIN/mb-graph-nudge.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-catchup"* ]]
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
