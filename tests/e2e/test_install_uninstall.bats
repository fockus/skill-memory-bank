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
  [ -f "$HOME/.pi/agent/AGENTS.md" ]
  [ -d "$HOME/.claude/commands" ]
  [ -d "$HOME/.config/opencode/commands" ]
  [ -d "$HOME/.claude/agents" ]
  [ -d "$HOME/.claude/hooks" ]
  [ -L "$HOME/.claude/skills/skill-memory-bank" ]
  [ -L "$HOME/.claude/skills/memory-bank" ]
  [ -L "$HOME/.codex/skills/memory-bank" ]
  [ -L "$HOME/.pi/agent/skills/memory-bank" ]
}

@test "install: creates Pi global skill, AGENTS.md, and prompt templates" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -L "$HOME/.pi/agent/skills/memory-bank" ]
  [ -f "$HOME/.pi/agent/skills/memory-bank/SKILL.md" ]
  [ -f "$HOME/.pi/agent/AGENTS.md" ]
  grep -q "<!-- memory-bank-pi:start -->" "$HOME/.pi/agent/AGENTS.md"
  grep -q "<!-- memory-bank-pi:end -->" "$HOME/.pi/agent/AGENTS.md"
  grep -q "~/.pi/agent/skills/memory-bank/SKILL.md" "$HOME/.pi/agent/AGENTS.md"
  [ -f "$HOME/.pi/agent/prompts/mb.md" ]
  [ -f "$HOME/.pi/agent/prompts/start.md" ]
  [ -f "$HOME/.pi/agent/prompts/done.md" ]
  [ -f "$HOME/.pi/agent/prompts/plan.md" ]
}

@test "install: backs up existing Pi skill outside skill discovery directory" {
  mkdir -p "$HOME/.pi/agent/skills/memory-bank"
  cat > "$HOME/.pi/agent/skills/memory-bank/SKILL.md" <<'EOF'
---
name: memory-bank
---
# old local Pi skill
EOF

  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -L "$HOME/.pi/agent/skills/memory-bank" ]
  [ -f "$HOME/.pi/agent/skills/memory-bank/SKILL.md" ]
  [ -d "$HOME/.pi/agent/.memory-bank-backups" ]
  find "$HOME/.pi/agent/.memory-bank-backups" -maxdepth 2 -name SKILL.md | grep -q .
  ! find "$HOME/.pi/agent/skills" -maxdepth 2 -path '*pre-mb-backup*' -name SKILL.md | grep -q .
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
  [ -f "$HOME/.pi/agent/prompts/mb.md" ]
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
  [ -f "$HOME/.pi/agent/skills/memory-bank/commands/mb.md" ]
  [ -f "$HOME/.pi/agent/skills/memory-bank/agents/mb-manager.md" ]
  [ -f "$HOME/.pi/agent/skills/memory-bank/hooks/session-end-autosave.sh" ]
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

@test "install: Pi AGENTS.md is localized with --language ru" {
  bash "$REPO_ROOT/install.sh" --language ru >/dev/null
  grep -q "<!-- memory-bank-pi:start -->" "$HOME/.pi/agent/AGENTS.md"
  grep -q '\*\*Language\*\* — respond in Russian; technical terms may remain in English\.' "$HOME/.pi/agent/AGENTS.md"
}

@test "install: writes manifest" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  [ -f "$REPO_ROOT/.installed-manifest.json" ]
  python3 -c "import json; json.load(open('$REPO_ROOT/.installed-manifest.json'))"
}

@test "install: manifest has schema_version=1" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  [ -f "$REPO_ROOT/.installed-manifest.json" ]
  python3 - <<PY
import json

data = json.load(open("$REPO_ROOT/.installed-manifest.json"))
assert data["schema_version"] == 1
PY
}

@test "install: global manifest does not own Cursor global files" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  python3 - <<PY
import json

data = json.load(open("$REPO_ROOT/.installed-manifest.json"))
files = data["files"]
assert all("/.cursor/AGENTS.md" not in f for f in files)
assert all("/.cursor/hooks.json" not in f for f in files)
assert all("/.cursor/memory-bank-user-rules.md" not in f for f in files)
assert all("/.cursor/commands/mb.md" not in f for f in files)
assert any("/.pi/agent/prompts/mb.md" in f for f in files)
assert any("/.pi/agent/skills/memory-bank" in f for f in files)
PY
}

@test "install: refuses unsafe symlink target outside managed dirs" {
  mkdir -p "$HOME/.claude" "$HOME/outside"
  echo "keep me" > "$HOME/outside/victim.txt"
  ln -s "$HOME/outside/victim.txt" "$HOME/.claude/RULES.md"

  run bash "$REPO_ROOT/install.sh"
  [ "$status" -ne 0 ]
  grep -q "keep me" "$HOME/outside/victim.txt"
}

@test "install: idempotent — two runs yield no duplicate CLAUDE.md sections" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  bash "$REPO_ROOT/install.sh" >/dev/null

  count=$(grep -c "\[MEMORY-BANK-SKILL\]" "$HOME/.claude/CLAUDE.md")
  [ "$count" -eq 1 ]
  python3 - <<PY
from pathlib import Path
text = Path('$HOME/.claude/CLAUDE.md').read_text(encoding='utf-8')
assert text.startswith('# [MEMORY-BANK-SKILL]')
PY
}

@test "install: idempotent — two runs yield no duplicate Pi sections or leading blanks" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  bash "$REPO_ROOT/install.sh" >/dev/null

  count=$(grep -c "memory-bank-pi:start" "$HOME/.pi/agent/AGENTS.md")
  [ "$count" -eq 1 ]
  python3 - <<PY
from pathlib import Path
text = Path('$HOME/.pi/agent/AGENTS.md').read_text(encoding='utf-8')
assert text.startswith('<!-- memory-bank-pi:start -->')
PY
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
  [ ! -e "$HOME/.pi/agent/skills/memory-bank" ]
  [ ! -f "$HOME/.pi/agent/prompts/mb.md" ]
}

@test "uninstall: calls per-adapter uninstall for install-time --clients (A10 refcount decrement)" {
  command -v jq >/dev/null || skip "jq required"
  PROJECT="$(mktemp -d)"

  bash "$REPO_ROOT/install.sh" --clients codex,opencode --project-root "$PROJECT" --non-interactive >/dev/null

  [ -f "$PROJECT/AGENTS.md" ]
  [ -f "$PROJECT/.opencode/commands/mb.md" ]
  [ -f "$PROJECT/.codex/config.toml" ]
  jq -e '.owners | contains(["opencode","codex"])' "$PROJECT/.mb-agents-owners.json" >/dev/null

  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ ! -f "$PROJECT/.opencode/commands/mb.md" ]
  [ ! -f "$PROJECT/.codex/config.toml" ]
  # Both clients uninstalled → refcount reaches 0 → owners file + shared section removed.
  [ ! -f "$PROJECT/.mb-agents-owners.json" ]
  [ ! -f "$PROJECT/AGENTS.md" ]

  rm -rf "$PROJECT"
}

@test "uninstall: -y removes installed files without stdin prompt" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  run bash "$REPO_ROOT/uninstall.sh" -y

  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.claude/RULES.md" ]
  [ ! -e "$HOME/.claude/skills/memory-bank" ]
  [ ! -e "$HOME/.pi/agent/skills/memory-bank" ]
}

@test "uninstall: skips poisoned manifest paths outside managed dirs" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  mkdir -p "$HOME/victim-dir"
  echo "do not delete" > "$HOME/victim-dir/keep.txt"

  python3 - <<PY
import json
from pathlib import Path

manifest = Path("$REPO_ROOT/.installed-manifest.json")
data = json.loads(manifest.read_text())
data["files"].append("$HOME/.claude/../victim-dir")
manifest.write_text(json.dumps(data, indent=2))
PY

  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ -d "$HOME/victim-dir" ]
  [ -f "$HOME/victim-dir/keep.txt" ]
}

@test "uninstall: removes Cursor global files even if global manifest lacks them" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  python3 - <<PY
import json
from pathlib import Path

manifest = Path("$REPO_ROOT/.installed-manifest.json")
data = json.loads(manifest.read_text())
data["files"] = [
    f for f in data["files"]
    if "/.cursor/" not in f
]
manifest.write_text(json.dumps(data, indent=2))
PY

  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ ! -f "$HOME/.cursor/hooks.json" ]
  [ ! -f "$HOME/.cursor/AGENTS.md" ]
  [ ! -f "$HOME/.cursor/memory-bank-user-rules.md" ]
  [ ! -f "$HOME/.cursor/commands/mb.md" ]
  [ ! -f "$HOME/.cursor/.mb-manifest.json" ]
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

@test "uninstall: strips Pi managed section from AGENTS.md and removes prompts" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ ! -f "$HOME/.pi/agent/prompts/mb.md" ]
  if [ -f "$HOME/.pi/agent/AGENTS.md" ]; then
    ! grep -q "memory-bank-pi:start" "$HOME/.pi/agent/AGENTS.md"
  fi
}

@test "uninstall: restores pre-existing Pi skill from hidden backup" {
  mkdir -p "$HOME/.pi/agent/skills/memory-bank"
  cat > "$HOME/.pi/agent/skills/memory-bank/SKILL.md" <<'EOF'
---
name: memory-bank
---
# old local Pi skill
EOF

  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ -d "$HOME/.pi/agent/skills/memory-bank" ]
  [ ! -L "$HOME/.pi/agent/skills/memory-bank" ]
  grep -q "old local Pi skill" "$HOME/.pi/agent/skills/memory-bank/SKILL.md"
  [ ! -d "$HOME/.pi/agent/.memory-bank-backups" ]
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

@test "uninstall: preserves CLAUDE.md edits the user made AFTER install (A20 / CDX-I9)" {
  # Regression for CDX-I9: a backup only gets recorded when CLAUDE.md already
  # existed pre-install (backup_if_exists is a no-op otherwise) — this is the
  # scenario where uninstall.sh used to `mv` that PRE-install backup straight
  # back over CLAUDE.md, discarding both the pre-existing content AND anything
  # the user added after install ran. The managed block must instead be
  # stripped surgically (paired A13 markers), leaving everything else intact.
  mkdir -p "$HOME/.claude"
  echo "# Pre-existing user content" > "$HOME/.claude/CLAUDE.md"

  bash "$REPO_ROOT/install.sh" >/dev/null

  echo "" >> "$HOME/.claude/CLAUDE.md"
  echo "USER_POST_INSTALL_EDIT: keep me" >> "$HOME/.claude/CLAUDE.md"

  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ -f "$HOME/.claude/CLAUDE.md" ]
  grep -q "Pre-existing user content" "$HOME/.claude/CLAUDE.md"
  grep -q "USER_POST_INSTALL_EDIT: keep me" "$HOME/.claude/CLAUDE.md"
  ! grep -q "\[MEMORY-BANK-SKILL\]" "$HOME/.claude/CLAUDE.md"
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

@test "uninstall: preserves user Pi AGENTS.md content above skill section" {
  mkdir -p "$HOME/.pi/agent"
  cat > "$HOME/.pi/agent/AGENTS.md" <<'EOF'
# User Pi rules

Keep Pi concise.
EOF

  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  grep -q "User Pi rules" "$HOME/.pi/agent/AGENTS.md"
  grep -q "Keep Pi concise." "$HOME/.pi/agent/AGENTS.md"
  ! grep -q "memory-bank-pi:start" "$HOME/.pi/agent/AGENTS.md"
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

# ═══════════════════════════════════════════════════════════════
# A22 (CDX-I11): fail loudly on a corrupt manifest instead of
# silently treating it as empty (uninstall.sh used to `|| true` past a
# JSON-parse failure and just... remove nothing).
# ═══════════════════════════════════════════════════════════════

@test "uninstall: exits nonzero on a corrupt manifest without --force" {
  export MB_MANIFEST_PATH="$HOME/.mb-a22-corrupt-manifest.json"
  printf '{"schema_version": 1, "files": [' > "$MB_MANIFEST_PATH"   # truncated JSON

  run bash "$REPO_ROOT/uninstall.sh" -y
  [ "$status" -ne 0 ]
  [[ "$output" == *"corrupt"* ]] || [[ "$output" == *"invalid"* ]]
  # It must not have been silently treated as an empty/no-op manifest.
  [ -f "$MB_MANIFEST_PATH" ]
}

@test "uninstall: --force proceeds past a corrupt manifest" {
  export MB_MANIFEST_PATH="$HOME/.mb-a22-corrupt-manifest-force.json"
  printf '{"schema_version": 1, "files": [' > "$MB_MANIFEST_PATH"   # truncated JSON

  run bash "$REPO_ROOT/uninstall.sh" -y --force
  [ "$status" -eq 0 ]
}

@test "uninstall: no-tty without -y exits nonzero with a hint instead of hanging (A24)" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  run bash "$REPO_ROOT/uninstall.sh" < /dev/null

  [ "$status" -ne 0 ]
  [[ "$output" == *"-y"* ]]
  # Files must still be present — no half-applied removal happened.
  [ -f "$HOME/.claude/RULES.md" ]
}

@test "uninstall: -y still works with no tty on stdin (A24)" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  run bash "$REPO_ROOT/uninstall.sh" -y < /dev/null

  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.claude/RULES.md" ]
}

@test "uninstall: pipe with real y answers the prompt normally (A24 no regression)" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ ! -f "$HOME/.claude/RULES.md" ]
}

# ═══════════════════════════════════════════════════════════════
# A6 (H-4): backup rotation preserves the user's TRUE original
# A7 (H-5): incremental/trap manifest survives partial failure
# ═══════════════════════════════════════════════════════════════

@test "install: upgrade preserves the user's TRUE original backup across two installs (A6)" {
  mkdir -p "$HOME/.claude"
  printf 'USER_RULES_ORIGINAL\n' > "$HOME/.claude/RULES.md"
  bash "$REPO_ROOT/install.sh" >/dev/null 2>&1            # #1: backs up user RULES.md → T1 (true original)
  printf '\nlocal_edit\n' >> "$HOME/.claude/RULES.md"     # make the installed file differ so #2 re-backs-up
  bash "$REPO_ROOT/install.sh" >/dev/null 2>&1            # #2: rotation must NOT delete the true original
  found=0
  for b in "$HOME/.claude/RULES.md.pre-mb-backup."*; do
    [ -f "$b" ] && grep -q "USER_RULES_ORIGINAL" "$b" && found=1
  done
  [ "$found" = "1" ]
}

@test "install: partial failure still writes a manifest for rollback (A7 trap flush)" {
  mkdir -p "$HOME/.claude"
  : > "$HOME/.claude/agents"          # poison Step 2: mkdir .claude/agents/ fails mid-install
  export MB_MANIFEST_PATH="$HOME/.mb-test-manifest.json"
  run bash "$REPO_ROOT/install.sh"
  [ "$status" -ne 0 ]                 # install aborted mid-way
  [ -f "$MB_MANIFEST_PATH" ]          # trap flushed a manifest anyway
  python3 -c "import json; m=json.load(open('$MB_MANIFEST_PATH')); assert len(m.get('files',[]))>=1, 'manifest has no files'"
}

# ═══════════════════════════════════════════════════════════════
# A12 (M-4): user-writable manifest path for pip/sudo installs
# ═══════════════════════════════════════════════════════════════

setup_readonly_skill_sandbox() {
  command -v rsync >/dev/null || skip "rsync required"
  RO_SKILL_PARENT="$(mktemp -d)"
  RO_SKILL_SRC="$RO_SKILL_PARENT/skill"
  mkdir -p "$RO_SKILL_SRC"
  rsync -a \
    --exclude='.git' \
    --exclude='*.pre-mb-backup.*' \
    --exclude='.index' \
    --exclude='node_modules' \
    --exclude='.installed-manifest.json' \
    "$REPO_ROOT/" "$RO_SKILL_SRC/"
  # Simulate a pip/sudo install tree: readable+executable, not writable by us.
  chmod -R a-w "$RO_SKILL_SRC"
}

teardown_readonly_skill_sandbox() {
  [ -n "${RO_SKILL_SRC:-}" ] && [ -d "$RO_SKILL_SRC" ] && chmod -R u+w "$RO_SKILL_SRC"
  [ -n "${RO_SKILL_PARENT:-}" ] && [ -d "$RO_SKILL_PARENT" ] && rm -rf "$RO_SKILL_PARENT"
}

@test "install: manifest falls back to XDG data dir when skill dir is read-only (A12)" {
  setup_readonly_skill_sandbox
  unset XDG_DATA_HOME

  run env MB_SKIP_DEPS_CHECK=1 bash "$RO_SKILL_SRC/install.sh" --non-interactive
  [ "$status" -eq 0 ]

  # Not silently lost inside the unwritable tree...
  [ ! -f "$RO_SKILL_SRC/.installed-manifest.json" ]
  # ...but present at the user-writable fallback, and valid JSON.
  local fallback="$HOME/.local/share/memory-bank/.installed-manifest.json"
  [ -f "$fallback" ]
  python3 -c "import json; json.load(open('$fallback'))"

  teardown_readonly_skill_sandbox
}

@test "install: manifest write failure is logged, not silently swallowed (A12)" {
  setup_readonly_skill_sandbox
  # Fallback dir itself unwritable too — both candidate paths fail.
  mkdir -p "$HOME/.local/share/memory-bank"
  chmod a-w "$HOME/.local/share/memory-bank"

  run env MB_SKIP_DEPS_CHECK=1 bash "$RO_SKILL_SRC/install.sh" --non-interactive
  # Install still completes (manifest is a rollback aid, not a hard blocker)...
  [ "$status" -eq 0 ]
  # ...but the failure is reported, not hidden behind a bare generic string.
  [[ "$output" == *"Manifest write failed"* ]]
  [[ "$output" == *"Permission denied"* ]] || [[ "$output" == *"Errno 13"* ]]

  chmod u+w "$HOME/.local/share/memory-bank"
  teardown_readonly_skill_sandbox
}

@test "uninstall: finds manifest at the same XDG fallback install.sh used (A12)" {
  setup_readonly_skill_sandbox
  unset XDG_DATA_HOME

  bash "$RO_SKILL_SRC/install.sh" --non-interactive >/dev/null 2>&1

  local fallback="$HOME/.local/share/memory-bank/.installed-manifest.json"
  [ -f "$fallback" ]

  echo "y" | bash "$RO_SKILL_SRC/uninstall.sh" >/dev/null
  [ ! -f "$fallback" ]
  [ ! -f "$HOME/.claude/RULES.md" ]

  teardown_readonly_skill_sandbox
}
