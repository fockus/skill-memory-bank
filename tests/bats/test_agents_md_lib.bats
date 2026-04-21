#!/usr/bin/env bats

# Direct tests for adapters/_lib_agents_md.sh shared ownership logic.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/adapters/_lib_agents_md.sh"
  PROJECT="$(mktemp -d)"
  SKILL_DIR="$(mktemp -d)"
  mkdir -p "$SKILL_DIR/rules"
  cat > "$SKILL_DIR/rules/RULES.md" <<'EOF'
# Global Rules

1. **Language**: English — responses and code comments. Technical terms may remain in English.
EOF
  command -v jq >/dev/null || skip "jq required"
  # shellcheck source=/dev/null
  source "$LIB"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
  [ -n "${SKILL_DIR:-}" ] && [ -d "$SKILL_DIR" ] && rm -rf "$SKILL_DIR"
}

@test "agents-md: first install creates AGENTS.md and owners file" {
  run agents_md_install "$PROJECT" "codex" "$SKILL_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  [ -f "$PROJECT/AGENTS.md" ]
  [ -f "$PROJECT/.mb-agents-owners.json" ]
  jq -e '.owners == ["codex"]' "$PROJECT/.mb-agents-owners.json" >/dev/null
}

@test "agents-md: second owner reuses one shared section and updates refcount" {
  agents_md_install "$PROJECT" "codex" "$SKILL_DIR" >/dev/null
  run agents_md_install "$PROJECT" "opencode" "$SKILL_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
  [ "$(grep -c 'memory-bank:start' "$PROJECT/AGENTS.md")" -eq 1 ]
  jq -e '.owners | contains(["codex","opencode"])' "$PROJECT/.mb-agents-owners.json" >/dev/null
}

@test "agents-md: uninstall decrements owners then removes section on last owner" {
  agents_md_install "$PROJECT" "codex" "$SKILL_DIR" >/dev/null
  agents_md_install "$PROJECT" "opencode" "$SKILL_DIR" >/dev/null

  run agents_md_uninstall "$PROJECT" "codex"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/AGENTS.md" ]
  jq -e '.owners == ["opencode"]' "$PROJECT/.mb-agents-owners.json" >/dev/null

  run agents_md_uninstall "$PROJECT" "opencode"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/AGENTS.md" ]
  [ ! -f "$PROJECT/.mb-agents-owners.json" ]
}

@test "agents-md: owners file write leaves valid json and no temp leftovers" {
  _owners_write "$PROJECT" '{"owners":["cursor"],"initial_had_user_content":false}'
  jq -e '.owners == ["cursor"]' "$PROJECT/.mb-agents-owners.json" >/dev/null
  local tmp_count
  tmp_count=$(find "$PROJECT" -maxdepth 1 -name '.mb-agents-owners.json.*.tmp' | wc -l | tr -d ' ')
  [ "$tmp_count" -eq 0 ]
}

@test "agents-md: uninstall preserves user content when MB section was appended" {
  cat > "$PROJECT/AGENTS.md" <<'EOF'
# User content

Keep me.
EOF

  agents_md_install "$PROJECT" "pi" "$SKILL_DIR" >/dev/null
  run agents_md_uninstall "$PROJECT" "pi"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q '^# User content$' "$PROJECT/AGENTS.md"
  ! grep -q 'memory-bank:start' "$PROJECT/AGENTS.md"
}
