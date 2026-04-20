#!/usr/bin/env bats
# End-to-end tests for install.sh --clients flag (cross-agent integration).
#
# Verifies:
#   - install.sh without --clients → default claude-code only (backward compat)
#   - install.sh --clients <list> → invokes adapters for each in addition to global
#   - --clients validation rejects unknown client names
#   - --project-root targets adapter file placement
#   - --help works and exits 0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX_HOME="$(mktemp -d)"
  PROJECT="$(mktemp -d)"
  (cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t)
  export HOME="$SANDBOX_HOME"
  export MB_SKIP_DEPS_CHECK=1
  command -v python3 >/dev/null || skip "python3 required"
  command -v jq >/dev/null || skip "jq required"
}

teardown() {
  [ -n "${SANDBOX_HOME:-}" ] && [ -d "$SANDBOX_HOME" ] && rm -rf "$SANDBOX_HOME"
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

@test "install.sh --help prints usage and exits 0" {
  run bash "$REPO_ROOT/install.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--clients"* ]]
}

@test "install.sh without --clients → global install only (backward compat)" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  [ -f "$HOME/.claude/RULES.md" ]
  [ ! -d "$PROJECT/.cursor" ]
  [ ! -d "$PROJECT/.windsurf" ]
}

@test "install.sh --clients cursor installs Cursor adapter into project" {
  bash "$REPO_ROOT/install.sh" --clients cursor --project-root "$PROJECT" >/dev/null
  [ -f "$HOME/.claude/RULES.md" ]
  [ -f "$PROJECT/.cursor/rules/memory-bank.mdc" ]
  [ -f "$PROJECT/.cursor/hooks.json" ]
  [ -f "$PROJECT/.cursor/.mb-manifest.json" ]
}

@test "install.sh --clients claude-code,cursor,kilo installs both adapters" {
  bash "$REPO_ROOT/install.sh" --clients claude-code,cursor,kilo --project-root "$PROJECT" >/dev/null
  [ -f "$HOME/.claude/RULES.md" ]
  [ -f "$PROJECT/.cursor/rules/memory-bank.mdc" ]
  [ -f "$PROJECT/.kilocode/rules/memory-bank.md" ]
  [ -x "$PROJECT/.git/hooks/post-commit" ]
}

@test "install.sh --clients opencode,codex coexist via shared AGENTS.md refcount" {
  bash "$REPO_ROOT/install.sh" --clients opencode,codex --project-root "$PROJECT" >/dev/null
  [ -f "$PROJECT/AGENTS.md" ]
  [ -f "$PROJECT/.opencode/commands/mb.md" ]
  local count
  count=$(grep -c "memory-bank:start" "$PROJECT/AGENTS.md")
  [ "$count" -eq 1 ]
  jq -e '.owners | contains(["opencode","codex"])' "$PROJECT/.mb-agents-owners.json" >/dev/null
}

@test "install.sh --clients invalidname → exit non-zero with validation error" {
  run bash "$REPO_ROOT/install.sh" --clients invalidname --project-root "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid client"* ]]
}

@test "install.sh --clients '' → exit non-zero (empty)" {
  run bash "$REPO_ROOT/install.sh" --clients "" --project-root "$PROJECT"
  [ "$status" -ne 0 ]
}

@test "install.sh --unknown-flag → exit non-zero with hint" {
  run bash "$REPO_ROOT/install.sh" --nonsense
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown argument"* ]] || [[ "$output" == *"--help"* ]]
}

@test "install.sh --clients windsurf creates Cascade hooks.json in project" {
  bash "$REPO_ROOT/install.sh" --clients windsurf --project-root "$PROJECT" >/dev/null
  [ -f "$PROJECT/.windsurf/rules/memory-bank.md" ]
  [ -f "$PROJECT/.windsurf/hooks.json" ]
  jq . "$PROJECT/.windsurf/hooks.json" >/dev/null
}

@test "install.sh --clients cline creates .clinerules with hooks" {
  bash "$REPO_ROOT/install.sh" --clients cline --project-root "$PROJECT" >/dev/null
  [ -f "$PROJECT/.clinerules/memory-bank.md" ]
  [ -x "$PROJECT/.clinerules/hooks/before-tool.sh" ]
}
