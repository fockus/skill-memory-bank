#!/usr/bin/env bats
# Stage 5 (session-memory-graph-hardening) + I-133 — 5g must route the
# post-`flip` graph refresh through the bounded single-consumer catchup CLI
# (mb-graph-query.py catchup): one lock, one budget, one cooldown — and must
# NOT instruct a detached background rebuild or the legacy ad-hoc lock.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  WORK_MD="$REPO_ROOT/commands/work.md"
}

_5g_region() {
  # From the "### 5g. Item done" heading up to (not including) the next
  # top-level "6." section heading.
  awk '/^   ### 5g\. Item done/{flag=1} flag{print} /^6\. \*\*End-of-run summary/{exit}' "$WORK_MD"
}

@test "5g routes the graph refresh through the bounded catchup CLI" {
  region="$(_5g_region)"
  [ -n "$region" ]

  echo "$region" | grep -q "mb-graph-query.py catchup"
  echo "$region" | grep -q "codebase/.graph.lock"
  echo "$region" | grep -q "MB_GRAPH_CATCHUP_BUDGET"
  echo "$region" | grep -Eiq "fail-open"
  echo "$region" | grep -q "graph.json"
}

@test "5g forbids the legacy detached rebuild pattern" {
  region="$(_5g_region)"
  [ -n "$region" ]

  if echo "$region" | grep -q "graph-rebuild.lock"; then false; fi
  if echo "$region" | grep -Eq 'mb-codegraph\.py[^)]*&'; then false; fi
}

@test "5g documents refresh is skipped when graph.json is absent" {
  region="$(_5g_region)"
  [ -n "$region" ]

  echo "$region" | grep -Eiq "existing-graph-only|first build stays manual|absent.*skip|skip.*absent"
}
