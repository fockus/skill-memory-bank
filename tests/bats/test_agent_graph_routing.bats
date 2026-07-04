#!/usr/bin/env bats
# Stage 8 — every skill role agent must carry the graph-first routing block so
# structural questions hit the code graph before blind grep (when it is fresh).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  AGENTS_DIR="$REPO_ROOT/agents"
}

_agents() {
  echo "mb-developer.md mb-backend.md mb-frontend.md mb-architect.md mb-qa.md plan-verifier.md"
}

@test "all skill role agents carry the graph-first routing sentinel" {
  for f in $(_agents); do
    run grep -F "Code-graph routing (when the graph is fresh)" "$AGENTS_DIR/$f"
    [ "$status" -eq 0 ] || { echo "missing sentinel in $f"; return 1; }
  done
}

@test "all skill role agents reference the impact command" {
  for f in $(_agents); do
    run grep -F "mb-graph-query.py impact" "$AGENTS_DIR/$f"
    [ "$status" -eq 0 ] || { echo "missing impact command in $f"; return 1; }
  done
}
