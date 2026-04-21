#!/usr/bin/env bats
# Tests for adapters/pi.sh — Pi Code cross-agent adapter (dual-mode).
#
# Contract:
#   adapters/pi.sh install [PROJECT_ROOT]
#   adapters/pi.sh uninstall [PROJECT_ROOT]
#
# Modes (via MB_PI_MODE env, default = agents-md):
#   agents-md  — AGENTS.md (shared, refcount) + git-hooks-fallback
#   skill      — experimental compatibility path, gated out of normal installs
#
# Pi Skills API is in active development (2026-04-20 research), so agents-md is default.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ADAPTER="$REPO_ROOT/adapters/pi.sh"
  PROJECT="$(mktemp -d)"
  (cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t)
  mkdir -p "$PROJECT/.memory-bank"
  echo '# Progress' > "$PROJECT/.memory-bank/progress.md"
  command -v jq >/dev/null || skip "jq required"
  # Isolated ~/.pi sandbox
  SANDBOX_HOME="$(mktemp -d)"
  export HOME="$SANDBOX_HOME"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
  [ -n "${SANDBOX_HOME:-}" ] && [ -d "$SANDBOX_HOME" ] && rm -rf "$SANDBOX_HOME"
}

run_adapter() {
  local raw
  raw=$(bash "$ADAPTER" "$@" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

# ═══════════════════════════════════════════════════════════════
# Default (agents-md) mode
# ═══════════════════════════════════════════════════════════════

@test "pi: default install uses agents-md mode (creates AGENTS.md + git-hooks)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q "memory-bank:start" "$PROJECT/AGENTS.md"
  [ -x "$PROJECT/.git/hooks/post-commit" ]
}

@test "pi: default manifest records mode=agents-md" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local m="$PROJECT/.mb-pi-manifest.json"
  [ -f "$m" ]
  jq -e '.schema_version == 1' "$m" >/dev/null
  jq -e '.adapter == "pi"' "$m" >/dev/null
  jq -e '.mode == "agents-md"' "$m" >/dev/null
}

@test "pi: uninstall (agents-md mode) removes our artifacts, preserves user hooks" {
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/AGENTS.md" ]
  [ ! -f "$PROJECT/.mb-pi-manifest.json" ]
  if [ -f "$PROJECT/.git/hooks/post-commit" ]; then
    ! grep -q "memory-bank: managed hook" "$PROJECT/.git/hooks/post-commit"
  fi
}

@test "pi: default mode requires git repo (git-hooks-fallback mandatory)" {
  local nongit
  nongit="$(mktemp -d)"
  mkdir -p "$nongit/.memory-bank"
  run_adapter install "$nongit"
  [ "$status" -ne 0 ]
  rm -rf "$nongit"
}

# ═══════════════════════════════════════════════════════════════
# Experimental skill mode gate
# ═══════════════════════════════════════════════════════════════

@test "pi: MB_PI_MODE=skill is rejected without experimental gate" {
  MB_PI_MODE=skill run_adapter install "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"experimental"* ]]
}

@test "pi: skill mode uninstall rejects poisoned manifest path outside ~/.pi/skills" {
  mkdir -p "$HOME/keep-me"
  echo "still here" > "$HOME/keep-me/file.txt"
  cat > "$PROJECT/.mb-pi-manifest.json" <<EOF
{
  "adapter": "pi",
  "mode": "skill",
  "pi_skill_dir": "$HOME/keep-me"
}
EOF

  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ -d "$HOME/keep-me" ]
  [ -f "$HOME/keep-me/file.txt" ]
  [ ! -f "$PROJECT/.mb-pi-manifest.json" ]
}

# ═══════════════════════════════════════════════════════════════
# Idempotency + edge cases
# ═══════════════════════════════════════════════════════════════

@test "pi: install idempotent — 2x run in default mode" {
  run_adapter install "$PROJECT"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local count
  count=$(grep -c "memory-bank:start" "$PROJECT/AGENTS.md")
  [ "$count" -eq 1 ]
}

@test "pi: uninstall no-op if never installed" {
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
}

@test "pi: coexistence with opencode — both active → single AGENTS.md section" {
  local OC_ADAPTER="$REPO_ROOT/adapters/opencode.sh"
  bash "$OC_ADAPTER" install "$PROJECT" >/dev/null
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local count
  count=$(grep -c "memory-bank:start" "$PROJECT/AGENTS.md")
  [ "$count" -eq 1 ]
  jq -e '.owners | contains(["opencode","pi"])' "$PROJECT/.mb-agents-owners.json" >/dev/null
}
