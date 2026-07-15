#!/usr/bin/env bats
# Tests for hooks/_skill_root.sh — skill bundle resolution from hook scripts.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME:-$(dirname "$BATS_TEST_FILENAME")}/../.." && pwd)"
  cd "$REPO_ROOT"
  SKILL_ROOT="$REPO_ROOT"
  HOOKS_DIR="$REPO_ROOT/hooks"
  SCRIPTS_DIR="$REPO_ROOT/scripts"
  SANDBOX="$(mktemp -d)"
}

teardown() {
  [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ] && rm -rf "$SANDBOX"
}

@test "skill_root: resolves scripts from repo hook dir via parent SKILL.md" {
  run bash -c '
    HOOK_DIR="'"$HOOKS_DIR"'"
    # shellcheck source=hooks/_skill_root.sh
    . "'"$HOOKS_DIR"'/_skill_root.sh"
    mb_skill_script_path "mb-plan-sync.sh" "$HOOK_DIR"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"/scripts/mb-plan-sync.sh" ]]
  [ -f "$output" ]
}

@test "skill_root: MB_SKILL_ROOT override wins over hook parent" {
  fake_root="$SANDBOX/fake-skill"
  mkdir -p "$fake_root/scripts" "$fake_root/hooks"
  echo "stub" > "$fake_root/scripts/mb-plan-sync.sh"
  # A real skill root always has a VERSION file (or SKILL.md) — the
  # candidate gate requires one, same as the hook-parent candidate below.
  printf '9.9.9\n' > "$fake_root/VERSION"
  run env MB_SKILL_ROOT="$fake_root" bash -c '
    HOOK_DIR="'"$HOOKS_DIR"'"
    . "'"$HOOKS_DIR"'/_skill_root.sh"
    mb_skill_script_path "mb-plan-sync.sh" "$HOOK_DIR"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "$fake_root/scripts/mb-plan-sync.sh" ]
}

@test "skill_root: MB_SKILL_ROOT without a bundle marker (SKILL.md/VERSION) is rejected, not blindly trusted (M3)" {
  fake_root="$SANDBOX/untrusted"
  mkdir -p "$fake_root/scripts"
  echo "stub" > "$fake_root/scripts/mb-plan-sync.sh"
  run env MB_SKILL_ROOT="$fake_root" bash -c '
    HOOK_DIR="'"$HOOKS_DIR"'"
    . "'"$HOOKS_DIR"'/_skill_root.sh"
    mb_skill_root_resolve "$HOOK_DIR"
  '
  [ "$status" -eq 0 ]
  [ "$output" != "$fake_root" ]
  [ "$output" = "$SKILL_ROOT" ]
}

@test "skill_root: mb_hook_resolve_mb_path finds local .memory-bank" {
  project="$SANDBOX/project"
  mkdir -p "$project/.memory-bank"
  run bash -c '
    . "'"$HOOKS_DIR"'/_skill_root.sh"
    mb_hook_resolve_mb_path "'"$project"'"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "$project/.memory-bank" ]
}

@test "skill_root: mb_hook_default_agent returns cursor when Cursor skill dir exists" {
  fake_home="$SANDBOX/home"
  mkdir -p "$fake_home/.cursor/skills/memory-bank"
  run env HOME="$fake_home" bash -c '
    . "'"$HOOKS_DIR"'/_skill_root.sh"
    mb_hook_default_agent
  '
  [ "$status" -eq 0 ]
  [ "$output" = "cursor" ]
}

# ═══════════════════════════════════════════════════════════════
# B6 (A-1): OpenCode skill-alias / MB_SKILLS_ROOT — /mb commands must resolve
# a skill root without depending on a Claude Code tree. Full-install sandbox
# (LESSON L64 pattern): tmp copy of the repo (manifest writes land in the
# copy) + sandboxed $HOME (all client dirs are HOME-derived in install.sh).
# ═══════════════════════════════════════════════════════════════

setup_skill_alias_sandbox() {
  command -v rsync >/dev/null || skip "rsync required"
  FAKE_HOME="$(mktemp -d)"
  INSTALL_PROJECT="$(mktemp -d)"
  SKILL_SRC="$(mktemp -d)/skill"
  mkdir -p "$SKILL_SRC"
  rsync -a \
    --exclude='.git' \
    --exclude='*.pre-mb-backup.*' \
    --exclude='.index' \
    --exclude='node_modules' \
    "$REPO_ROOT/" "$SKILL_SRC/"
}

teardown_skill_alias_sandbox() {
  [ -n "${FAKE_HOME:-}" ] && [ -d "$FAKE_HOME" ] && rm -rf "$FAKE_HOME"
  [ -n "${INSTALL_PROJECT:-}" ] && [ -d "$INSTALL_PROJECT" ] && rm -rf "$INSTALL_PROJECT"
  [ -n "${SKILL_SRC:-}" ] && rm -rf "$(dirname "$SKILL_SRC")"
}

@test "skill_root: install --clients opencode (no pre-existing Claude tree) creates OpenCode's own skill alias" {
  setup_skill_alias_sandbox
  local raw status_
  raw=$(HOME="$FAKE_HOME" MB_SKIP_DEPS_CHECK=1 \
        bash "$SKILL_SRC/install.sh" --clients opencode \
        --project-root "$INSTALL_PROJECT" --non-interactive \
        </dev/null 2>&1; printf '\n__EXIT__%s' "$?")
  status_="${raw##*__EXIT__}"
  [ "$status_" -eq 0 ]
  local alias="$FAKE_HOME/.config/opencode/skills/memory-bank"
  [ -e "$alias" ]
  [ -f "$alias/SKILL.md" ]
  teardown_skill_alias_sandbox
}

@test "skill_root: commands/mb.md resolves the skill root via MB_SKILLS_ROOT (overridable), not a bare hardcode" {
  local mb_md="$REPO_ROOT/commands/mb.md"
  [ -f "$mb_md" ] || skip "commands/mb.md missing"
  # The command doc must honour an MB_SKILLS_ROOT override with the historical
  # Claude alias as its default fallback (backward compatible).
  grep -qF '${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}' "$mb_md"
  # The `/mb help` self-read algorithm (SKILL_MD=...) is a resolution point too.
  grep -qE 'SKILL_MD="\$\{MB_SKILLS_ROOT:-\$HOME/\.claude/skills/memory-bank\}' "$mb_md"
}

@test "skill_root: install.sh does not regress the pre-existing Claude/Codex/Cursor/Pi aliases" {
  setup_skill_alias_sandbox
  HOME="$FAKE_HOME" MB_SKIP_DEPS_CHECK=1 \
    bash "$SKILL_SRC/install.sh" --clients opencode \
    --project-root "$INSTALL_PROJECT" --non-interactive \
    </dev/null >/dev/null 2>&1
  [ -f "$FAKE_HOME/.claude/skills/memory-bank/SKILL.md" ]
  [ -f "$FAKE_HOME/.codex/skills/memory-bank/SKILL.md" ]
  [ -f "$FAKE_HOME/.cursor/skills/memory-bank/SKILL.md" ]
  [ -f "$FAKE_HOME/.pi/agent/skills/memory-bank/SKILL.md" ]
  teardown_skill_alias_sandbox
}

@test "skill_root: plan-sync hook finds chain scripts when MB_SKILL_ROOT set" {
  fake_root="$SANDBOX/fake-skill"
  mkdir -p "$fake_root/scripts" "$fake_root/hooks"
  printf '9.9.9\n' > "$fake_root/VERSION"
  for s in mb-plan-sync.sh mb-roadmap-sync.sh mb-traceability-gen.sh; do
    echo "#!/usr/bin/env bash" > "$fake_root/scripts/$s"
    chmod +x "$fake_root/scripts/$s"
  done
  cp "$HOOKS_DIR/mb-plan-sync-post-write.sh" "$HOOKS_DIR/_skill_root.sh" "$fake_root/hooks/"
  chmod +x "$fake_root/hooks/mb-plan-sync-post-write.sh"
  plan="$SANDBOX/plans/demo.md"
  mkdir -p "$(dirname "$plan")"
  echo "# plan" > "$plan"
  payload=$(jq -n --arg p "$plan" '{tool_name:"Write", tool_input:{file_path:$p}}')
  run env MB_SKILL_ROOT="$fake_root" bash "$fake_root/hooks/mb-plan-sync-post-write.sh" <<< "$payload"
  [ "$status" -eq 0 ]
  grep -q "plan-sync" <<< "$output" || true
}
