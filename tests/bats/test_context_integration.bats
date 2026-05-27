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
