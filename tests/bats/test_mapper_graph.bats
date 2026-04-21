#!/usr/bin/env bats
# Contract tests for graph.json / god-nodes.md consumption in
# agents/mb-codebase-mapper.md.
#
# Stage 4 of plans/2026-04-21_refactor_agents-quality.md requires the prompt
# to:
#   1. Prefer reading .memory-bank/codebase/graph.json BEFORE falling back to
#      grep/find when analyzing a codebase.
#   2. Honor a 24h staleness threshold (tunable via MB_GRAPH_STALE_HOURS env).
#   3. Explicitly state a "graph: not-used" fallback header when the graph is
#      missing, stale, or empty — so readers can tell which code path ran.
#   4. For CONCERNS.md, cite god-nodes (top-degree functions) from
#      .memory-bank/codebase/god-nodes.md when present.
#   5. For CONVENTIONS.md, derive naming patterns from graph.json node names
#      (snake_case vs camelCase counts) rather than brittle grep-on-source.
#   6. Stamp "Generated: <UTC timestamp>" via `date -u` — no hand-typed dates.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PROMPT="$REPO_ROOT/agents/mb-codebase-mapper.md"
  [ -f "$PROMPT" ]
}

@test "mapper/graph: prompt references graph.json consumption" {
  grep -Fq 'graph.json' "$PROMPT"
  # Must appear BEFORE grep fallback instructions — a pure mention would be
  # insufficient. Check that the first graph.json mention precedes the first
  # 'grep -rE' or 'grep/find' reference.
  local first_graph first_grep
  first_graph=$(grep -nF 'graph.json' "$PROMPT" | head -n1 | cut -d: -f1)
  first_grep=$(grep -nE 'grep -rE|grep/find|grep-based' "$PROMPT" | head -n1 | cut -d: -f1)
  [ -n "$first_graph" ]
  # If grep is mentioned at all, it must be after the graph-first precondition.
  [ -z "$first_grep" ] || [ "$first_graph" -lt "$first_grep" ]
}

@test "mapper/graph: prompt references god-nodes.md for CONCERNS derivation" {
  grep -Fq 'god-nodes.md' "$PROMPT"
}

@test "mapper/graph: prompt documents 24h staleness threshold" {
  grep -Eq '24[[:space:]]*h(our)?|24h' "$PROMPT"
}

@test "mapper/graph: prompt references MB_GRAPH_STALE_HOURS env override" {
  grep -Fq 'MB_GRAPH_STALE_HOURS' "$PROMPT"
}

@test "mapper/graph: prompt declares 'graph: not-used' fallback marker" {
  # The output document header must carry this marker so readers know the
  # mapper ran against grep-only data.
  grep -Eq 'graph:[[:space:]]*not-used|graph:[[:space:]]*used' "$PROMPT"
}

@test "mapper/graph: prompt derives naming-pattern stats from graph nodes (CONVENTIONS)" {
  # Must name at least one of the naming conventions we report on,
  # alongside a hint that the count comes from graph data.
  grep -Eq 'snake_case|camelCase|PascalCase' "$PROMPT"
  grep -Eq 'graph.*(name|node|count)|naming' "$PROMPT"
}

@test "mapper/graph: prompt instructs 'date -u' auto-timestamp (no hand-typed date)" {
  # Template should say to compute the timestamp, not ask the LLM to type it.
  grep -Eq 'date -u|\$\(date' "$PROMPT"
}

@test "mapper/graph: prompt documents graceful fallback when graph absent" {
  grep -Eiq 'missing|absent|stale|fallback|fall back' "$PROMPT"
}
