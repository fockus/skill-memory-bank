#!/usr/bin/env bats
# Tests for scripts/mb-init-bank.sh — Sprint 1 / Stage 3 global-storage flags.
#
# Contract additions on top of test_mb_init_bank.bats:
#   --storage=local|global       (default: local)
#   --agent=<claude-code|cursor|codex|opencode|pi|windsurf|cline|kilo>
#                                (default: $MB_AGENT or claude-code)
#   --project-root=PATH          (default: $PWD)
#
#   Local mode unchanged. Global mode:
#     - bank lives under <agent_config>/memory-bank/projects/<project_id>/.memory-bank/
#     - registry entry written atomically to <agent_config>/memory-bank/registry.json
#     - NO <project>/.memory-bank/ created
#     - .mb-config holds: lang, storage_mode, project_root, project_id, agent
#     - refuses implicit migration when local bank already exists
#     - idempotent for repeated invocations on the same project

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  INIT="$REPO_ROOT/scripts/mb-init-bank.sh"
  LIB="$REPO_ROOT/scripts/_lib.sh"

  # Sandbox HOME and PROJECT under one tmp dir so the registry never touches
  # the real ~/.claude tree.
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX/home"
  mkdir -p "$HOME"
  PROJECT="$SANDBOX/project"
  mkdir -p "$PROJECT"

  unset MB_LANG MB_ROOT MB_AGENT MB_PATH
}

teardown() {
  unset MB_LANG MB_ROOT MB_AGENT MB_PATH
  [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ] && rm -rf "$SANDBOX"
}

# Resolve the global bank path the same way the implementation will, so the
# assertion stays in sync without copy-pasting the project_id derivation.
_expected_global_bank() {
  local agent="$1" project="$2" base id
  # shellcheck source=/dev/null
  source "$LIB"
  base=$(mb_agent_config_dir "$agent")
  id=$(mb_project_id "$project")
  printf '%s/memory-bank/projects/%s/.memory-bank\n' "$base" "$id"
}

# Resolve registry path through the lib so paths stay consistent.
_expected_registry() {
  local agent="$1"
  # shellcheck source=/dev/null
  source "$LIB"
  mb_registry_path "$agent"
}

# ═══ Local mode regression ════════════════════════════════════════════════════

@test "init storage: local remains default and creates project bank" {
  run bash "$INIT" --lang=en --mb-root="$PROJECT"
  [ "$status" -eq 0 ]
  [ -d "$PROJECT/.memory-bank" ]
  [ -f "$PROJECT/.memory-bank/.mb-config" ]
  grep -q '^storage_mode=local$' "$PROJECT/.memory-bank/.mb-config" \
    || grep -q '^lang=en$' "$PROJECT/.memory-bank/.mb-config"
}

@test "init storage: explicit --storage=local behaves like default" {
  run bash "$INIT" --storage=local --lang=en --mb-root="$PROJECT"
  [ "$status" -eq 0 ]
  [ -d "$PROJECT/.memory-bank" ]
}

# ═══ Global mode ══════════════════════════════════════════════════════════════

@test "init storage: --storage=global --agent=claude-code creates external bank" {
  run bash "$INIT" --storage=global --agent=claude-code --project-root="$PROJECT" --lang=en
  [ "$status" -eq 0 ]
  local expected
  expected=$(_expected_global_bank claude-code "$PROJECT")
  [ -d "$expected" ]
  [ -f "$expected/.mb-config" ]
}

@test "init storage: global mode does NOT create project .memory-bank" {
  bash "$INIT" --storage=global --agent=claude-code --project-root="$PROJECT" --lang=en
  [ ! -d "$PROJECT/.memory-bank" ]
}

@test "init storage: global mode writes a registry entry" {
  bash "$INIT" --storage=global --agent=claude-code --project-root="$PROJECT" --lang=en
  local registry
  registry=$(_expected_registry claude-code)
  [ -f "$registry" ]
  # python3 inspection: project realpath key present + bank_path non-empty
  python3 - "$registry" "$PROJECT" <<'PY'
import json, os, sys
reg, project = sys.argv[1], sys.argv[2]
data = json.load(open(reg))
projects = data.get("projects") or {}
key = os.path.realpath(project)
assert key in projects, f"missing project key {key} in {list(projects)}"
entry = projects[key]
bank = entry["bank_path"] if isinstance(entry, dict) else entry
assert bank and os.path.isdir(bank), f"bank path {bank!r} not a directory"
PY
}

@test "init storage: .mb-config carries storage/project/agent metadata in global mode" {
  bash "$INIT" --storage=global --agent=claude-code --project-root="$PROJECT" --lang=ru
  local bank
  bank=$(_expected_global_bank claude-code "$PROJECT")
  local cfg="$bank/.mb-config"
  [ -f "$cfg" ]
  grep -q '^lang=ru$' "$cfg"
  grep -q '^storage_mode=global$' "$cfg"
  grep -q '^agent=claude-code$' "$cfg"
  grep -q '^project_root=' "$cfg"
  grep -q '^project_id=' "$cfg"
}

@test "init storage: global mode works for non-default agent (pi)" {
  run bash "$INIT" --storage=global --agent=pi --project-root="$PROJECT" --lang=en
  [ "$status" -eq 0 ]
  local expected
  expected=$(_expected_global_bank pi "$PROJECT")
  [ -d "$expected" ]
  [ -f "$HOME/.pi/agent/memory-bank/registry.json" ]
}

# ═══ Safety ═══════════════════════════════════════════════════════════════════

@test "init storage: existing local bank blocks global init without --force" {
  mkdir -p "$PROJECT/.memory-bank"
  echo "USER CONTENT" > "$PROJECT/.memory-bank/STATUS.md"

  run bash "$INIT" --storage=global --agent=claude-code --project-root="$PROJECT" --lang=en
  [ "$status" -ne 0 ]
  # Local bank must remain untouched
  grep -q "USER CONTENT" "$PROJECT/.memory-bank/STATUS.md"
  # Helpful guidance mentioning a migration path or --force
  [[ "$output" == *"migrate"* || "$output" == *"--force"* || "$output" == *"local"* ]]
}

@test "init storage: invalid agent exits 2 and lists supported agents" {
  run bash "$INIT" --storage=global --agent=not-a-real-agent --project-root="$PROJECT" --lang=en
  [ "$status" -eq 2 ]
  [[ "$output" == *"claude-code"* || "$output" == *"pi"* || "$output" == *"agent"* ]]
}

# ═══ Idempotency ══════════════════════════════════════════════════════════════

@test "init storage: second global init is idempotent (no duplicates, no error)" {
  bash "$INIT" --storage=global --agent=claude-code --project-root="$PROJECT" --lang=en
  run bash "$INIT" --storage=global --agent=claude-code --project-root="$PROJECT" --lang=en
  [ "$status" -eq 0 ]

  local registry
  registry=$(_expected_registry claude-code)
  # Registry must list this project exactly once
  python3 - "$registry" "$PROJECT" <<'PY'
import json, os, sys
data = json.load(open(sys.argv[1]))
projects = data.get("projects") or {}
key = os.path.realpath(sys.argv[2])
keys = [k for k in projects if k == key]
assert len(keys) == 1, f"expected 1 entry for {key}, got {len(keys)}: {projects}"
PY
}

# ═══ UX / help ════════════════════════════════════════════════════════════════

@test "init storage: --help documents both storage modes with examples" {
  run bash "$INIT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--storage"* ]]
  [[ "$output" == *"local"* ]]
  [[ "$output" == *"global"* ]]
  [[ "$output" == *"--agent"* ]]
}

# ═══ MB_AGENT env auto-detect ════════════════════════════════════════════════

@test "init storage: MB_AGENT env supplies default agent when --agent omitted" {
  MB_AGENT=cursor run bash "$INIT" --storage=global --project-root="$PROJECT" --lang=en
  [ "$status" -eq 0 ]
  local expected
  expected=$(_expected_global_bank cursor "$PROJECT")
  [ -d "$expected" ]
}
