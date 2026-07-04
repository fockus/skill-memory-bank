#!/usr/bin/env bats
# Stage 6 — opt-in git post-commit hook that refreshes the code graph.
# Fail-safe on every path (exit 0); no-op when the graph does not exist yet.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/git/post-commit-codegraph.sh"
  TMP="$(mktemp -d)"
  ( cd "$TMP" && git init -q && git commit -q --allow-empty -m init 2>/dev/null ) || true
  MB="$TMP/.memory-bank"
  mkdir -p "$MB/codebase"
}
teardown() { [ -n "${TMP:-}" ] && rm -rf "$TMP"; }

_graph() {
  cat > "$MB/codebase/graph.json" <<'EOF'
{"type":"meta","generated_at":"2026-07-04T00:00:00Z","commit":null,"nodes":1,"edges":0}
{"type":"node","name":"x","file":"x.py"}
EOF
}

@test "hook file has the executable bit set" {
  [ -x "$HOOK" ]
}

@test "post-commit absent graph is a no-op, exit 0" {
  run bash -c "cd '$TMP' && MB_GRAPH_AUTO_DRYRUN=1 bash '$HOOK'"
  [ "$status" -eq 0 ]
  if echo "$output" | grep -q 'mb-codegraph.py --apply'; then false; fi
}

@test "post-commit existing graph rebuilds (dryrun)" {
  _graph
  run bash -c "cd '$TMP' && MB_GRAPH_AUTO_DRYRUN=1 bash '$HOOK'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'mb-codegraph.py --apply'
}

@test "post-commit fail-safe when python3 missing" {
  _graph
  FAKEBIN="$TMP/bin"; mkdir -p "$FAKEBIN"
  for t in bash git mkdir dirname printf; do
    p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$FAKEBIN/$t"
  done
  run bash -c "cd '$TMP' && PATH='$FAKEBIN' MB_GRAPH_AUTO_DRYRUN=1 '$FAKEBIN/bash' '$HOOK'"
  [ "$status" -eq 0 ]
  if echo "$output" | grep -q 'mb-codegraph.py --apply'; then false; fi
}
