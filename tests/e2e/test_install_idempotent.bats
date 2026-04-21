#!/usr/bin/env bats
# End-to-end test: install.sh idempotency.
#
# Verifies that `install.sh` backs up files only when content actually changes:
#   1. Second install on already-installed system → zero new .pre-mb-backup.* files.
#   2. Install after source file bump → exactly one backup per changed file.
#   3. Install after external delete of managed files → zero backups (nothing to back up).
#   4. Language swap (en → ru) → RULES.md backed up (localized differently), other files untouched.
#   5. Manifest `.backups[]` contains only paths that still exist on disk.

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

count_backups() {
  find "$HOME/.claude" "$HOME/.cursor" "$HOME/.codex" "$HOME/.config/opencode" \
    -name "*.pre-mb-backup.*" 2>/dev/null | wc -l | tr -d ' '
}

# ═══════════════════════════════════════════════════════════════
# Scenario 1 — second install creates zero new backups
# ═══════════════════════════════════════════════════════════════

@test "idempotent: second install creates zero new .pre-mb-backup.* files" {
  bash "$REPO_ROOT/install.sh" --non-interactive --language en --clients claude-code,cursor >/dev/null
  after_first="$(count_backups)"

  sleep 2  # ensure timestamp would differ if backups were created
  bash "$REPO_ROOT/install.sh" --non-interactive --language en --clients claude-code,cursor >/dev/null
  after_second="$(count_backups)"

  [ "$after_first" -eq 0 ]
  [ "$after_second" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Scenario 2 — src bump → one backup per changed file
# ═══════════════════════════════════════════════════════════════

@test "idempotent: install after src bump creates exactly one backup per changed file" {
  bash "$REPO_ROOT/install.sh" --non-interactive --language en --clients claude-code >/dev/null
  initial="$(count_backups)"
  [ "$initial" -eq 0 ]

  # Mutate the installed copy of mb.md — simulates updated source by editing target directly.
  # Because install_file does cmp src dst, touching the dst is what triggers a real diff.
  # More realistic: mutate dst so next install sees src != dst → one backup.
  echo "# user-modified content" >> "$HOME/.claude/commands/mb.md"

  sleep 2
  bash "$REPO_ROOT/install.sh" --non-interactive --language en --clients claude-code >/dev/null

  after="$(count_backups)"
  [ "$after" -eq 1 ]

  backup_file=$(find "$HOME/.claude/commands" -name "mb.md.pre-mb-backup.*" | head -1)
  [ -n "$backup_file" ]
  grep -q "user-modified content" "$backup_file"
}

# ═══════════════════════════════════════════════════════════════
# Scenario 3 — install after external delete → zero backups
# ═══════════════════════════════════════════════════════════════

@test "idempotent: install after external delete of managed files creates zero backups" {
  bash "$REPO_ROOT/install.sh" --non-interactive --language en --clients claude-code >/dev/null
  [ "$(count_backups)" -eq 0 ]

  rm -f "$HOME/.claude/commands"/*.md
  rm -f "$HOME/.claude/hooks"/*.sh

  sleep 2
  bash "$REPO_ROOT/install.sh" --non-interactive --language en --clients claude-code >/dev/null

  after="$(count_backups)"
  [ "$after" -eq 0 ]

  [ -f "$HOME/.claude/commands/mb.md" ]
  [ -f "$HOME/.claude/hooks/session-end-autosave.sh" ]
}

# ═══════════════════════════════════════════════════════════════
# Scenario 4 — language swap → only localize-target files backed up
# ═══════════════════════════════════════════════════════════════

@test "idempotent: language swap en->ru backs up RULES.md but not commands/agents/hooks" {
  bash "$REPO_ROOT/install.sh" --non-interactive --language en --clients claude-code,cursor >/dev/null
  [ "$(count_backups)" -eq 0 ]

  sleep 2
  bash "$REPO_ROOT/install.sh" --non-interactive --language ru --clients claude-code,cursor >/dev/null

  rules_backups=$(find "$HOME/.claude" -name "RULES.md.pre-mb-backup.*" | wc -l | tr -d ' ')
  cursor_user_rules_backups=$(find "$HOME/.cursor" -name "memory-bank-user-rules.md.pre-mb-backup.*" | wc -l | tr -d ' ')
  commands_backups=$(find "$HOME/.claude/commands" "$HOME/.cursor/commands" -name "*.pre-mb-backup.*" 2>/dev/null | wc -l | tr -d ' ')
  hooks_backups=$(find "$HOME/.claude/hooks" "$HOME/.cursor/hooks" -name "*.pre-mb-backup.*" 2>/dev/null | wc -l | tr -d ' ')
  agents_backups=$(find "$HOME/.claude/agents" -name "*.pre-mb-backup.*" 2>/dev/null | wc -l | tr -d ' ')

  # localize-target files: RULES.md + cursor user rules paste-file got backed up (language changed their content)
  [ "$rules_backups" -ge 1 ]
  [ "$cursor_user_rules_backups" -ge 1 ]

  # non-localize files: identical content → zero backups
  [ "$commands_backups" -eq 0 ]
  [ "$hooks_backups" -eq 0 ]
  [ "$agents_backups" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Scenario 5 — manifest backups[] filters stale paths
# ═══════════════════════════════════════════════════════════════

@test "idempotent: manifest backups[] contains only existing paths" {
  bash "$REPO_ROOT/install.sh" --non-interactive --language en --clients claude-code >/dev/null
  # Force one real backup via mutated target.
  echo "# force-diff" >> "$HOME/.claude/commands/mb.md"
  sleep 2
  bash "$REPO_ROOT/install.sh" --non-interactive --language en --clients claude-code >/dev/null

  manifest="$REPO_ROOT/.installed-manifest.json"
  [ -f "$manifest" ]

  # Count backups recorded in manifest before external delete
  len_before=$(jq '.backups | length' "$manifest")
  [ "$len_before" -ge 1 ]

  # Delete one backup file from disk (simulates user cleanup)
  backup_path=$(jq -r '.backups[0] | split("|")[1]' "$manifest")
  [ -f "$backup_path" ] && rm -f "$backup_path"

  # Reinstall — manifest should no longer list the deleted backup
  sleep 2
  bash "$REPO_ROOT/install.sh" --non-interactive --language en --clients claude-code >/dev/null

  listed_backups=$(jq -r '.backups[] | split("|")[1]' "$manifest")
  while IFS= read -r bp; do
    [ -z "$bp" ] && continue
    [ -e "$bp" ] || {
      echo "manifest references missing backup: $bp" >&2
      false
    }
  done <<< "$listed_backups"
}
