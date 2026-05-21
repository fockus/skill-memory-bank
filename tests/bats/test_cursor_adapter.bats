#!/usr/bin/env bats
# Tests for adapters/cursor.sh — Cursor IDE cross-agent adapter.
#
# Contract:
#   adapters/cursor.sh install [PROJECT_ROOT]
#   adapters/cursor.sh uninstall [PROJECT_ROOT]
#
# Generates:
#   <project>/.cursor/rules/memory-bank.mdc      — rules with YAML frontmatter
#   <project>/.cursor/hooks.json                 — Cursor hooks.json (CC-compat)
#   <project>/.cursor/hooks/*.sh                 — copied hook scripts
#   <project>/.cursor/.mb-manifest.json          — tracks installed files
#
# Uses CC-compatible hooks.json format (Cursor 1.7+ supports loading hooks from Claude Code).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ADAPTER="$REPO_ROOT/adapters/cursor.sh"
  PROJECT="$(mktemp -d)"
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
# Install
# ═══════════════════════════════════════════════════════════════

@test "cursor: install creates expected directory structure" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -d "$PROJECT/.cursor" ]
  [ -d "$PROJECT/.cursor/rules" ]
  [ -d "$PROJECT/.cursor/hooks" ]
}

@test "cursor: install creates rules/memory-bank.mdc with valid frontmatter" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local mdc="$PROJECT/.cursor/rules/memory-bank.mdc"
  [ -f "$mdc" ]
  # Frontmatter: starts and ends with ---
  head -n1 "$mdc" | grep -q '^---$'
  grep -q '^description:' "$mdc"
  grep -q '^alwaysApply:' "$mdc"
}

@test "cursor: install creates valid hooks.json with CC-compat events" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hjson="$PROJECT/.cursor/hooks.json"
  [ -f "$hjson" ]
  # Valid JSON
  jq . "$hjson" >/dev/null
  # Contains our required events
  jq -e '.hooks.sessionEnd' "$hjson" >/dev/null
  jq -e '.hooks.preCompact' "$hjson" >/dev/null
  jq -e '.hooks.beforeShellExecution' "$hjson" >/dev/null
}

@test "cursor: install copies executable hook scripts" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -x "$PROJECT/.cursor/hooks/session-end-autosave.sh" ]
  [ -x "$PROJECT/.cursor/hooks/mb-compact-reminder.sh" ]
  [ -x "$PROJECT/.cursor/hooks/block-dangerous.sh" ]
}

@test "cursor: install writes manifest tracking all created files" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local m="$PROJECT/.cursor/.mb-manifest.json"
  [ -f "$m" ]
  jq . "$m" >/dev/null
  jq -e '.schema_version == 1' "$m" >/dev/null
  # Manifest must list the rules file and hooks.json ownership
  jq -e '.files | length > 0' "$m" >/dev/null
  jq -e '.hooks_events | length > 0' "$m" >/dev/null
}

@test "cursor: install is idempotent — 2x run creates no duplicates" {
  run_adapter install "$PROJECT"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hjson="$PROJECT/.cursor/hooks.json"
  # Each event has exactly 1 command (no duplicate entries)
  local count
  count=$(jq '.hooks.sessionEnd | length' "$hjson")
  [ "$count" -eq 1 ]
  count=$(jq '.hooks.preCompact | length' "$hjson")
  [ "$count" -eq 1 ]
}

@test "cursor: install merges with existing user hooks.json" {
  mkdir -p "$PROJECT/.cursor"
  cat > "$PROJECT/.cursor/hooks.json" <<'EOF'
{
  "version": 1,
  "hooks": {
    "sessionEnd": [
      { "command": "echo user-custom-hook" }
    ],
    "afterFileEdit": [
      { "command": "prettier --write" }
    ]
  }
}
EOF
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hjson="$PROJECT/.cursor/hooks.json"
  # User's hooks preserved
  jq -e '.hooks.afterFileEdit[0].command == "prettier --write"' "$hjson" >/dev/null
  jq -e '.hooks.sessionEnd | map(.command) | any(. == "echo user-custom-hook")' "$hjson" >/dev/null
  # Our hooks added
  jq -e '.hooks.sessionEnd | length >= 2' "$hjson" >/dev/null
  jq -e '.hooks.preCompact | length == 1' "$hjson" >/dev/null
}

# ═══════════════════════════════════════════════════════════════
# Uninstall
# ═══════════════════════════════════════════════════════════════

@test "cursor: uninstall removes all our files" {
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.cursor/rules/memory-bank.mdc" ]
  [ ! -f "$PROJECT/.cursor/hooks/session-end-autosave.sh" ]
  [ ! -f "$PROJECT/.cursor/.mb-manifest.json" ]
}

@test "cursor: uninstall preserves user hooks in hooks.json" {
  mkdir -p "$PROJECT/.cursor"
  cat > "$PROJECT/.cursor/hooks.json" <<'EOF'
{
  "version": 1,
  "hooks": {
    "afterFileEdit": [
      { "command": "prettier --write" }
    ]
  }
}
EOF
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  local hjson="$PROJECT/.cursor/hooks.json"
  # hooks.json still exists (user had it)
  [ -f "$hjson" ]
  # User hook preserved
  jq -e '.hooks.afterFileEdit[0].command == "prettier --write"' "$hjson" >/dev/null
  # Our events removed
  local se_count
  se_count=$(jq '.hooks.sessionEnd // [] | length' "$hjson")
  [ "$se_count" -eq 0 ]
}

@test "cursor: uninstall without prior install exits 0 as no-op" {
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
}

@test "cursor: install fails gracefully if project root doesn't exist" {
  run_adapter install "/nonexistent/path/xyz"
  [ "$status" -ne 0 ]
}

@test "cursor: install removes hooks.json if no user hooks remain after uninstall" {
  # hooks.json was created by us (no prior user content)
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  # Since we were sole owner and had no user hooks, hooks.json should be gone
  [ ! -f "$PROJECT/.cursor/hooks.json" ]
}

@test "cursor: install registers sessionStart and tool hooks with matchers" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hjson="$PROJECT/.cursor/hooks.json"
  jq -e '.hooks.sessionStart | length == 1' "$hjson" >/dev/null
  jq -e '.hooks.preToolUse | length == 4' "$hjson" >/dev/null
  jq -e '.hooks.postToolUse | length == 2' "$hjson" >/dev/null
  jq -e '.hooks.preToolUse[] | select(.matcher == "Write|Edit")' "$hjson" >/dev/null
  jq -e '.hooks.preToolUse[] | select(.matcher == "Task")' "$hjson" >/dev/null
}

@test "cursor: install copies all ten hook scripts" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hooks=(
    session-end-autosave.sh
    mb-compact-reminder.sh
    block-dangerous.sh
    mb-protected-paths-guard.sh
    mb-ears-pre-write.sh
    mb-context-slim-pre-agent.sh
    mb-sprint-context-guard.sh
    file-change-log.sh
    mb-plan-sync-post-write.sh
    mb-session-start-context.sh
  )
  local h
  for h in "${hooks[@]}"; do
    [ -x "$PROJECT/.cursor/hooks/$h" ]
  done
}

@test "cursor: install has exactly ten _mb_owned entries" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local count
  count=$(jq '[.hooks[][] | select(._mb_owned == true)] | length' "$PROJECT/.cursor/hooks.json")
  [ "$count" -eq 10 ]
}

@test "cursor: idempotent install keeps ten _mb_owned entries" {
  run_adapter install "$PROJECT"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local count
  count=$(jq '[.hooks[][] | select(._mb_owned == true)] | length' "$PROJECT/.cursor/hooks.json")
  [ "$count" -eq 10 ]
  count=$(jq '.hooks.preToolUse | length' "$PROJECT/.cursor/hooks.json")
  [ "$count" -eq 4 ]
}

# ═══════════════════════════════════════════════════════════════
# Global storage support (Stage 3 — MB_PATH resolver-aware)
# ═══════════════════════════════════════════════════════════════

@test "cursor: adapter copies hooks that will support global storage via MB_PATH" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  # Cursor copies hooks from hooks/ directory rather than generating inline bodies.
  # Resolver-aware updates to hooks/ (Stage 2) automatically propagate to Cursor
  # projects on the next adapter install. Verify the hook directory is populated
  # and the hooks.json wires them up correctly (structural contract).
  local hooks_dir="$PROJECT/.cursor/hooks"
  [ -d "$hooks_dir" ]
  local n
  n=$(find "$hooks_dir" -name '*.sh' | wc -l | tr -d ' ')
  [ "$n" -ge 5 ]
  # hooks.json must reference the hooks directory
  grep -q "\.cursor/hooks" "$PROJECT/.cursor/hooks.json"
}

@test "cursor: rules file mentions resolver or global storage for bank path" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local mdc="$PROJECT/.cursor/rules/memory-bank.mdc"
  [ -f "$mdc" ]
  # Rules file must mention that path is resolved (not only local)
  grep -qi "MB_PATH\|global storage\|resolver\|resolved" "$mdc"
}
