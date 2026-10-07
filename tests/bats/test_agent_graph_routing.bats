#!/usr/bin/env bats
# Stage 8 — every skill role agent must carry the graph-first routing block so
# structural questions hit the code graph before blind grep (when it is fresh).
# The block lives once in mb-tooling-core and reaches each role through its
# `compose:` frontmatter, so the checks run on the installed (rendered) form.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  AGENTS_DIR="$REPO_ROOT/agents"
}

_agents() {
  echo "mb-developer.md mb-backend.md mb-frontend.md mb-architect.md mb-qa.md mb-debugger.md plan-verifier.md"
}

_role_agents() {
  echo "mb-developer.md mb-backend.md mb-frontend.md mb-qa.md mb-architect.md mb-debugger.md plan-verifier.md"
}

_rendered() {  # installed form of an agent (partials from `compose:` placed above it)
  python3 "$REPO_ROOT/scripts/mb-agent-render.py" "$AGENTS_DIR/$1" --skill-dir "$REPO_ROOT"
}

@test "all skill role agents carry the graph-first routing table once installed" {
  for f in $(_agents); do
    run _rendered "$f"
    [ "$status" -eq 0 ] || { echo "render failed for $f"; return 1; }
    [[ "$output" == *"Code-understanding tools (graph-first, fail-open)"* ]] || { echo "missing routing in $f"; return 1; }
  done
}

@test "all skill role agents reference the impact command" {
  for f in $(_agents); do
    # graph-semantic-adoption Stage 4: the same short command the hooks print
    # ("$SKILL_DIR"/scripts/mb-graph.sh impact), not the long python form.
    run _rendered "$f"
    [[ "$output" =~ mb-graph\.sh\ impact ]] || { echo "missing impact command in $f"; return 1; }
  done
}

@test "tooling-core grants a bounded one-time catchup permission on stale (I-133 discipline)" {
  run grep -F "mb-graph-query.py catchup" "$AGENTS_DIR/mb-tooling-core.md"
  [ "$status" -eq 0 ] || { echo "missing catchup permission"; return 1; }

  run grep -iE "once|one-time" "$AGENTS_DIR/mb-tooling-core.md"
  [ "$status" -eq 0 ] || { echo "missing bounded (once/one-time) wording"; return 1; }

  run grep -F "codebase/.graph.lock" "$AGENTS_DIR/mb-tooling-core.md"
  [ "$status" -eq 0 ] || { echo "missing single-consumer lock reference"; return 1; }

  run grep -E "fall back|never block" "$AGENTS_DIR/mb-tooling-core.md"
  [ "$status" -eq 0 ] || { echo "fail-open wording missing"; return 1; }

  # The legacy direct-rebuild path must be forbidden, not granted.
  run grep -F ".graph-rebuild.lock" "$AGENTS_DIR/mb-tooling-core.md"
  [ "$status" -ne 0 ] || { echo "legacy rebuild lock still referenced"; return 1; }
}

@test "role files use mb-graph.sh status not /mb context for freshness" {
  for f in $(_role_agents); do
    run _rendered "$f"
    [[ "$output" =~ mb-graph\.sh\ status ]] || { echo "missing mb-graph.sh status in $f"; return 1; }
    [[ "$output" != *"/mb context"* ]] || { echo "stale /mb context freshness reference still present in $f"; return 1; }
  done
}

@test "engineering-core has a graph pointer" {
  run grep -iE "mb-graph-query.py|code graph|graph-first" "$AGENTS_DIR/mb-engineering-core.md"
  [ "$status" -eq 0 ] || { echo "missing graph pointer in mb-engineering-core.md"; return 1; }
}
