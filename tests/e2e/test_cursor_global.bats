#!/usr/bin/env bats
# End-to-end test: Cursor global parity.
#
# Verifies that `install.sh` installs Cursor as a first-class global target:
#   - ~/.cursor/skills/memory-bank symlink on canonical bundle
#   - ~/.cursor/hooks.json + ~/.cursor/hooks/*.sh with three _mb_owned bindings
#   - ~/.cursor/commands/*.md (slash commands mirrored)
#   - ~/.cursor/AGENTS.md with marker section memory-bank-cursor:start/end
#   - ~/.cursor/memory-bank-user-rules.md ready for Settings → Rules → User Rules paste
#
# And that `uninstall.sh` reverses all of the above while preserving user content.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX_HOME="$(mktemp -d)"
  export HOME="$SANDBOX_HOME"

  command -v python3 >/dev/null || skip "python3 not installed"
  command -v jq      >/dev/null || skip "jq not installed"
}

teardown() {
  [ -n "${SANDBOX_HOME:-}" ] && [ -d "$SANDBOX_HOME" ] && rm -rf "$SANDBOX_HOME"
}

# ═══════════════════════════════════════════════════════════════
# Install
# ═══════════════════════════════════════════════════════════════

@test "cursor-global: install creates ~/.cursor/skills/memory-bank alias on canonical bundle" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -L "$HOME/.cursor/skills/memory-bank" ]

  canonical="$(python3 -c 'import os; print(os.path.realpath("'"$HOME"'/.claude/skills/skill-memory-bank"))')"
  cursor_alias="$(python3 -c 'import os; print(os.path.realpath("'"$HOME"'/.cursor/skills/memory-bank"))')"
  [ "$cursor_alias" = "$canonical" ]
}

@test "cursor-global: install writes ~/.cursor/hooks.json with three _mb_owned entries" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -f "$HOME/.cursor/hooks.json" ]
  owned_count=$(jq '[.hooks[][] | select(._mb_owned == true)] | length' "$HOME/.cursor/hooks.json")
  [ "$owned_count" -eq 3 ]
}

@test "cursor-global: install copies three hook scripts into ~/.cursor/hooks/" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -x "$HOME/.cursor/hooks/session-end-autosave.sh" ]
  [ -x "$HOME/.cursor/hooks/mb-compact-reminder.sh" ]
  [ -x "$HOME/.cursor/hooks/block-dangerous.sh" ]
}

@test "cursor-global: install copies slash commands into ~/.cursor/commands/" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -f "$HOME/.cursor/commands/mb.md" ]
  [ -f "$HOME/.cursor/commands/commit.md" ]
}

@test "cursor-global: install writes ~/.cursor/AGENTS.md with managed marker section" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -f "$HOME/.cursor/AGENTS.md" ]
  grep -q "<!-- memory-bank-cursor:start -->" "$HOME/.cursor/AGENTS.md"
  grep -q "<!-- memory-bank-cursor:end -->"   "$HOME/.cursor/AGENTS.md"
  grep -q "~/.cursor/skills/memory-bank/SKILL.md" "$HOME/.cursor/AGENTS.md"
}

@test "cursor-global: install writes ~/.cursor/memory-bank-user-rules.md paste-file" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -f "$HOME/.cursor/memory-bank-user-rules.md" ]
  # Paste-ready file must not contain marker comments
  ! grep -q "<!-- memory-bank-cursor:start -->" "$HOME/.cursor/memory-bank-user-rules.md"
  # And should reference the skill location so the user knows where rules live
  grep -q "~/.cursor/skills/memory-bank" "$HOME/.cursor/memory-bank-user-rules.md"
}

# ═══════════════════════════════════════════════════════════════
# Idempotency
# ═══════════════════════════════════════════════════════════════

@test "cursor-global: install is idempotent — two runs keep exactly three _mb_owned entries" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  bash "$REPO_ROOT/install.sh" >/dev/null

  owned_count=$(jq '[.hooks[][] | select(._mb_owned == true)] | length' "$HOME/.cursor/hooks.json")
  [ "$owned_count" -eq 3 ]
}

@test "cursor-global: install is idempotent — two runs keep one memory-bank-cursor section" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  bash "$REPO_ROOT/install.sh" >/dev/null

  start_count=$(grep -c "memory-bank-cursor:start" "$HOME/.cursor/AGENTS.md")
  [ "$start_count" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════
# Preserve user content
# ═══════════════════════════════════════════════════════════════

@test "cursor-global: install preserves pre-existing user hooks in ~/.cursor/hooks.json" {
  mkdir -p "$HOME/.cursor"
  cat > "$HOME/.cursor/hooks.json" <<'EOF'
{
  "version": 1,
  "hooks": {
    "afterFileEdit": [
      {"command": "echo user-hook"}
    ]
  }
}
EOF

  bash "$REPO_ROOT/install.sh" >/dev/null

  grep -q "user-hook" "$HOME/.cursor/hooks.json"
  owned_count=$(jq '[.hooks[][] | select(._mb_owned == true)] | length' "$HOME/.cursor/hooks.json")
  [ "$owned_count" -eq 3 ]
}

@test "cursor-global: install preserves pre-existing user content in ~/.cursor/AGENTS.md" {
  mkdir -p "$HOME/.cursor"
  cat > "$HOME/.cursor/AGENTS.md" <<'EOF'
# My Cursor personal rules

Always prefer vanilla CSS.
EOF

  bash "$REPO_ROOT/install.sh" >/dev/null

  grep -q "My Cursor personal rules" "$HOME/.cursor/AGENTS.md"
  grep -q "Always prefer vanilla CSS" "$HOME/.cursor/AGENTS.md"
  grep -q "memory-bank-cursor:start" "$HOME/.cursor/AGENTS.md"
}

# ═══════════════════════════════════════════════════════════════
# Uninstall roundtrip
# ═══════════════════════════════════════════════════════════════

@test "cursor-global: uninstall removes ~/.cursor/skills alias" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ ! -e "$HOME/.cursor/skills/memory-bank" ]
}

@test "cursor-global: uninstall removes hook scripts and empties hooks.json" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ ! -f "$HOME/.cursor/hooks/session-end-autosave.sh" ]
  [ ! -f "$HOME/.cursor/hooks/mb-compact-reminder.sh" ]
  [ ! -f "$HOME/.cursor/hooks/block-dangerous.sh" ]

  if [ -f "$HOME/.cursor/hooks.json" ]; then
    owned_count=$(jq '[.. | objects | select(._mb_owned == true)] | length' "$HOME/.cursor/hooks.json")
    [ "$owned_count" -eq 0 ]
  fi
}

@test "cursor-global: uninstall removes commands and paste-file" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ ! -f "$HOME/.cursor/commands/mb.md" ]
  [ ! -f "$HOME/.cursor/memory-bank-user-rules.md" ]
}

@test "cursor-global: uninstall strips memory-bank-cursor section from AGENTS.md" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  if [ -f "$HOME/.cursor/AGENTS.md" ]; then
    ! grep -q "memory-bank-cursor:start" "$HOME/.cursor/AGENTS.md"
    ! grep -q "memory-bank-cursor:end"   "$HOME/.cursor/AGENTS.md"
  fi
}

@test "cursor-global: uninstall preserves user content in ~/.cursor/AGENTS.md" {
  mkdir -p "$HOME/.cursor"
  cat > "$HOME/.cursor/AGENTS.md" <<'EOF'
# My Cursor personal rules

Always prefer vanilla CSS.
EOF

  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  grep -q "My Cursor personal rules" "$HOME/.cursor/AGENTS.md"
  grep -q "Always prefer vanilla CSS" "$HOME/.cursor/AGENTS.md"
  ! grep -q "memory-bank-cursor:start" "$HOME/.cursor/AGENTS.md"
}

@test "cursor-global: uninstall preserves user hooks in ~/.cursor/hooks.json" {
  mkdir -p "$HOME/.cursor"
  cat > "$HOME/.cursor/hooks.json" <<'EOF'
{
  "version": 1,
  "hooks": {
    "afterFileEdit": [
      {"command": "echo user-hook"}
    ]
  }
}
EOF

  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ -f "$HOME/.cursor/hooks.json" ]
  grep -q "user-hook" "$HOME/.cursor/hooks.json"
}

# ═══════════════════════════════════════════════════════════════
# Project adapter — no double `# Global Rules` heading
# ═══════════════════════════════════════════════════════════════

@test "cursor-global: project adapter .cursor/rules/memory-bank.mdc has exactly one # Global Rules heading" {
  PROJECT_ROOT="$(mktemp -d)"
  bash "$REPO_ROOT/install.sh" --clients claude-code,cursor --project-root "$PROJECT_ROOT" >/dev/null

  mdc="$PROJECT_ROOT/.cursor/rules/memory-bank.mdc"
  [ -f "$mdc" ]
  heading_count=$(grep -c '^# Global Rules$' "$mdc")
  [ "$heading_count" -eq 1 ]

  rm -rf "$PROJECT_ROOT"
}
