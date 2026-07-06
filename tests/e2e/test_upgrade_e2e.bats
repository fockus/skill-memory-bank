#!/usr/bin/env bats
# End-to-end test: full vN → vN+1 upgrade cycle via install.sh, run twice
# against a real (writable, isolated) skill-source copy whose VERSION we bump
# between runs — exercises A6 (true-original backup survives rotation), A7
# (manifest incremental/atomic), and A13 (paired-marker refresh + versioned
# AGENTS.md markers) as ONE coherent upgrade narrative rather than the
# per-mechanism unit tests already covering each individually.
#
# Never mutates the real repo: install.sh always runs from a writable rsync
# copy (SKILL_COPY) so bumping VERSION between "vN" and "vN+1" never touches
# the actual checked-out VERSION file other sessions/tests rely on.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX_HOME="$(mktemp -d)"
  export HOME="$SANDBOX_HOME"
  PROJECT="$(mktemp -d)"

  command -v python3 >/dev/null || skip "python3 not installed"
  command -v jq >/dev/null || skip "jq not installed"
  command -v rsync >/dev/null || skip "rsync required"

  SKILL_COPY_PARENT="$(mktemp -d)"
  SKILL_COPY="$SKILL_COPY_PARENT/skill"
  mkdir -p "$SKILL_COPY"
  rsync -a \
    --exclude='.git' \
    --exclude='*.pre-mb-backup.*' \
    --exclude='.index' \
    --exclude='node_modules' \
    --exclude='.installed-manifest.json' \
    "$REPO_ROOT/" "$SKILL_COPY/"
}

teardown() {
  { [ -n "${SANDBOX_HOME:-}" ] && [ -d "$SANDBOX_HOME" ] && rm -rf "$SANDBOX_HOME"; } || true
  { [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"; } || true
  { [ -n "${SKILL_COPY_PARENT:-}" ] && [ -d "$SKILL_COPY_PARENT" ] && rm -rf "$SKILL_COPY_PARENT"; } || true
}

_seed_user_content() {
  mkdir -p "$HOME/.claude" "$PROJECT/.codex"

  # 1. Plain user CLAUDE.md — no MB markers yet (pure pre-existing user file).
  cat > "$HOME/.claude/CLAUDE.md" <<'EOF'
# My Own Notes

USER_TAIL_MUST_SURVIVE_V1
EOF

  # 2. Foreign key in a project config.toml the Codex adapter merges into.
  printf 'user_key = "keep"\n' > "$PROJECT/.codex/config.toml"

  # 3. A pre-existing user hook in Claude Code's settings.json.
  cat > "$HOME/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Edit", "hooks": [{"type": "command", "command": "echo user-edit-hook"}]}
    ]
  }
}
EOF
}

@test "upgrade e2e: vN install preserves seeded user content and stamps the manifest/markers with vN" {
  _seed_user_content
  echo "9.9.0" > "$SKILL_COPY/VERSION"

  run bash "$SKILL_COPY/install.sh" --non-interactive --clients claude-code,codex --project-root "$PROJECT"
  [ "$status" -eq 0 ]

  # User content survived the first install.
  grep -q "USER_TAIL_MUST_SURVIVE_V1" "$HOME/.claude/CLAUDE.md"
  grep -q 'user_key = "keep"' "$PROJECT/.codex/config.toml"
  grep -q "user-edit-hook" "$HOME/.claude/settings.json"

  # Top-level manifest is present and valid (rollback source for uninstall).
  manifest="$SKILL_COPY/.installed-manifest.json"
  [ -f "$manifest" ]
  [ "$(jq -r '.schema_version' "$manifest")" = "1" ]
  [ "$(jq -r '.files | length' "$manifest")" -ge 1 ]

  # Codex adapter's own per-project manifest is stamped with vN.
  codex_manifest="$PROJECT/.codex/.mb-manifest.json"
  [ -f "$codex_manifest" ]
  [ "$(jq -r '.skill_version' "$codex_manifest")" = "9.9.0" ]

  # Project AGENTS.md (shared codex/opencode/pi format) carries the vN marker.
  grep -q "memory-bank-skill-version: 9.9.0" "$PROJECT/AGENTS.md"

  # The TRUE original backup of CLAUDE.md (pure pre-install user content)
  # exists — install.sh captures it before writing the merged MB block.
  found=0
  for b in "$HOME/.claude/CLAUDE.md.pre-mb-backup."*; do
    [ -f "$b" ] && grep -q "USER_TAIL_MUST_SURVIVE_V1" "$b" && found=1
  done
  [ "$found" -eq 1 ]
}

@test "upgrade e2e: vN -> vN+1 preserves the TRUE original backup, user edits, and re-stamps markers" {
  _seed_user_content
  echo "9.9.0" > "$SKILL_COPY/VERSION"
  bash "$SKILL_COPY/install.sh" --non-interactive --clients claude-code,codex --project-root "$PROJECT" >/dev/null

  # Locate & remember the true-original backup created at vN — it must
  # survive the vN+1 rotation untouched.
  true_original_backup=""
  for b in "$HOME/.claude/CLAUDE.md.pre-mb-backup."*; do
    if [ -f "$b" ] && grep -q "USER_TAIL_MUST_SURVIVE_V1" "$b"; then
      true_original_backup="$b"
      break
    fi
  done
  [ -n "$true_original_backup" ]

  # Simulate the user adding more content to the live (already-merged) file
  # between installs — must survive as "content after the MB section".
  printf '\nUSER_ADDED_AFTER_V1_INSTALL\n' >> "$HOME/.claude/CLAUDE.md"

  sleep 1  # ensure a distinguishable backup timestamp for the rotation event

  # Bump to vN+1 and reinstall (the "upgrade").
  echo "9.9.1" > "$SKILL_COPY/VERSION"
  run bash "$SKILL_COPY/install.sh" --non-interactive --clients claude-code,codex --project-root "$PROJECT"
  [ "$status" -eq 0 ]

  # The TRUE original backup from vN is still there, untouched by rotation.
  [ -f "$true_original_backup" ]
  grep -q "USER_TAIL_MUST_SURVIVE_V1" "$true_original_backup"

  # User content added between the two installs is preserved in the live file.
  grep -q "USER_ADDED_AFTER_V1_INSTALL" "$HOME/.claude/CLAUDE.md"
  grep -q "USER_TAIL_MUST_SURVIVE_V1" "$HOME/.claude/CLAUDE.md"

  # Foreign codex config.toml key + settings.json user hook still intact.
  grep -q 'user_key = "keep"' "$PROJECT/.codex/config.toml"
  grep -q "user-edit-hook" "$HOME/.claude/settings.json"

  # Codex adapter manifest + AGENTS.md marker now reflect vN+1.
  manifest="$SKILL_COPY/.installed-manifest.json"
  codex_manifest="$PROJECT/.codex/.mb-manifest.json"
  [ "$(jq -r '.skill_version' "$codex_manifest")" = "9.9.1" ]
  grep -q "memory-bank-skill-version: 9.9.1" "$PROJECT/AGENTS.md"
  ! grep -q "memory-bank-skill-version: 9.9.0" "$PROJECT/AGENTS.md"

  # Manifest stays valid JSON with a non-empty files[] throughout.
  python3 -c "
import json
m = json.load(open('$manifest'))
assert isinstance(m.get('files'), list) and len(m['files']) >= 1, 'manifest files[] empty/missing'
"
}

@test "upgrade e2e: a no-op reinstall at the same version is idempotent (zero new backups)" {
  _seed_user_content
  echo "9.9.0" > "$SKILL_COPY/VERSION"
  bash "$SKILL_COPY/install.sh" --non-interactive --clients claude-code,codex --project-root "$PROJECT" >/dev/null

  before=$(find "$HOME/.claude" "$PROJECT" -name '*.pre-mb-backup.*' 2>/dev/null | wc -l | tr -d ' ')

  sleep 1
  run bash "$SKILL_COPY/install.sh" --non-interactive --clients claude-code,codex --project-root "$PROJECT"
  [ "$status" -eq 0 ]

  after=$(find "$HOME/.claude" "$PROJECT" -name '*.pre-mb-backup.*' 2>/dev/null | wc -l | tr -d ' ')
  [ "$after" -eq "$before" ]

  # Still intact after the no-op reinstall.
  grep -q "USER_TAIL_MUST_SURVIVE_V1" "$HOME/.claude/CLAUDE.md"
  grep -q 'user_key = "keep"' "$PROJECT/.codex/config.toml"
}
