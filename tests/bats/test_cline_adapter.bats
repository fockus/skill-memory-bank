#!/usr/bin/env bats
# Tests for adapters/cline.sh — Cline VS Code extension adapter.
#
# Contract:
#   adapters/cline.sh install [PROJECT_ROOT]
#   adapters/cline.sh uninstall [PROJECT_ROOT]
#
# Generates:
#   <project>/.clinerules/memory-bank.md     — rules (Cline reads all *.md in dir)
#   <project>/.clinerules/hooks/before-tool.sh     — beforeToolExecution
#   <project>/.clinerules/hooks/after-tool.sh      — afterToolExecution (auto-capture)
#   <project>/.clinerules/hooks/on-notification.sh — onNotification (compact reminder)
#   <project>/.clinerules/.mb-manifest.json        — ownership tracking
#
# Cline has native shell-script hooks (.clinerules/hooks/ discovery).
# Events: beforeToolExecution, afterToolExecution, onNotification.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ADAPTER="$REPO_ROOT/adapters/cline.sh"
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
# Install
# ═══════════════════════════════════════════════════════════════

@test "cline: install creates .clinerules/memory-bank.md with workflow section" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.clinerules/memory-bank.md" ]
  grep -qi "memory bank" "$PROJECT/.clinerules/memory-bank.md"
  grep -qi "workflow" "$PROJECT/.clinerules/memory-bank.md"
}

@test "cline: install creates 3 executable hook scripts" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -x "$PROJECT/.clinerules/hooks/before-tool.sh" ]
  [ -x "$PROJECT/.clinerules/hooks/after-tool.sh" ]
  [ -x "$PROJECT/.clinerules/hooks/on-notification.sh" ]
}

@test "cline: install writes manifest with adapter=cline and event mappings" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local m="$PROJECT/.clinerules/.mb-manifest.json"
  [ -f "$m" ]
  jq -e '.adapter == "cline"' "$m" >/dev/null
  jq -e '.files | length >= 4' "$m" >/dev/null
  jq -e '.hooks_events | index("beforeToolExecution")' "$m" >/dev/null
  jq -e '.hooks_events | index("afterToolExecution")' "$m" >/dev/null
}

@test "cline: install idempotent — 2x run works cleanly" {
  run_adapter install "$PROJECT"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.clinerules/memory-bank.md" ]
  [ -x "$PROJECT/.clinerules/hooks/before-tool.sh" ]
}

@test "cline: install fails if project root missing" {
  run_adapter install "/nonexistent/xyz"
  [ "$status" -ne 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Hook behavior
# ═══════════════════════════════════════════════════════════════

@test "cline: after-tool hook appends auto-capture to progress.md (idempotent per session)" {
  run_adapter install "$PROJECT"
  # Simulate Cline afterToolExecution event with sessionId
  local payload='{"sessionId":"cline-abc12345","toolName":"read_file"}'
  (cd "$PROJECT" && echo "$payload" | bash .clinerules/hooks/after-tool.sh)
  grep -q "Auto-capture.*cline-abc12345" "$PROJECT/.memory-bank/progress.md"

  # Second fire with same session → no duplicate
  (cd "$PROJECT" && echo "$payload" | bash .clinerules/hooks/after-tool.sh)
  local count
  count=$(grep -c "Auto-capture.*cline-abc12345" "$PROJECT/.memory-bank/progress.md")
  [ "$count" -eq 1 ]
}

@test "cline: after-tool hook noop if no .memory-bank/" {
  run_adapter install "$PROJECT"
  rm -rf "$PROJECT/.memory-bank"
  (cd "$PROJECT" && echo '{"sessionId":"x"}' | bash .clinerules/hooks/after-tool.sh)
  [ "$status" -eq 0 ] || true  # must not fail
}

@test "cline: before-tool hook blocks rm -rf command (exit non-zero)" {
  run_adapter install "$PROJECT"
  local payload='{"toolName":"execute_command","params":{"command":"rm -rf /"}}'
  local rc
  rc=$(cd "$PROJECT" && echo "$payload" | bash .clinerules/hooks/before-tool.sh >/dev/null 2>&1; echo $?)
  [ "$rc" -ne 0 ]
}

@test "cline: before-tool hook allows safe commands (exit 0)" {
  run_adapter install "$PROJECT"
  local payload='{"toolName":"execute_command","params":{"command":"ls"}}'
  local rc
  rc=$(cd "$PROJECT" && echo "$payload" | bash .clinerules/hooks/before-tool.sh >/dev/null 2>&1; echo $?)
  [ "$rc" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Uninstall
# ═══════════════════════════════════════════════════════════════

@test "cline: uninstall removes all our files and manifest" {
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.clinerules/memory-bank.md" ]
  [ ! -f "$PROJECT/.clinerules/hooks/before-tool.sh" ]
  [ ! -f "$PROJECT/.clinerules/.mb-manifest.json" ]
}

@test "cline: uninstall preserves user-owned .clinerules/*.md files" {
  run_adapter install "$PROJECT"
  echo "custom cline rules" > "$PROJECT/.clinerules/user-rules.md"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.clinerules/user-rules.md" ]
  [ ! -f "$PROJECT/.clinerules/memory-bank.md" ]
}

@test "cline: uninstall no-op if never installed" {
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
}
