#!/usr/bin/env bats
# End-to-end tests for install.sh --clients flag (cross-agent integration).
#
# Verifies:
#   - install.sh without --clients → default claude-code only (backward compat)
#   - install.sh --clients <list> → invokes adapters for each in addition to global
#   - --clients validation rejects unknown client names
#   - --project-root targets adapter file placement
#   - --help works and exits 0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX_HOME="$(mktemp -d)"
  PROJECT="$(mktemp -d)"
  (cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t)
  export HOME="$SANDBOX_HOME"
  export MB_SKIP_DEPS_CHECK=1
  command -v python3 >/dev/null || skip "python3 required"
  command -v jq >/dev/null || skip "jq required"
}

teardown() {
  [ -n "${SANDBOX_HOME:-}" ] && [ -d "$SANDBOX_HOME" ] && rm -rf "$SANDBOX_HOME"
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

@test "install.sh --help prints usage and exits 0" {
  run bash "$REPO_ROOT/install.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--clients"* ]]
}

@test "install.sh without --clients → global install only (backward compat)" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  [ -f "$HOME/.claude/RULES.md" ]
  [ ! -d "$PROJECT/.cursor" ]
  [ ! -d "$PROJECT/.windsurf" ]
}

@test "install.sh merges Pi global AGENTS.md with mandatory mb-work gate" {
  mkdir -p "$HOME/.pi/agent"
  cat > "$HOME/.pi/agent/AGENTS.md" <<'EOF'
# User Pi Rules

Keep my custom instructions.
EOF

  bash "$REPO_ROOT/install.sh" --non-interactive >/dev/null
  bash "$REPO_ROOT/install.sh" --non-interactive >/dev/null

  [ -f "$HOME/.pi/agent/AGENTS.md" ]
  grep -q '^# User Pi Rules$' "$HOME/.pi/agent/AGENTS.md"
  grep -q 'Mandatory `/mb work` execution gate' "$HOME/.pi/agent/AGENTS.md"
  grep -q 'mb-workflow.sh' "$HOME/.pi/agent/AGENTS.md"
  grep -q 'mb-work-plan.sh' "$HOME/.pi/agent/AGENTS.md"
  local count
  count=$(grep -c 'memory-bank-pi:start' "$HOME/.pi/agent/AGENTS.md")
  [ "$count" -eq 1 ]
}

@test "install.sh merges Pi settings.json skills without overwriting user settings" {
  mkdir -p "$HOME/.pi/agent"
  cat > "$HOME/.pi/agent/settings.json" <<'EOF'
{
  "defaultProvider": "custom-provider",
  "theme": "dark",
  "skills": [
    "~/.pi/agent/skills/custom-skill"
  ],
  "packages": ["npm:example"]
}
EOF

  bash "$REPO_ROOT/install.sh" --non-interactive >/dev/null
  bash "$REPO_ROOT/install.sh" --non-interactive >/dev/null

  python3 -m json.tool "$HOME/.pi/agent/settings.json" >/dev/null
  jq -e '.defaultProvider == "custom-provider"' "$HOME/.pi/agent/settings.json" >/dev/null
  jq -e '.theme == "dark"' "$HOME/.pi/agent/settings.json" >/dev/null
  jq -e '.packages == ["npm:example"]' "$HOME/.pi/agent/settings.json" >/dev/null
  jq -e '.skills | index("~/.pi/agent/skills/custom-skill") != null' "$HOME/.pi/agent/settings.json" >/dev/null
  jq -e '.skills[0] == "~/.pi/agent/skills/memory-bank"' "$HOME/.pi/agent/settings.json" >/dev/null
  jq -e '[.skills[] | select(. == "~/.pi/agent/skills/memory-bank")] | length == 1' "$HOME/.pi/agent/settings.json" >/dev/null
}

@test "install.sh --clients cursor installs Cursor adapter into project" {
  bash "$REPO_ROOT/install.sh" --clients cursor --project-root "$PROJECT" >/dev/null
  [ -f "$HOME/.claude/RULES.md" ]
  [ -f "$PROJECT/.cursor/rules/memory-bank.mdc" ]
  [ -f "$PROJECT/.cursor/hooks.json" ]
  [ -f "$PROJECT/.cursor/.mb-manifest.json" ]
}

@test "install.sh --clients claude-code,cursor,kilo installs both adapters" {
  bash "$REPO_ROOT/install.sh" --clients claude-code,cursor,kilo --project-root "$PROJECT" >/dev/null
  [ -f "$HOME/.claude/RULES.md" ]
  [ -f "$PROJECT/.cursor/rules/memory-bank.mdc" ]
  [ -f "$PROJECT/.kilocode/rules/memory-bank.md" ]
  [ -x "$PROJECT/.git/hooks/post-commit" ]
}

@test "install.sh --clients opencode,codex coexist via shared AGENTS.md refcount" {
  bash "$REPO_ROOT/install.sh" --clients opencode,codex --project-root "$PROJECT" >/dev/null
  [ -f "$PROJECT/AGENTS.md" ]
  [ -f "$PROJECT/.opencode/commands/mb.md" ]
  local count
  count=$(grep -c "memory-bank:start" "$PROJECT/AGENTS.md")
  [ "$count" -eq 1 ]
  jq -e '.owners | contains(["opencode","codex"])' "$PROJECT/.mb-agents-owners.json" >/dev/null
}

@test "install.sh --language ru localizes project adapter rules" {
  bash "$REPO_ROOT/install.sh" --clients cursor,codex --language ru --project-root "$PROJECT" >/dev/null
  grep -q '1. \*\*Language\*\*: Russian — responses and code comments' "$PROJECT/AGENTS.md"
  grep -q '1. \*\*Language\*\*: Russian — responses and code comments' "$PROJECT/.cursor/rules/memory-bank.mdc"
}

@test "install.sh --clients invalidname → exit non-zero with validation error" {
  run bash "$REPO_ROOT/install.sh" --clients invalidname --project-root "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid client"* ]]
}

@test "install.sh --clients '' → exit non-zero (empty)" {
  run bash "$REPO_ROOT/install.sh" --clients "" --project-root "$PROJECT"
  [ "$status" -ne 0 ]
}

@test "install.sh --unknown-flag → exit non-zero with hint" {
  run bash "$REPO_ROOT/install.sh" --nonsense
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown argument"* ]] || [[ "$output" == *"--help"* ]]
}

@test "install.sh --clients windsurf creates Cascade hooks.json in project" {
  bash "$REPO_ROOT/install.sh" --clients windsurf --project-root "$PROJECT" >/dev/null
  [ -f "$PROJECT/.windsurf/rules/memory-bank.md" ]
  [ -f "$PROJECT/.windsurf/hooks.json" ]
  jq . "$PROJECT/.windsurf/hooks.json" >/dev/null
}

@test "install.sh --clients cline creates .clinerules with hooks" {
  bash "$REPO_ROOT/install.sh" --clients cline --project-root "$PROJECT" >/dev/null
  [ -f "$PROJECT/.clinerules/memory-bank.md" ]
  [ -x "$PROJECT/.clinerules/hooks/before-tool.sh" ]
}

# ═══════════════════════════════════════════════════════════════
# A17 (CDX-I3): adapter failure must fail top-level install
# ═══════════════════════════════════════════════════════════════
# These tests need a stub adapter that deterministically fails, so they run
# install.sh from a writable rsync copy of the repo with adapters/codex.sh
# swapped for a failing stub (never mutate the real repo's adapters/).

_a17_make_failing_adapter_skill_copy() {
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
  cat > "$SKILL_COPY/adapters/codex.sh" <<'EOF'
#!/usr/bin/env bash
echo "[stub codex adapter] simulated failure" >&2
exit 1
EOF
  chmod +x "$SKILL_COPY/adapters/codex.sh"
}

_a17_cleanup_skill_copy() {
  [ -n "${SKILL_COPY_PARENT:-}" ] && [ -d "$SKILL_COPY_PARENT" ] && rm -rf "$SKILL_COPY_PARENT"
}

@test "install.sh: a failing adapter makes top-level install exit nonzero (A17)" {
  _a17_make_failing_adapter_skill_copy

  run bash "$SKILL_COPY/install.sh" --clients codex --project-root "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"codex"* ]]

  _a17_cleanup_skill_copy
}

@test "install.sh: a healthy sibling adapter still installs despite another's failure (A17)" {
  _a17_make_failing_adapter_skill_copy

  run bash "$SKILL_COPY/install.sh" --clients codex,cursor --project-root "$PROJECT"
  [ "$status" -ne 0 ]
  # cursor (the healthy sibling) must still have been installed.
  [ -f "$PROJECT/.cursor/rules/memory-bank.mdc" ]

  _a17_cleanup_skill_copy
}

@test "install.sh: failed adapters are recorded in the manifest (adapters_failed) (A17)" {
  _a17_make_failing_adapter_skill_copy

  local manifest="$HOME/.mb-a17-manifest.json"
  run env MB_MANIFEST_PATH="$manifest" bash "$SKILL_COPY/install.sh" --clients codex --project-root "$PROJECT"
  [ "$status" -ne 0 ]
  [ -f "$manifest" ]
  python3 -c "
import json
m = json.load(open('$manifest'))
assert 'codex' in m.get('adapters_failed', []), m
"

  _a17_cleanup_skill_copy
}
