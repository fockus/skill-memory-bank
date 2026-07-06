#!/usr/bin/env bats
# Security: hooks/_skill_root.sh must not assemble bash -c strings from untrusted paths.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME:-$(dirname "$BATS_TEST_FILENAME")}/../.." && pwd)"
  cd "$REPO_ROOT"
  HOOKS_DIR="$REPO_ROOT/hooks"
  SCRIPTS_DIR="$REPO_ROOT/scripts"
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX/home"
  mkdir -p "$HOME/.claude/memory-bank/projects"
}

teardown() {
  [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ] && rm -rf "$SANDBOX"
}

@test "skill_root: path with single quote does not execute injected shell" {
  evil_dir="${SANDBOX}/evil'\$(touch "${SANDBOX}/PWNED")'dir"
  mkdir -p "$evil_dir"
  registry="$HOME/.claude/memory-bank/registry.json"
  mkdir -p "$(dirname "$registry")"
  printf '{"projects":{}}\n' > "$registry"
  run env MB_PROJECT_ROOT="$evil_dir" MB_AGENT=claude-code bash -c '
    . "'"$HOOKS_DIR"'/_skill_root.sh"
    mb_hook_resolve_mb_path "'"$SANDBOX"'/nowhere" || true
  '
  [ ! -f "$SANDBOX/PWNED" ]
}

@test "skill_root: registry lookup still works without bash -c injection path" {
  project="$SANDBOX/myproj"
  bank="$SANDBOX/global-bank"
  mkdir -p "$project" "$bank"
  # Registry keys use mb_resolve_real_path (must match mb_registry_lookup).
  run bash -c '
    # shellcheck source=scripts/_lib.sh
    . "'"$SCRIPTS_DIR"'/_lib.sh"
    mb_resolve_real_path "'"$project"'"
  '
  [ "$status" -eq 0 ]
  real_project="$output"
  registry="$HOME/.claude/memory-bank/registry.json"
  mkdir -p "$(dirname "$registry")"
  python3 - "$registry" "$real_project" "$bank" <<'PY'
import json, sys
path, proj, bank = sys.argv[1:4]
with open(path, "w") as fh:
    json.dump({"projects": {proj: {"bank_path": bank}}}, fh)
PY
  run env MB_PROJECT_ROOT="$project" MB_AGENT=claude-code bash -c '
    . "'"$HOOKS_DIR"'/_skill_root.sh"
    mb_hook_resolve_mb_path "'"$project"'"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "$bank" ]
}
