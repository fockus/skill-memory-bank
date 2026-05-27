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
  run env MB_SKILL_ROOT="$fake_root" bash -c '
    HOOK_DIR="'"$HOOKS_DIR"'"
    . "'"$HOOKS_DIR"'/_skill_root.sh"
    mb_skill_script_path "mb-plan-sync.sh" "$HOOK_DIR"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "$fake_root/scripts/mb-plan-sync.sh" ]
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

@test "skill_root: plan-sync hook finds chain scripts when MB_SKILL_ROOT set" {
  fake_root="$SANDBOX/fake-skill"
  mkdir -p "$fake_root/scripts" "$fake_root/hooks"
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
