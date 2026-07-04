#!/usr/bin/env bats
# Tests for hooks/mb-session-start.sh — inject _recent.md as # Recent Sessions
# plus the how-to cheat-sheet (graph + recall quick ref). macOS-safe (no hang).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/mb-session-start.sh"
  command -v jq >/dev/null || skip "jq required"
  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"; MB="$PROJ/.memory-bank"
  mkdir -p "$MB/session"
}
teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

@test "emits valid # Recent Sessions JSON" {
  printf '## 2026-06-06 18:35 (dev) — abc12345\nsummary text here\n' > "$MB/session/_recent.md"
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' bash '$HOOK'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName=="SessionStart"' >/dev/null
  echo "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '# Recent Sessions'
  echo "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'summary text here'
}

@test "includes how-to cheat-sheet by default (graph + recall quick ref)" {
  printf '## x\nbody\n' > "$MB/session/_recent.md"
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' bash '$HOOK'"
  [ "$status" -eq 0 ]
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  echo "$ctx" | grep -q '# How to use project memory'
  echo "$ctx" | grep -q '/mb recall'
  echo "$ctx" | grep -q 'graphify'
  echo "$ctx" | grep -q '# Recent Sessions'
}

@test "MB_SESSION_CHEATSHEET=off suppresses cheat-sheet, keeps Recent Sessions" {
  printf '## x\nbody\n' > "$MB/session/_recent.md"
  run bash -c "MB_SESSION_CHEATSHEET=off CLAUDE_PROJECT_DIR='$PROJ' bash '$HOOK'"
  [ "$status" -eq 0 ]
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  echo "$ctx" | grep -q '# Recent Sessions'
  echo "$ctx" | grep -q 'body'
  if echo "$ctx" | grep -q '# How to use project memory'; then false; fi
}

@test "no _recent.md → {}" {
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "unresolved MB → {}" {
  mkdir -p "$TMP/nobank"
  run bash -c "CLAUDE_PROJECT_DIR='$TMP/nobank' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "does not hang with no stdin (drains via exec)" {
  printf '## x\nbody\n' > "$MB/session/_recent.md"
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' bash '$HOOK'"
  [ "$status" -ne 124 ]
}

# ═══ Stage 5 — opt-in background code-graph rebuild (MB_GRAPH_AUTO) ═══

_graph() {  # $1 = generated_at ISO
  mkdir -p "$MB/codebase"
  cat > "$MB/codebase/graph.json" <<EOF
{"type":"meta","generated_at":"$1","commit":null,"nodes":2,"edges":1}
{"type":"node","name":"x","file":"x.py"}
{"type":"node","name":"y","file":"y.py"}
{"type":"edge","src":"x.py","dst":"y","kind":"import"}
EOF
}

@test "graph-auto off by default: stale graph triggers no rebuild" {
  printf '## x\nbody\n' > "$MB/session/_recent.md"
  _graph "2020-01-01T00:00:00Z"
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' bash '$HOOK'"
  [ "$status" -eq 0 ]
  if echo "$output" | grep -q 'mb-codegraph.py --apply'; then false; fi
}

@test "graph-auto on + stale graph: rebuild command constructed (dryrun)" {
  printf '## x\nbody\n' > "$MB/session/_recent.md"
  _graph "2020-01-01T00:00:00Z"
  run bash -c "MB_GRAPH_AUTO=on MB_GRAPH_AUTO_DRYRUN=1 CLAUDE_PROJECT_DIR='$PROJ' bash '$HOOK'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'mb-codegraph.py --apply'
}

@test "graph-auto on + absent graph: no rebuild (first build stays manual)" {
  printf '## x\nbody\n' > "$MB/session/_recent.md"
  run bash -c "MB_GRAPH_AUTO=on MB_GRAPH_AUTO_DRYRUN=1 CLAUDE_PROJECT_DIR='$PROJ' bash '$HOOK'"
  [ "$status" -eq 0 ]
  if echo "$output" | grep -q 'mb-codegraph.py --apply'; then false; fi
}

@test "graph-auto on + fresh graph: no rebuild" {
  printf '## x\nbody\n' > "$MB/session/_recent.md"
  _graph "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  run bash -c "MB_GRAPH_AUTO=on MB_GRAPH_AUTO_DRYRUN=1 CLAUDE_PROJECT_DIR='$PROJ' bash '$HOOK'"
  [ "$status" -eq 0 ]
  if echo "$output" | grep -q 'mb-codegraph.py --apply'; then false; fi
}

@test "graph-auto fail-safe: exit 0 when python3 missing" {
  printf '## x\nbody\n' > "$MB/session/_recent.md"
  _graph "2020-01-01T00:00:00Z"
  FAKEBIN="$TMP/bin"; mkdir -p "$FAKEBIN"
  for t in bash cat wc head grep sed awk date stat dirname jq mkdir printf env; do
    p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$FAKEBIN/$t"
  done
  run bash -c "PATH='$FAKEBIN' MB_GRAPH_AUTO=on CLAUDE_PROJECT_DIR='$PROJ' '$FAKEBIN/bash' '$HOOK'"
  [ "$status" -eq 0 ]
}
