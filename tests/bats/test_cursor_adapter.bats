#!/usr/bin/env bats
# Tests for adapters/cursor.sh — Cursor IDE cross-agent adapter.

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

@test "cursor: install creates expected directory structure" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -d "$PROJECT/.cursor" ]
  [ -d "$PROJECT/.cursor/rules" ]
  [ ! -d "$PROJECT/.cursor/hooks" ]
}

@test "cursor: install wires hooks.json to skill bundle paths" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hjson="$PROJECT/.cursor/hooks.json"
  grep -q 'memory-bank/hooks/session-end-autosave.sh' "$hjson"
  grep -q 'MB_AGENT=cursor' "$hjson"
  [ ! -f "$PROJECT/.cursor/hooks/session-end-autosave.sh" ]
}

@test "cursor: install removes legacy hook copies on reinstall" {
  run_adapter install "$PROJECT"
  mkdir -p "$PROJECT/.cursor/hooks"
  echo legacy > "$PROJECT/.cursor/hooks/mb-plan-sync-post-write.sh"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.cursor/hooks/mb-plan-sync-post-write.sh" ]
}

@test "cursor: install creates valid hooks.json with CC-compat events" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hjson="$PROJECT/.cursor/hooks.json"
  jq . "$hjson" >/dev/null
  jq -e '.hooks.sessionEnd' "$hjson" >/dev/null
  jq -e '.hooks.preCompact' "$hjson" >/dev/null
  jq -e '.hooks.beforeShellExecution' "$hjson" >/dev/null
}

@test "cursor: install references all ten hook scripts in hooks.json" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hjson="$PROJECT/.cursor/hooks.json"
  local hooks=(session-end-autosave.sh mb-pre-compact.sh block-dangerous.sh mb-protected-paths-guard.sh mb-ears-pre-write.sh mb-context-slim-pre-agent.sh mb-sprint-context-guard.sh file-change-log.sh mb-plan-sync-post-write.sh mb-session-start-context.sh)
  local h
  for h in "${hooks[@]}"; do
    grep -q "memory-bank/hooks/$h" "$hjson"
  done
}

@test "cursor: install has exactly ten _mb_owned entries" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local count
  count=$(jq '[.hooks[][] | select(._mb_owned == true)] | length' "$PROJECT/.cursor/hooks.json")
  [ "$count" -eq 10 ]
}

@test "cursor: uninstall removes all our files" {
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.cursor/rules/memory-bank.mdc" ]
  [ ! -f "$PROJECT/.cursor/.mb-manifest.json" ]
}

@test "cursor: adapter hooks.json supports global storage via MB_AGENT" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  grep -q 'MB_AGENT=cursor' "$PROJECT/.cursor/hooks.json"
  grep -q 'MB_SKILLS_ROOT=' "$PROJECT/.cursor/hooks.json"
}

@test "cursor: reinstall removes legacy mb-compact-reminder.sh copy left by old install" {
  # Simulate an old install that left a physical copy of the renamed hook.
  run_adapter install "$PROJECT"
  mkdir -p "$PROJECT/.cursor/hooks"
  echo '#!/usr/bin/env bash' > "$PROJECT/.cursor/hooks/mb-compact-reminder.sh"
  chmod +x "$PROJECT/.cursor/hooks/mb-compact-reminder.sh"
  # Reinstall must clean up the stale legacy copy.
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.cursor/hooks/mb-compact-reminder.sh" ]
}
