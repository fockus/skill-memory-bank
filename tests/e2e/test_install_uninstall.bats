#!/usr/bin/env bats
# End-to-end test: install.sh → verify files → uninstall.sh → verify clean.
#
# Runs against an isolated HOME directory — does not touch the real ~/.claude/.
# Works on macOS and Linux without Docker.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX_HOME="$(mktemp -d)"
  export HOME="$SANDBOX_HOME"

  # Ensure Python 3 + jq-less mode. install.sh uses python3 for manifest + merge-hooks.
  command -v python3 >/dev/null || skip "python3 not installed"
}

teardown() {
  [ -n "${SANDBOX_HOME:-}" ] && [ -d "$SANDBOX_HOME" ] && rm -rf "$SANDBOX_HOME"
}

# ═══════════════════════════════════════════════════════════════
# Install
# ═══════════════════════════════════════════════════════════════

@test "install: creates RULES, CLAUDE.md, commands, agents, hooks" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -f "$HOME/.claude/RULES.md" ]
  [ -f "$HOME/.claude/CLAUDE.md" ]
  [ -f "$HOME/.claude/memory-bank-config.json" ]
  [ -f "$HOME/.codex/AGENTS.md" ]
  [ -f "$HOME/.config/opencode/AGENTS.md" ]
  [ -d "$HOME/.claude/commands" ]
  [ -d "$HOME/.config/opencode/commands" ]
  [ -d "$HOME/.claude/agents" ]
  [ -d "$HOME/.claude/hooks" ]
  [ -L "$HOME/.claude/skills/skill-memory-bank" ]
  [ -L "$HOME/.claude/skills/memory-bank" ]
  [ -L "$HOME/.codex/skills/memory-bank" ]
}

@test "install: default language is English in installed rules and config" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  grep -q '1. \*\*Language\*\*: English — responses and code comments' "$HOME/.claude/RULES.md"
  grep -q '\*\*Language\*\* — respond in English; technical terms may remain in English\.' "$HOME/.claude/CLAUDE.md"
  grep -q 'comments in English' "$HOME/.claude/settings.json"
  grep -q '"preferred_language": "en"' "$HOME/.claude/memory-bank-config.json"
}

@test "install: --language ru localizes global rules and settings" {
  bash "$REPO_ROOT/install.sh" --language ru >/dev/null

  grep -q '1. \*\*Language\*\*: Russian — responses and code comments' "$HOME/.claude/RULES.md"
  grep -q '\*\*Language\*\* — respond in Russian; technical terms may remain in English\.' "$HOME/.claude/CLAUDE.md"
  grep -q 'comments in Russian' "$HOME/.claude/settings.json"
  grep -q '"preferred_language": "ru"' "$HOME/.claude/memory-bank-config.json"
}

@test "install: copies expected commands" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  # Key commands must exist
  [ -f "$HOME/.claude/commands/mb.md" ]
  [ -f "$HOME/.config/opencode/commands/mb.md" ]
  [ -f "$HOME/.claude/commands/commit.md" ]
  [ -f "$HOME/.claude/commands/review.md" ]
  [ -f "$HOME/.claude/commands/plan.md" ]
  # Setup-project removed in v2
  [ ! -f "$HOME/.claude/commands/setup-project.md" ]
}

@test "install: copies 4 MB-native agents" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -f "$HOME/.claude/agents/mb-manager.md" ]
  [ -f "$HOME/.claude/agents/mb-doctor.md" ]
  [ -f "$HOME/.claude/agents/plan-verifier.md" ]
  [ -f "$HOME/.claude/agents/mb-codebase-mapper.md" ]
  # Orphan agent must be gone
  [ ! -f "$HOME/.claude/agents/codebase-mapper.md" ]
}

@test "install: creates settings.json with MB hooks" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -f "$HOME/.claude/settings.json" ]
  grep -q "memory-bank-skill" "$HOME/.claude/settings.json"
}

@test "install: skill scripts are executable" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  for s in mb-context.sh mb-metrics.sh mb-plan.sh mb-plan-sync.sh mb-plan-done.sh _lib.sh; do
    [ -x "$HOME/.claude/skills/memory-bank/scripts/$s" ]
  done
}

@test "install: v3.1 scripts are executable (idea, idea-promote, adr, migrate-structure)" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  for s in mb-idea.sh mb-idea-promote.sh mb-adr.sh mb-migrate-structure.sh mb-compact.sh; do
    [ -x "$HOME/.claude/skills/memory-bank/scripts/$s" ]
  done
}

@test "install: skill bundle is complete for Claude and Codex aliases" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -f "$HOME/.claude/skills/memory-bank/SKILL.md" ]
  [ -d "$HOME/.claude/skills/memory-bank/commands" ]
  [ -d "$HOME/.claude/skills/memory-bank/agents" ]
  [ -d "$HOME/.claude/skills/memory-bank/hooks" ]
  [ -d "$HOME/.claude/skills/memory-bank/scripts" ]
  [ -d "$HOME/.claude/skills/memory-bank/references" ]
  [ -d "$HOME/.claude/skills/memory-bank/rules" ]
  [ -f "$HOME/.claude/skills/memory-bank/commands/mb.md" ]
  [ -f "$HOME/.claude/skills/memory-bank/agents/mb-manager.md" ]
  [ -f "$HOME/.claude/skills/memory-bank/hooks/session-end-autosave.sh" ]
  [ -f "$HOME/.codex/skills/memory-bank/commands/mb.md" ]
  [ -f "$HOME/.codex/skills/memory-bank/agents/mb-manager.md" ]
  [ -f "$HOME/.codex/skills/memory-bank/hooks/session-end-autosave.sh" ]
}

@test "install: Claude and Codex aliases resolve to canonical skill path" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  claude_canonical="$(python3 -c 'import os; print(os.path.realpath("'"$HOME"'/.claude/skills/skill-memory-bank"))')"
  claude_alias="$(python3 -c 'import os; print(os.path.realpath("'"$HOME"'/.claude/skills/memory-bank"))')"
  codex_alias="$(python3 -c 'import os; print(os.path.realpath("'"$HOME"'/.codex/skills/memory-bank"))')"

  [ "$claude_canonical" = "$REPO_ROOT" ]
  [ "$claude_alias" = "$claude_canonical" ]
  [ "$codex_alias" = "$claude_canonical" ]
}

@test "install: CLAUDE.md has MEMORY-BANK-SKILL marker" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  grep -q "\[MEMORY-BANK-SKILL\]" "$HOME/.claude/CLAUDE.md"
}

@test "install: OpenCode AGENTS.md has memory-bank markers" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  grep -q "<!-- memory-bank:start -->" "$HOME/.config/opencode/AGENTS.md"
  grep -q "<!-- memory-bank:end -->" "$HOME/.config/opencode/AGENTS.md"
}

@test "install: Codex AGENTS.md has managed memory-bank block" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  grep -q "<!-- memory-bank-codex:start -->" "$HOME/.codex/AGENTS.md"
  grep -q "<!-- memory-bank-codex:end -->" "$HOME/.codex/AGENTS.md"
  grep -q "~/.codex/skills/memory-bank/SKILL.md" "$HOME/.codex/AGENTS.md"
}

@test "install: writes manifest" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  [ -f "$REPO_ROOT/.installed-manifest.json" ]
  python3 -c "import json; json.load(open('$REPO_ROOT/.installed-manifest.json'))"
}

@test "install: idempotent — two runs yield no duplicate CLAUDE.md sections" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  bash "$REPO_ROOT/install.sh" >/dev/null

  count=$(grep -c "\[MEMORY-BANK-SKILL\]" "$HOME/.claude/CLAUDE.md")
  [ "$count" -eq 1 ]
}

@test "install: idempotent — settings.json has no duplicate hooks" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  bash "$REPO_ROOT/install.sh" >/dev/null

  # Each skill hook command should appear exactly once
  block_count=$(grep -c "block-dangerous.sh" "$HOME/.claude/settings.json")
  [ "$block_count" -eq 1 ]
}

@test "install: SessionEnd auto-capture hook registered and executable" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  # Hook copied
  [ -x "$HOME/.claude/hooks/session-end-autosave.sh" ]

  # Event is registered in settings.json
  grep -q "SessionEnd" "$HOME/.claude/settings.json"
  grep -q "session-end-autosave.sh" "$HOME/.claude/settings.json"
}

@test "install: SessionEnd idempotent — two runs = one entry" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  bash "$REPO_ROOT/install.sh" >/dev/null

  count=$(grep -c "session-end-autosave.sh" "$HOME/.claude/settings.json")
  [ "$count" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════
# Uninstall roundtrip
# ═══════════════════════════════════════════════════════════════

@test "uninstall: removes installed files" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ ! -f "$HOME/.claude/RULES.md" ]
  [ ! -f "$HOME/.claude/commands/mb.md" ]
  [ ! -f "$HOME/.config/opencode/commands/mb.md" ]
  [ ! -f "$HOME/.claude/agents/mb-manager.md" ]
  [ ! -f "$HOME/.claude/hooks/block-dangerous.sh" ]
  [ ! -f "$HOME/.claude/hooks/session-end-autosave.sh" ]
  [ ! -e "$HOME/.claude/skills/skill-memory-bank" ]
  [ ! -e "$HOME/.claude/skills/memory-bank" ]
  [ ! -e "$HOME/.codex/skills/memory-bank" ]
}

@test "uninstall: SessionEnd hook removed from settings.json" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  if [ -f "$HOME/.claude/settings.json" ]; then
    ! grep -q "session-end-autosave.sh" "$HOME/.claude/settings.json"
  fi
}

@test "uninstall: strips MB hooks from settings.json" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  # settings.json may still exist, but must not contain memory-bank-skill markers
  if [ -f "$HOME/.claude/settings.json" ]; then
    ! grep -q "memory-bank-skill" "$HOME/.claude/settings.json"
  fi
}

@test "uninstall: strips Codex managed section from AGENTS.md" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  if [ -f "$HOME/.codex/AGENTS.md" ]; then
    ! grep -q "memory-bank-codex:start" "$HOME/.codex/AGENTS.md"
  fi
}

@test "uninstall: strips MEMORY-BANK-SKILL section from CLAUDE.md" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  if [ -f "$HOME/.claude/CLAUDE.md" ]; then
    ! grep -q "\[MEMORY-BANK-SKILL\]" "$HOME/.claude/CLAUDE.md"
  fi
}

@test "uninstall: preserves user CLAUDE.md content above skill section" {
  # User has their own CLAUDE.md before install
  mkdir -p "$HOME/.claude"
  echo "# User's own preferences" > "$HOME/.claude/CLAUDE.md"
  echo "Important project rules" >> "$HOME/.claude/CLAUDE.md"

  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  grep -q "User's own preferences" "$HOME/.claude/CLAUDE.md"
  grep -q "Important project rules" "$HOME/.claude/CLAUDE.md"
}

@test "uninstall: preserves user OpenCode AGENTS.md content above skill section" {
  mkdir -p "$HOME/.config/opencode"
  cat > "$HOME/.config/opencode/AGENTS.md" <<'EOF'
# User OpenCode rules

Keep answers concise.
EOF

  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  grep -q "User OpenCode rules" "$HOME/.config/opencode/AGENTS.md"
  grep -q "Keep answers concise" "$HOME/.config/opencode/AGENTS.md"
  ! grep -q "memory-bank:start" "$HOME/.config/opencode/AGENTS.md"
}

@test "uninstall: preserves user Codex AGENTS.md content above skill section" {
  mkdir -p "$HOME/.codex"
  cat > "$HOME/.codex/AGENTS.md" <<'EOF'
# User Codex rules

Respect existing workflows.
EOF

  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  grep -q "User Codex rules" "$HOME/.codex/AGENTS.md"
  grep -q "Respect existing workflows." "$HOME/.codex/AGENTS.md"
  ! grep -q "memory-bank-codex:start" "$HOME/.codex/AGENTS.md"
}

@test "uninstall: preserves user hooks in settings.json" {
  # User has their own settings before install
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Edit", "hooks": [{"type": "command", "command": "echo user-edit-hook"}]}
    ]
  }
}
EOF

  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  # User hook survives both install and uninstall
  grep -q "user-edit-hook" "$HOME/.claude/settings.json"
}

@test "uninstall: removes manifest after cleanup" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ ! -f "$REPO_ROOT/.installed-manifest.json" ]
}
