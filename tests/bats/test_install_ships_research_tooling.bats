#!/usr/bin/env bats
# Regression guard: install.sh ships the mb-research + mb-tooling-core agents
# to every client through the symlinked canonical skill dir.
#
# Contract (install.sh):
#   - install_symlink "$SOURCE_SKILL_DIR" "$CANONICAL_SKILL_DIR"  (~/.claude/skills/skill-memory-bank)
#   - install_symlink "$CANONICAL_SKILL_DIR" → Claude/Codex/Cursor/Pi aliases
#   => every alias resolves agents/*.md via the symlink chain, no per-file copy.
#   - AGENT_COUNT = count_matching_files agents '*.md' (auto-includes new files).
#
# Isolation (LESSON L64): install.sh writes its manifest to
# "$SOURCE_SKILL_DIR/.installed-manifest.json". To keep the REPO's tracked
# manifest pristine, we install from a TMP copy of the repo (manifest lands in
# the copy) AND sandbox $HOME (all client aliases land in a tmp HOME). Nothing
# under the real repo or the real $HOME is mutated.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  command -v jq >/dev/null || skip "jq required"
  command -v rsync >/dev/null || skip "rsync required"

  # Sandboxed HOME — every client alias (Claude/Codex/Cursor/Pi) is derived
  # from $HOME inside install.sh, so this redirects ALL install side effects.
  FAKE_HOME="$(mktemp -d)"
  PROJECT="$(mktemp -d)"

  # TMP copy of the repo so the manifest writes into the copy, never the repo.
  SKILL_SRC="$(mktemp -d)/skill"
  mkdir -p "$SKILL_SRC"
  rsync -a \
    --exclude='.git' \
    --exclude='*.pre-mb-backup.*' \
    --exclude='.index' \
    --exclude='node_modules' \
    "$REPO_ROOT/" "$SKILL_SRC/"

  INSTALL="$SKILL_SRC/install.sh"
  CLAUDE_AGENTS="$FAKE_HOME/.claude/skills/memory-bank/agents"
  CODEX_AGENTS="$FAKE_HOME/.codex/skills/memory-bank/agents"
  PI_AGENTS="$FAKE_HOME/.pi/agent/skills/memory-bank/agents"
}

teardown() {
  [ -n "${FAKE_HOME:-}" ] && [ -d "$FAKE_HOME" ] && rm -rf "$FAKE_HOME"
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
  if [ -n "${SKILL_SRC:-}" ]; then
    rm -rf "$(dirname "$SKILL_SRC")"
  fi
}

# Run a fresh claude-code install against the sandboxed HOME + tmp project.
run_fresh_install() {
  local raw
  raw=$(HOME="$FAKE_HOME" MB_SKIP_DEPS_CHECK=1 \
        bash "$INSTALL" --clients claude-code --project-root "$PROJECT" --non-interactive \
        </dev/null 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

# ═══════════════════════════════════════════════════════════════
# Claude alias resolves both new agents
# ═══════════════════════════════════════════════════════════════

@test "install: Claude alias resolves mb-research.md AND mb-tooling-core.md" {
  run_fresh_install
  [ "$status" -eq 0 ]
  # Resolvable as real files (whether via symlink or copy) under the Claude alias.
  [ -f "$CLAUDE_AGENTS/mb-research.md" ]
  [ -f "$CLAUDE_AGENTS/mb-tooling-core.md" ]
}

# ═══════════════════════════════════════════════════════════════
# Codex + Pi aliases resolve through the same canonical dir
# ═══════════════════════════════════════════════════════════════

@test "install: Codex and Pi aliases also resolve both new agents (shared canonical dir)" {
  run_fresh_install
  [ "$status" -eq 0 ]
  [ -f "$CODEX_AGENTS/mb-research.md" ]
  [ -f "$CODEX_AGENTS/mb-tooling-core.md" ]
  [ -f "$PI_AGENTS/mb-research.md" ]
  [ -f "$PI_AGENTS/mb-tooling-core.md" ]
}

# ═══════════════════════════════════════════════════════════════
# AGENT_COUNT reflects the shipped agents (auto-counted, includes new files)
# ═══════════════════════════════════════════════════════════════

@test "install: reports an agent count that matches the resolved agents dir" {
  run_fresh_install
  [ "$status" -eq 0 ]
  # The reported "<N> agents (...)" line must equal the number of *.md files
  # actually resolvable under the installed Claude alias.
  local resolved_count
  resolved_count="$(find "$CLAUDE_AGENTS" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
  [ "$resolved_count" -ge 2 ]
  [[ "$output" == *"$resolved_count agents ("* ]]
  # Both new agents are part of that resolved set.
  [ -f "$CLAUDE_AGENTS/mb-research.md" ]
  [ -f "$CLAUDE_AGENTS/mb-tooling-core.md" ]
}

# ═══════════════════════════════════════════════════════════════
# L64 — the repo's tracked manifest is never touched by this test
# ═══════════════════════════════════════════════════════════════

@test "install: does NOT mutate the repo's .installed-manifest.json (L64)" {
  local repo_manifest="$REPO_ROOT/.installed-manifest.json"
  local before=""
  [ -f "$repo_manifest" ] && before="$(shasum "$repo_manifest" | awk '{print $1}')"

  run_fresh_install
  [ "$status" -eq 0 ]

  # The manifest lands in the TMP skill copy, proving the repo copy is bypassed.
  [ -f "$SKILL_SRC/.installed-manifest.json" ]

  local after=""
  [ -f "$repo_manifest" ] && after="$(shasum "$repo_manifest" | awk '{print $1}')"
  [ "$before" = "$after" ]
}
