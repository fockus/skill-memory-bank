#!/usr/bin/env bats
# GraphRAG-lite adapter contracts for Pi/OpenCode/Codex/generic AGENTS.md surfaces.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PI_ADAPTER="$REPO_ROOT/adapters/pi.sh"
  OPENCODE_ADAPTER="$REPO_ROOT/adapters/opencode.sh"
  CODEX_ADAPTER="$REPO_ROOT/adapters/codex.sh"
  PROJECT="$(mktemp -d)"
  (cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t)
  mkdir -p "$PROJECT/.memory-bank/codebase"
  echo '# Progress' > "$PROJECT/.memory-bank/progress.md"
  command -v jq >/dev/null || skip "jq required"
  SANDBOX_HOME="$(mktemp -d)"
  export HOME="$SANDBOX_HOME"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
  [ -n "${SANDBOX_HOME:-}" ] && [ -d "$SANDBOX_HOME" ] && rm -rf "$SANDBOX_HOME"
}

run_script() {
  local raw
  raw=$(bash "$@" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

@test "graph-rag adapters: pi installs native project extension wrapper tools" {
  run_script "$PI_ADAPTER" install "$PROJECT"
  [ "$status" -eq 0 ]

  local ext="$PROJECT/.pi/extensions/memory-bank-graph-rag.ts"
  [ -f "$ext" ]
  grep -q "pi.registerTool" "$ext"
  grep -q "name: \"code_context\"" "$ext"
  grep -q "registerGraphTool(\"graph_neighbors\"" "$ext"
  grep -q "registerGraphTool(\"graph_impact\"" "$ext"
  grep -q "registerGraphTool(\"graph_tests\"" "$ext"
  grep -q "scripts/mb-code-context.py" "$ext"
  grep -q "scripts/mb-graph-query.py" "$ext"
}

# ═══════════════════════════════════════════════════════════════
# F-2: Pi extension placeholders must be substituted with JSON-encoded paths
# (a bare `cp` leaves __MB_SKILL_DIR_JSON__ / __MB_PROJECT_ROOT_JSON__ → invalid .ts)
# ═══════════════════════════════════════════════════════════════

_ts_const() {
  # Extract the RHS (JSON literal) of `const <NAME> = <value>;`
  local file="$1" name="$2"
  grep -E "^const ${name} = " "$file" | sed -E "s/^const ${name} = (.*);[[:space:]]*\$/\1/"
}

@test "graph-rag adapters: pi extension has no unresolved __MB_ placeholders" {
  run_script "$PI_ADAPTER" install "$PROJECT"
  [ "$status" -eq 0 ]
  local ext="$PROJECT/.pi/extensions/memory-bank-graph-rag.ts"
  [ -f "$ext" ]
  ! grep -q '__MB_' "$ext"
}

@test "graph-rag adapters: pi extension paths are valid JSON string literals" {
  run_script "$PI_ADAPTER" install "$PROJECT"
  [ "$status" -eq 0 ]
  local ext="$PROJECT/.pi/extensions/memory-bank-graph-rag.ts"
  local skill_val proj_val resolved_proj
  skill_val="$(_ts_const "$ext" SKILL_DIR)"
  proj_val="$(_ts_const "$ext" PROJECT_ROOT)"
  printf '%s' "$skill_val" | jq -e 'type == "string"' >/dev/null
  printf '%s' "$proj_val" | jq -e 'type == "string"' >/dev/null
  resolved_proj="$(cd "$PROJECT" && pwd)"
  [ "$(printf '%s' "$proj_val" | jq -r .)" = "$resolved_proj" ]
}

@test "graph-rag adapters: pi extension survives project path with spaces" {
  local sp="$PROJECT/with space/proj"
  mkdir -p "$sp/.memory-bank"
  (cd "$sp" && git init -q && git config user.email t@t && git config user.name t)
  echo '# Progress' > "$sp/.memory-bank/progress.md"
  run_script "$PI_ADAPTER" install "$sp"
  [ "$status" -eq 0 ]
  local ext="$sp/.pi/extensions/memory-bank-graph-rag.ts"
  [ -f "$ext" ]
  ! grep -q '__MB_' "$ext"
  local proj_val
  proj_val="$(_ts_const "$ext" PROJECT_ROOT)"
  printf '%s' "$proj_val" | jq -e 'type == "string"' >/dev/null
  [ "$(printf '%s' "$proj_val" | jq -r .)" = "$(cd "$sp" && pwd)" ]
}

@test "graph-rag adapters: pi wrappers preserve JSON payloads on fail-open exits" {
  run_script "$PI_ADAPTER" install "$PROJECT"
  [ "$status" -eq 0 ]

  local ext="$PROJECT/.pi/extensions/memory-bank-graph-rag.ts"
  grep -q "catch (caught" "$ext"
  grep -q '"stdout" in caught' "$ext"
  grep -q "JSON.parse(stdout)" "$ext"
  grep -q "tool_execution_failed" "$ext"
}

@test "graph-rag adapters: pi graph tools honor custom mbPath" {
  run_script "$PI_ADAPTER" install "$PROJECT"
  [ "$status" -eq 0 ]

  local ext="$PROJECT/.pi/extensions/memory-bank-graph-rag.ts"
  grep -q "mbPath: Type.Optional" "$ext"
  grep -q "params.mbPath || path.join(projectRoot, \".memory-bank\")" "$ext"
  grep -q "graphPath(projectRoot, mbPath)" "$ext"
}

@test "graph-rag adapters: pi manifest tracks native extension and uninstall removes it" {
  run_script "$PI_ADAPTER" install "$PROJECT"
  [ "$status" -eq 0 ]

  local manifest="$PROJECT/.mb-pi-manifest.json"
  jq -e '.files | map(.) | any(contains("memory-bank-graph-rag.ts"))' "$manifest" >/dev/null

  run_script "$PI_ADAPTER" uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.pi/extensions/memory-bank-graph-rag.ts" ]
}

@test "graph-rag adapters: opencode plugin documents native limit and CLI fallback" {
  run_script "$OPENCODE_ADAPTER" install "$PROJECT"
  [ "$status" -eq 0 ]

  local plugin="$PROJECT/.opencode/plugins/memory-bank.js"
  [ -f "$plugin" ]
  grep -q "code_context" "$plugin"
  grep -q "graph_neighbors" "$plugin"
  grep -q "graph_impact" "$plugin"
  grep -q "graph_tests" "$plugin"
  grep -q "scripts/mb-code-context.py" "$plugin"
  grep -q "scripts/mb-graph-query.py" "$plugin"
  grep -q "CLI fallback" "$plugin"
}

@test "graph-rag adapters: AGENTS.md guidance exposes cross-agent routing and CLI commands" {
  run_script "$CODEX_ADAPTER" install "$PROJECT"
  [ "$status" -eq 0 ]

  local agents="$PROJECT/AGENTS.md"
  [ -f "$agents" ]
  grep -q "GraphRAG-lite routing" "$agents"
  grep -q "code_context" "$agents"
  grep -q "graph_neighbors" "$agents"
  grep -q "graph_impact" "$agents"
  grep -q "graph_tests" "$agents"
  grep -q "search_code" "$agents"
  grep -q "scripts/mb-code-context.py" "$agents"
  grep -q "scripts/mb-graph-query.py" "$agents"
}
