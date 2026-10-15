#!/usr/bin/env bats
# SessionStart injects <bank>/orchestrator-console.md when present; unchanged otherwise.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/mb-session-start.sh"
  command -v jq >/dev/null 2>&1 || skip "jq not available"
  PROJECT="$(mktemp -d)"
  mkdir -p "$PROJECT/.memory-bank/session"
  printf '# Recent\nsomething\n' > "$PROJECT/.memory-bank/session/_recent.md"
  cd "$PROJECT" || return 1
}

teardown() { rm -rf "$PROJECT"; }

ctx() { printf '{"cwd":"%s","source":"compact"}' "$PROJECT" | MB_FRESHNESS_BANNER=off bash "$HOOK" | jq -r '.hookSpecificOutput.additionalContext'; }

@test "console present: content leads the context" {
  printf '# Console\nagent A running\n' > "$PROJECT/.memory-bank/orchestrator-console.md"
  run ctx
  [ "$status" -eq 0 ]
  [[ "$output" == "# Orchestrator console"* ]]
  [[ "$output" == *"agent A running"* ]]
  [[ "$output" == *"# Recent Sessions"* ]]
}

@test "console absent: no console section" {
  run ctx
  [[ "$output" != *"Orchestrator console"* ]]
  [[ "$output" == *"# Recent Sessions"* ]]
}

@test "console over the cap is truncated with a marker" {
  head -c 6000 /dev/zero | tr '\0' 'x' > "$PROJECT/.memory-bank/orchestrator-console.md"
  run ctx
  [[ "$output" == *"[console truncated]"* ]]
}
