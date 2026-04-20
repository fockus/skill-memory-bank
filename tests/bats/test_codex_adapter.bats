#!/usr/bin/env bats
# Tests for adapters/codex.sh — OpenAI Codex CLI adapter.
#
# Contract:
#   adapters/codex.sh install [PROJECT_ROOT]
#   adapters/codex.sh uninstall [PROJECT_ROOT]
#
# Generates:
#   <project>/AGENTS.md            — shared format (refcount via lib)
#   <project>/.codex/config.toml   — project-level settings
#   <project>/.codex/hooks.json    — experimental hooks (off by default)
#   <project>/.codex/.mb-manifest.json
#
# Codex hooks API: experimental, userpromptsubmit currently stable, lifecycle under dev.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ADAPTER="$REPO_ROOT/adapters/codex.sh"
  OC_ADAPTER="$REPO_ROOT/adapters/opencode.sh"
  PROJECT="$(mktemp -d)"
  mkdir -p "$PROJECT/.memory-bank"
  echo '# Progress' > "$PROJECT/.memory-bank/progress.md"
  command -v jq >/dev/null || skip "jq required"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

run_adapter() {
  local raw
  raw=$(bash "$ADAPTER" "$@" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

# ═══════════════════════════════════════════════════════════════

@test "codex: install creates AGENTS.md with memory-bank section" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q "memory-bank:start" "$PROJECT/AGENTS.md"
}

@test "codex: install creates .codex/config.toml with project settings" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.codex/config.toml" ]
  grep -q "project_doc_max_bytes" "$PROJECT/.codex/config.toml"
}

@test "codex: install creates .codex/hooks.json with userpromptsubmit event" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.codex/hooks.json" ]
  jq . "$PROJECT/.codex/hooks.json" >/dev/null
  jq -e '.hooks.userpromptsubmit // .hooks."user-prompt-submit"' "$PROJECT/.codex/hooks.json" >/dev/null
}

@test "codex: install writes manifest with adapter=codex" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local m="$PROJECT/.codex/.mb-manifest.json"
  [ -f "$m" ]
  jq -e '.adapter == "codex"' "$m" >/dev/null
}

@test "codex: install idempotent — 2x run no section duplicates" {
  run_adapter install "$PROJECT"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local count
  count=$(grep -c "memory-bank:start" "$PROJECT/AGENTS.md")
  [ "$count" -eq 1 ]
}

@test "codex: uninstall removes our files and section" {
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.codex/config.toml" ]
  [ ! -f "$PROJECT/.codex/hooks.json" ]
  [ ! -f "$PROJECT/.codex/.mb-manifest.json" ]
  [ ! -f "$PROJECT/AGENTS.md" ]
}

@test "codex: uninstall no-op if never installed" {
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Coexistence with OpenCode (shared AGENTS.md refcount)
# ═══════════════════════════════════════════════════════════════

@test "codex+opencode: both install → single AGENTS.md section, refcount=2" {
  bash "$OC_ADAPTER" install "$PROJECT" >/dev/null
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  # Exactly one section
  local count
  count=$(grep -c "memory-bank:start" "$PROJECT/AGENTS.md")
  [ "$count" -eq 1 ]
  # Owners file has both
  jq -e '.owners | contains(["opencode","codex"])' "$PROJECT/.mb-agents-owners.json" >/dev/null
}

@test "codex+opencode: uninstall codex preserves section because opencode still owns" {
  bash "$OC_ADAPTER" install "$PROJECT" >/dev/null
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  # Section still present (opencode active)
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q "memory-bank:start" "$PROJECT/AGENTS.md"
  # Owners reduced to opencode only
  jq -e '.owners == ["opencode"]' "$PROJECT/.mb-agents-owners.json" >/dev/null
}

@test "codex+opencode: uninstall BOTH removes AGENTS.md entirely (no owners left)" {
  bash "$OC_ADAPTER" install "$PROJECT" >/dev/null
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  bash "$OC_ADAPTER" uninstall "$PROJECT" >/dev/null
  [ ! -f "$PROJECT/AGENTS.md" ]
  [ ! -f "$PROJECT/.mb-agents-owners.json" ]
}

@test "codex+opencode: existing user AGENTS.md preserved after both uninstall" {
  echo "# User preamble" > "$PROJECT/AGENTS.md"
  bash "$OC_ADAPTER" install "$PROJECT" >/dev/null
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  bash "$OC_ADAPTER" uninstall "$PROJECT" >/dev/null
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q "User preamble" "$PROJECT/AGENTS.md"
  ! grep -q "memory-bank:start" "$PROJECT/AGENTS.md"
}
