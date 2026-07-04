#!/usr/bin/env bats
# Tests for mb-context.sh integration with .memory-bank/codebase/.
#
# Contract:
#   When .memory-bank/codebase/ exists and contains MDs, mb-context.sh
#   adds a "Codebase summary" section with 1-line-per-MD output.
#   With --deep flag, includes full content of each codebase MD.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-context.sh"
  TMPBANK="$(mktemp -d)/.memory-bank"
  mkdir -p "$TMPBANK"/{codebase,plans,notes}

  # Minimal core files
  echo "# Status test" > "$TMPBANK/status.md"
  echo "# Roadmap test" > "$TMPBANK/roadmap.md"
  echo "# Checklist test" > "$TMPBANK/checklist.md"
  echo "# Research test" > "$TMPBANK/research.md"
}

teardown() {
  [ -n "${TMPBANK:-}" ] && [ -d "$(dirname "$TMPBANK")" ] && rm -rf "$(dirname "$TMPBANK")"
}

# ═══ Codebase summary integration ═══

@test "context: includes codebase summary when codebase/ has MDs" {
  cat > "$TMPBANK/codebase/STACK.md" <<'EOF'
# Technology Stack

Primary: Go 1.22. Uses Cobra for CLI, Viper for config.
EOF

  cat > "$TMPBANK/codebase/ARCHITECTURE.md" <<'EOF'
# Architecture

Clean architecture: cmd/ → internal/app/ → internal/domain/.
EOF

  run bash "$SCRIPT" "$TMPBANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Codebase summary"* ]]
  [[ "$output" == *"STACK.md"* ]]
  [[ "$output" == *"ARCHITECTURE.md"* ]]
}

@test "context: codebase summary shows first non-heading content line" {
  cat > "$TMPBANK/codebase/STACK.md" <<'EOF'
# Technology Stack

Primary language: Python 3.12 with FastAPI framework.
EOF

  run bash "$SCRIPT" "$TMPBANK"
  [ "$status" -eq 0 ]
  # It should extract the Python summary line, not the heading
  [[ "$output" == *"Python 3.12"* ]]
}

@test "context: no codebase section when codebase/ is empty" {
  run bash "$SCRIPT" "$TMPBANK"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Codebase summary"* ]]
}

@test "context: no codebase section when codebase/ doesn't exist" {
  rm -rf "$TMPBANK/codebase"
  run bash "$SCRIPT" "$TMPBANK"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Codebase summary"* ]]
}

# ═══ --deep mode ═══

@test "context --deep: includes full codebase MD contents" {
  cat > "$TMPBANK/codebase/STACK.md" <<'EOF'
# Technology Stack

Primary: Go 1.22.

## Runtime
- Go 1.22
- net/http standard library

## Frameworks
- Cobra CLI
EOF

  run bash "$SCRIPT" --deep "$TMPBANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Runtime"* ]]
  [[ "$output" == *"Cobra CLI"* ]]
  [[ "$output" == *"net/http"* ]]
}

@test "context --deep without codebase/: graceful (no crash)" {
  rm -rf "$TMPBANK/codebase"
  run bash "$SCRIPT" --deep "$TMPBANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status.md"* ]]
}

@test "context: --deep flag accepted before path" {
  cat > "$TMPBANK/codebase/STACK.md" <<'EOF'
# Technology Stack

Node 20 with TypeScript.
EOF

  run bash "$SCRIPT" --deep "$TMPBANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TypeScript"* ]]
}

# ═══ Code graph section (Stage 7) ═══

_write_graph() {
  # $1 = generated_at ISO timestamp
  cat > "$TMPBANK/codebase/graph.json" <<EOF
{"type": "meta", "generated_at": "$1", "commit": null, "nodes": 2, "edges": 1}
{"type": "node", "kind": "function", "name": "foo", "file": "a.py", "line": 1}
{"type": "node", "kind": "module", "name": "a.py", "file": "a.py", "line": 1}
{"type": "edge", "kind": "call", "src": "a.py:bar", "dst": "foo"}
EOF
  echo "# God nodes" > "$TMPBANK/codebase/god-nodes.md"
}

@test "context: shows fresh graph line with counts and god-nodes pointer" {
  _write_graph "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  run bash "$SCRIPT" "$TMPBANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Code graph"* ]]
  [[ "$output" == *"nodes="* ]]
  [[ "$output" == *"edges="* ]]
  [[ "$output" == *"god-nodes.md"* ]]
  # Never injects graph.json contents
  [[ "$output" != *'"type": "node"'* ]]
}

@test "context: shows stale graph hint with rebuild command" {
  _write_graph "2020-01-01T00:00:00Z"
  run bash "$SCRIPT" "$TMPBANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale"* ]]
  [[ "$output" == *"mb-codegraph.py --apply"* ]]
}

@test "context: absent graph shows build hint, never errors" {
  rm -f "$TMPBANK/codebase/graph.json"
  run bash "$SCRIPT" "$TMPBANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Code graph"* ]]
  [[ "$output" == *"not built"* ]]
  [[ "$output" == *"mb-codegraph.py --apply"* ]]
}
