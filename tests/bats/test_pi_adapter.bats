#!/usr/bin/env bats
# Tests for adapters/pi.sh — Pi Code cross-agent adapter (dual-mode).
#
# Contract:
#   adapters/pi.sh install [PROJECT_ROOT]
#   adapters/pi.sh uninstall [PROJECT_ROOT]
#
# Modes (via MB_PI_MODE env, default = agents-md):
#   agents-md  — AGENTS.md (shared, refcount) + git-hooks-fallback when git exists
#   skill      — native ~/.pi/agent/skills/memory-bank package
#
# Pi global install is handled by install.sh; this adapter adds project-local wiring.

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

@test "pi: default mode works without git repo and skips git hooks" {
  local nongit
  nongit="$(mktemp -d)"
  mkdir -p "$nongit/.memory-bank"
  run_adapter install "$nongit"
  [ "$status" -eq 0 ]
  [ -f "$nongit/AGENTS.md" ]
  [ ! -d "$nongit/.git/hooks" ]
  jq -e '.git_hooks_installed == false' "$nongit/.mb-pi-manifest.json" >/dev/null
  rm -rf "$nongit"
}

# ═══════════════════════════════════════════════════════════════
# Native Pi skill mode
# ═══════════════════════════════════════════════════════════════

@test "pi: MB_PI_MODE=skill installs native Pi skill under ~/.pi/agent/skills" {
  MB_PI_MODE=skill run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.pi/agent/skills/memory-bank/SKILL.md" ]
  jq -e '.mode == "skill"' "$PROJECT/.mb-pi-manifest.json" >/dev/null
}

@test "pi: MB_PI_MODE=skill merges global AGENTS.md with mandatory mb-work gate" {
  mkdir -p "$HOME/.pi/agent"
  cat > "$HOME/.pi/agent/AGENTS.md" <<'EOF'
# Existing Pi Rules

Keep this.
EOF

  MB_PI_MODE=skill run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  MB_PI_MODE=skill run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]

  grep -q '^# Existing Pi Rules$' "$HOME/.pi/agent/AGENTS.md"
  grep -q 'Mandatory `/mb work` execution gate' "$HOME/.pi/agent/AGENTS.md"
  grep -q 'mb-workflow.sh' "$HOME/.pi/agent/AGENTS.md"
  local count
  count=$(grep -c 'memory-bank-pi:start' "$HOME/.pi/agent/AGENTS.md")
  [ "$count" -eq 1 ]
}

@test "pi: MB_PI_MODE=skill merges settings.json skills without overwriting user settings" {
  mkdir -p "$HOME/.pi/agent"
  cat > "$HOME/.pi/agent/settings.json" <<'EOF'
{
  "theme": "dark",
  "skills": ["~/.pi/agent/skills/custom-skill"]
}
EOF

  MB_PI_MODE=skill run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  MB_PI_MODE=skill run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]

  python3 -m json.tool "$HOME/.pi/agent/settings.json" >/dev/null
  jq -e '.theme == "dark"' "$HOME/.pi/agent/settings.json" >/dev/null
  jq -e '.skills[0] == "~/.pi/agent/skills/memory-bank"' "$HOME/.pi/agent/settings.json" >/dev/null
  jq -e '.skills | index("~/.pi/agent/skills/custom-skill") != null' "$HOME/.pi/agent/settings.json" >/dev/null
  jq -e '[.skills[] | select(. == "~/.pi/agent/skills/memory-bank")] | length == 1' "$HOME/.pi/agent/settings.json" >/dev/null
}

@test "pi: MB_PI_MODE=skill does not overwrite global symlinked Pi skill" {
  mkdir -p "$HOME/.claude/skills/skill-memory-bank" "$HOME/.pi/agent/skills"
  cp "$REPO_ROOT/SKILL.md" "$HOME/.claude/skills/skill-memory-bank/SKILL.md"
  ln -s "$HOME/.claude/skills/skill-memory-bank" "$HOME/.pi/agent/skills/memory-bank"
  before=$(shasum "$HOME/.claude/skills/skill-memory-bank/SKILL.md" | awk '{print $1}')

  MB_PI_MODE=skill run_adapter install "$PROJECT"

  [ "$status" -eq 0 ]
  after=$(shasum "$HOME/.claude/skills/skill-memory-bank/SKILL.md" | awk '{print $1}')
  [ "$after" = "$before" ]
  jq -e '.mode == "skill"' "$PROJECT/.mb-pi-manifest.json" >/dev/null
  jq -e '.global_skill_alias_detected == true' "$PROJECT/.mb-pi-manifest.json" >/dev/null
}

@test "pi: skill mode uninstall rejects poisoned manifest path outside ~/.pi/agent/skills" {
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

# ═══════════════════════════════════════════════════════════════
# Global storage support (Stage 3 — resolver-aware guidance)
# ═══════════════════════════════════════════════════════════════

@test "pi: AGENTS.md section mentions global storage or resolver for bank path" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local agents="$PROJECT/AGENTS.md"
  [ -f "$agents" ]
  # Shared AGENTS.md section must mention path resolution (local OR global)
  grep -qi "MB_PATH\|global storage\|resolver\|resolved\|local OR global\|local or global" "$agents"
}

@test "pi: MB_PI_MODE=skill SKILL.md mentions resolver or global storage guidance" {
  MB_PI_MODE=skill run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local skill_md="$HOME/.pi/agent/skills/memory-bank/SKILL.md"
  [ -f "$skill_md" ]
  # SKILL.md must mention resolver or global storage so Pi users discover the option
  grep -qi "MB_PATH\|global storage\|resolver\|resolved\|local OR global\|local or global" "$skill_md"
}
