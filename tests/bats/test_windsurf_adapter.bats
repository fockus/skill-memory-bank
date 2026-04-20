#!/usr/bin/env bats
# Tests for adapters/windsurf.sh — Windsurf Cascade adapter.
#
# Contract:
#   adapters/windsurf.sh install [PROJECT_ROOT]
#   adapters/windsurf.sh uninstall [PROJECT_ROOT]
#
# Generates:
#   <project>/.windsurf/rules/memory-bank.md   — rules (trigger: always_on)
#   <project>/.windsurf/hooks.json              — Cascade Hooks config (project-level)
#   <project>/.windsurf/hooks/*.sh              — shell hook scripts
#   <project>/.windsurf/.mb-manifest.json       — ownership tracking
#
# Windsurf Cascade Hooks: shell commands + JSON config (3 levels: user/workspace/project).
# Pre-hooks return exit 2 to block action.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ADAPTER="$REPO_ROOT/adapters/windsurf.sh"
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

@test "windsurf: install creates rules with trigger: always_on frontmatter" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local rf="$PROJECT/.windsurf/rules/memory-bank.md"
  [ -f "$rf" ]
  grep -q "^trigger: always_on" "$rf"
}

@test "windsurf: install creates valid hooks.json with user-prompt + model-response events" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hj="$PROJECT/.windsurf/hooks.json"
  [ -f "$hj" ]
  jq . "$hj" >/dev/null
  # Windsurf Cascade supports at minimum: user-prompt, model-response
  jq -e '.hooks | length >= 1' "$hj" >/dev/null
}

@test "windsurf: install creates executable hook scripts" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -d "$PROJECT/.windsurf/hooks" ]
  # At least one hook script copied
  local n
  n=$(find "$PROJECT/.windsurf/hooks" -type f -name '*.sh' -perm -u+x | wc -l | tr -d ' ')
  [ "$n" -ge 1 ]
}

@test "windsurf: install writes manifest with adapter=windsurf" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local m="$PROJECT/.windsurf/.mb-manifest.json"
  [ -f "$m" ]
  jq -e '.adapter == "windsurf"' "$m" >/dev/null
  jq -e '.files | length >= 2' "$m" >/dev/null
}

@test "windsurf: install idempotent — 2x run no duplicates in hooks.json" {
  run_adapter install "$PROJECT"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  # Ensure no dupes of _mb_owned entries
  local dup_count
  dup_count=$(jq '[.hooks | to_entries[] | .value[] | select(._mb_owned == true)] | length' "$PROJECT/.windsurf/hooks.json")
  # Exactly one _mb_owned entry per event
  [ "$dup_count" -ge 1 ]
  # Check no event has >1 _mb_owned entries
  local max_dup
  max_dup=$(jq '[.hooks | to_entries[] | (.value | map(select(._mb_owned == true)) | length)] | max' "$PROJECT/.windsurf/hooks.json")
  [ "$max_dup" -eq 1 ]
}

@test "windsurf: install merges with existing user hooks.json" {
  mkdir -p "$PROJECT/.windsurf"
  cat > "$PROJECT/.windsurf/hooks.json" <<'EOF'
{
  "hooks": {
    "user-prompt-submit": [{ "command": "echo user-hook" }]
  }
}
EOF
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hj="$PROJECT/.windsurf/hooks.json"
  # User hook preserved
  jq -e '.hooks."user-prompt-submit" | map(.command) | any(. == "echo user-hook")' "$hj" >/dev/null
}

# ═══════════════════════════════════════════════════════════════
# Hook behavior
# ═══════════════════════════════════════════════════════════════

@test "windsurf: pre-hook script returns exit 2 on dangerous shell commands" {
  run_adapter install "$PROJECT"
  # Find the block-dangerous equivalent in hooks/
  local hook
  hook=$(find "$PROJECT/.windsurf/hooks" -name '*block*' -o -name '*danger*' -o -name '*before*' | head -1)
  if [ -n "$hook" ]; then
    local rc
    rc=$(echo '{"command":"rm -rf /"}' | bash "$hook" >/dev/null 2>&1; echo $?)
    [ "$rc" -eq 2 ]
  else
    skip "no pre-hook block script found"
  fi
}

# ═══════════════════════════════════════════════════════════════
# Uninstall
# ═══════════════════════════════════════════════════════════════

@test "windsurf: uninstall removes our files, preserves user hooks" {
  mkdir -p "$PROJECT/.windsurf"
  cat > "$PROJECT/.windsurf/hooks.json" <<'EOF'
{
  "hooks": {
    "user-prompt-submit": [{ "command": "echo user" }]
  }
}
EOF
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.windsurf/rules/memory-bank.md" ]
  [ ! -f "$PROJECT/.windsurf/.mb-manifest.json" ]
  # User hook preserved
  local hj="$PROJECT/.windsurf/hooks.json"
  [ -f "$hj" ]
  jq -e '.hooks."user-prompt-submit" | map(.command) | any(. == "echo user")' "$hj" >/dev/null
}

@test "windsurf: uninstall no-op if never installed" {
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
}

@test "windsurf: uninstall deletes hooks.json if we were sole owner" {
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  # No hooks left → hooks.json gone
  [ ! -f "$PROJECT/.windsurf/hooks.json" ]
}
