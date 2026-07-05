#!/usr/bin/env bats
# A13 (M-5): install.sh's ~/.claude/CLAUDE.md MB-section refresh must not
# silently destroy user content placed AFTER the section, and must back up
# the file before rewriting it. Exercises the exact code path install.sh runs
# for CLAUDE.md (Step 1), against a sandboxed $HOME — never the real one.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX_HOME="$(mktemp -d)"
  export HOME="$SANDBOX_HOME"
  export MB_SKIP_DEPS_CHECK=1
  command -v python3 >/dev/null || skip "python3 required"
}

teardown() {
  [ -n "${SANDBOX_HOME:-}" ] && [ -d "$SANDBOX_HOME" ] && rm -rf "$SANDBOX_HOME"
}

@test "install: CLAUDE.md refresh preserves user content after the MB section + backs it up (A13)" {
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/CLAUDE.md" <<'EOF'
# [MEMORY-BANK-SKILL]

OLD MB CONTENT (from a previous install)
<!-- /memory-bank-skill -->

# My Own Notes

USER_TAIL_MUST_SURVIVE
EOF

  bash "$REPO_ROOT/install.sh" --non-interactive >/dev/null

  # User content below the paired end marker must still be there.
  grep -q "USER_TAIL_MUST_SURVIVE" "$HOME/.claude/CLAUDE.md"
  grep -q "# My Own Notes" "$HOME/.claude/CLAUDE.md"
  # The MB section was actually refreshed (old placeholder content is gone).
  ! grep -q "OLD MB CONTENT" "$HOME/.claude/CLAUDE.md"
  # A backup of the pre-refresh file was taken.
  local found=0
  for b in "$HOME/.claude/CLAUDE.md.pre-mb-backup."*; do
    [ -f "$b" ] && grep -q "USER_TAIL_MUST_SURVIVE" "$b" && found=1
  done
  [ "$found" -eq 1 ]
}

@test "install: CLAUDE.md refresh replaces strictly between paired markers (A13)" {
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/CLAUDE.md" <<'EOF'
# Before

BEFORE_MARKER_CONTENT

# [MEMORY-BANK-SKILL]

stale body
<!-- /memory-bank-skill -->

# After

AFTER_MARKER_CONTENT
EOF

  bash "$REPO_ROOT/install.sh" --non-interactive >/dev/null

  grep -q "BEFORE_MARKER_CONTENT" "$HOME/.claude/CLAUDE.md"
  grep -q "AFTER_MARKER_CONTENT" "$HOME/.claude/CLAUDE.md"
  ! grep -q "stale body" "$HOME/.claude/CLAUDE.md"
  # Order preserved: BEFORE comes before the MB section, AFTER comes after it.
  python3 - <<PY
text = open("$HOME/.claude/CLAUDE.md").read()
i_before = text.index("BEFORE_MARKER_CONTENT")
i_mb = text.index("[MEMORY-BANK-SKILL]")
i_after = text.index("AFTER_MARKER_CONTENT")
assert i_before < i_mb < i_after, (i_before, i_mb, i_after)
PY
}

@test "install: CLAUDE.md legacy unclosed marker (pre-A13) is not eaten to EOF — safe append (A13 edge case)" {
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/CLAUDE.md" <<'EOF'
# [MEMORY-BANK-SKILL]

legacy content with no end marker
LEGACY_TAIL_NOT_DESTROYED
EOF

  bash "$REPO_ROOT/install.sh" --non-interactive >/dev/null

  # A fresh, properly paired MB block now exists.
  grep -q "<!-- /memory-bank-skill -->" "$HOME/.claude/CLAUDE.md"
  # Must not silently vanish with no way back (the old destructive
  # "marker..EOF, no backup" behavior) — it is captured in a backup, same
  # contract as the "no marker yet" merge case.
  local found=0
  for b in "$HOME/.claude/CLAUDE.md.pre-mb-backup."*; do
    [ -f "$b" ] && grep -q "LEGACY_TAIL_NOT_DESTROYED" "$b" && found=1
  done
  [ "$found" -eq 1 ]
}

@test "install: CLAUDE.md without any MB marker gets a fresh paired block appended (A13 control)" {
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/CLAUDE.md" <<'EOF'
# User's own preferences

Important project rules
EOF

  bash "$REPO_ROOT/install.sh" --non-interactive >/dev/null

  # New paired MB block present in the live file...
  grep -q "# \[MEMORY-BANK-SKILL\]" "$HOME/.claude/CLAUDE.md"
  grep -q "<!-- /memory-bank-skill -->" "$HOME/.claude/CLAUDE.md"
  # ...and the pre-existing content is not lost — it is captured in a backup
  # (existing install.sh contract: backup_if_exists + uninstall.sh restores
  # it verbatim; see "uninstall: preserves user CLAUDE.md content above skill
  # section" in test_install_uninstall.bats). This test only guards the new
  # end-marker addition, not that merge-branch contract.
  local found=0
  for b in "$HOME/.claude/CLAUDE.md.pre-mb-backup."*; do
    [ -f "$b" ] && grep -q "User's own preferences" "$b" && found=1
  done
  [ "$found" -eq 1 ]
}

@test "install: two consecutive installs do not duplicate the CLAUDE.md end marker (A13 idempotency)" {
  bash "$REPO_ROOT/install.sh" --non-interactive >/dev/null
  bash "$REPO_ROOT/install.sh" --non-interactive >/dev/null

  local count
  count=$(grep -c "<!-- /memory-bank-skill -->" "$HOME/.claude/CLAUDE.md")
  [ "$count" -eq 1 ]
}

@test "uninstall: strips CLAUDE.md strictly between paired markers, keeps the tail (A13)" {
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/CLAUDE.md" <<'EOF'
# [MEMORY-BANK-SKILL]

OLD MB CONTENT (from a previous install)
<!-- /memory-bank-skill -->

# My Own Notes

USER_TAIL_MUST_SURVIVE
EOF

  bash "$REPO_ROOT/install.sh" --non-interactive >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ -f "$HOME/.claude/CLAUDE.md" ]
  grep -q "USER_TAIL_MUST_SURVIVE" "$HOME/.claude/CLAUDE.md"
  ! grep -q "\[MEMORY-BANK-SKILL\]" "$HOME/.claude/CLAUDE.md"
}
