#!/usr/bin/env bats
# Tests for scripts/_lib.sh — agent-agnostic storage resolver.
#
# Sprint 1 / Stage 1 RED phase: behaviour contract for new resolver helpers.
# These tests MUST fail until Stage 2 implements:
#   - mb_agent_config_dir <agent>
#   - mb_project_key <project_root>
#   - mb_project_id <project_root>
#   - mb_registry_path <agent>
#   - mb_registry_lookup <agent> <project_root>
#   - extended mb_resolve_path precedence: explicit > MB_PATH > local > registry > legacy > fallback
#
# Failure must be semantic ("command not found: mb_…" / wrong output) — not
# syntax errors or missing fixtures.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/scripts/_lib.sh"
  CONTEXT_SCRIPT="$REPO_ROOT/scripts/mb-context.sh"

  [ -f "$LIB" ] || {
    echo "scripts/_lib.sh missing — repo broken, not a TDD red signal" >&2
    return 1
  }

  # Sandbox HOME so the registry never touches the real one.
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX/home"
  mkdir -p "$HOME"

  # Project root lives outside HOME for realpath clarity.
  PROJECT="$SANDBOX/project"
  mkdir -p "$PROJECT"

  # shellcheck source=/dev/null
  source "$LIB"
}

teardown() {
  [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ] && rm -rf "$SANDBOX"
}

# Helper: write a JSON registry entry for <agent> mapping <project> to <bank>.
# Uses python3 stdlib only — no jq dependency. Mirrors the per-agent paths
# enumerated in mb_agent_config_dir (Sprint 1 architecture decision §3).
_write_registry() {
  local agent="$1" project="$2" bank="$3" registry
  case "$agent" in
    claude-code) registry="$HOME/.claude/memory-bank/registry.json" ;;
    cursor)      registry="$HOME/.cursor/memory-bank/registry.json" ;;
    codex)       registry="$HOME/.codex/memory-bank/registry.json" ;;
    opencode)    registry="$HOME/.config/opencode/memory-bank/registry.json" ;;
    pi)          registry="$HOME/.pi/agent/memory-bank/registry.json" ;;
    windsurf)    registry="$HOME/.windsurf/memory-bank/registry.json" ;;
    cline)       registry="$HOME/.cline/memory-bank/registry.json" ;;
    kilo)        registry="$HOME/.kilocode/memory-bank/registry.json" ;;
    *)           printf 'unknown agent: %s\n' "$agent" >&2; return 1 ;;
  esac
  mkdir -p "$(dirname "$registry")"
  python3 - "$registry" "$project" "$bank" <<'PY'
import json, os, sys
path, project, bank = sys.argv[1], sys.argv[2], sys.argv[3]
data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        data = {}
projects = data.setdefault("projects", {})
projects[os.path.realpath(project)] = {"bank_path": bank}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY
}

# ═══ mb_agent_config_dir ═══════════════════════════════════════════════════════

@test "agent config dir: claude-code → \$HOME/.claude" {
  run mb_agent_config_dir claude-code
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude" ]
}

@test "agent config dir: cursor → \$HOME/.cursor" {
  run mb_agent_config_dir cursor
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.cursor" ]
}

@test "agent config dir: codex → \$HOME/.codex" {
  run mb_agent_config_dir codex
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.codex" ]
}

@test "agent config dir: opencode → \$HOME/.config/opencode" {
  run mb_agent_config_dir opencode
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.config/opencode" ]
}

@test "agent config dir: pi → \$HOME/.pi/agent" {
  run mb_agent_config_dir pi
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.pi/agent" ]
}

@test "agent config dir: windsurf/cline/kilo cover remaining matrix" {
  run mb_agent_config_dir windsurf
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.windsurf" ]

  run mb_agent_config_dir cline
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.cline" ]

  run mb_agent_config_dir kilo
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.kilocode" ]
}

@test "agent config dir: unknown agent → non-zero exit" {
  run mb_agent_config_dir totally-not-an-agent
  [ "$status" -ne 0 ]
}

# ═══ mb_project_key ════════════════════════════════════════════════════════════

@test "project key: deterministic for the same realpath" {
  run mb_project_key "$PROJECT"
  [ "$status" -eq 0 ]
  local first="$output"

  run mb_project_key "$PROJECT"
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
}

@test "project key: includes realpath even when no git remote" {
  run mb_project_key "$PROJECT"
  [ "$status" -eq 0 ]
  # realpath should expand to absolute form; key must reference it
  local real
  real="$(cd "$PROJECT" && pwd -P)"
  [[ "$output" == *"$real"* ]]
}

@test "project key: incorporates git remote when present" {
  ( cd "$PROJECT"
    git init -q
    git remote add origin git@example.com:acme/widgets.git
  )
  run mb_project_key "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"acme/widgets"* || "$output" == *"example.com"* ]]
}

@test "project key: project path with spaces still resolves" {
  local spaced="$SANDBOX/with spaces/proj"
  mkdir -p "$spaced"
  run mb_project_key "$spaced"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

# ═══ mb_project_id ═════════════════════════════════════════════════════════════

@test "project id: slug-hash form matches [A-Za-z0-9_-]+ regex" {
  run mb_project_id "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[A-Za-z0-9_-]+$ ]]
}

@test "project id: appends 12-char sha256 suffix" {
  run mb_project_id "$PROJECT"
  [ "$status" -eq 0 ]
  # last 12 chars after the trailing dash must be lowercase hex
  [[ "$output" =~ -[0-9a-f]{12}$ ]]
}

@test "project id: is idempotent for the same project" {
  run mb_project_id "$PROJECT"
  [ "$status" -eq 0 ]
  local first="$output"
  run mb_project_id "$PROJECT"
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
}

@test "project id: different projects produce different ids" {
  local other="$SANDBOX/project2"
  mkdir -p "$other"
  run mb_project_id "$PROJECT"
  [ "$status" -eq 0 ]
  local a="$output"
  run mb_project_id "$other"
  [ "$status" -eq 0 ]
  [ "$output" != "$a" ]
}

@test "project id: basename with spaces is sanitized to slug" {
  local spaced="$SANDBOX/Spaced Project Name"
  mkdir -p "$spaced"
  run mb_project_id "$spaced"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[A-Za-z0-9_-]+$ ]]
  [[ "$output" != *" "* ]]
}

# ═══ mb_registry_path ══════════════════════════════════════════════════════════

@test "registry path: claude-code → \$HOME/.claude/memory-bank/registry.json" {
  run mb_registry_path claude-code
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude/memory-bank/registry.json" ]
}

@test "registry path: opencode honours \$HOME/.config/opencode" {
  run mb_registry_path opencode
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.config/opencode/memory-bank/registry.json" ]
}

@test "registry path: pi honours \$HOME/.pi/agent" {
  run mb_registry_path pi
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.pi/agent/memory-bank/registry.json" ]
}

# ═══ mb_registry_lookup ════════════════════════════════════════════════════════

@test "registry lookup: missing registry → empty output, non-zero status" {
  run mb_registry_lookup claude-code "$PROJECT"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "registry lookup: registered project → external bank path printed" {
  local bank="$HOME/.claude/memory-bank/projects/widgets-abc123/.memory-bank"
  _write_registry claude-code "$PROJECT" "$bank"
  run mb_registry_lookup claude-code "$PROJECT"
  [ "$status" -eq 0 ]
  [ "$output" = "$bank" ]
}

@test "registry lookup: unrelated project not registered → non-zero, empty" {
  _write_registry claude-code "$SANDBOX/other" "$HOME/somewhere/.memory-bank"
  run mb_registry_lookup claude-code "$PROJECT"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "registry lookup: invalid JSON registry fails closed (non-zero, no crash)" {
  mkdir -p "$HOME/.claude/memory-bank"
  printf '{not valid json' > "$HOME/.claude/memory-bank/registry.json"
  run mb_registry_lookup claude-code "$PROJECT"
  # Must NOT exit 0 with a fake path; either non-zero or empty output.
  [ "$status" -ne 0 ] || [ -z "$output" ]
}

@test "registry lookup: project path with spaces resolves correctly" {
  local spaced="$SANDBOX/with spaces/proj"
  mkdir -p "$spaced"
  local bank="$HOME/.claude/memory-bank/projects/proj-deadbeef/.memory-bank"
  _write_registry claude-code "$spaced" "$bank"
  run mb_registry_lookup claude-code "$spaced"
  [ "$status" -eq 0 ]
  [ "$output" = "$bank" ]
}

# ═══ mb_resolve_path — extended precedence ═════════════════════════════════════

@test "resolve: explicit arg wins over everything else" {
  cd "$PROJECT"
  mkdir -p .memory-bank
  _write_registry claude-code "$PROJECT" "$HOME/.claude/memory-bank/projects/x/.memory-bank"
  export MB_AGENT=claude-code
  export MB_PATH=/should/be/ignored
  run mb_resolve_path /explicit/wins
  [ "$status" -eq 0 ]
  [ "$output" = "/explicit/wins" ]
}

@test "resolve: MB_PATH env wins over local and registry" {
  cd "$PROJECT"
  mkdir -p .memory-bank
  _write_registry claude-code "$PROJECT" "$HOME/.claude/registry-bank/.memory-bank"
  export MB_AGENT=claude-code
  export MB_PATH=/from/env
  run mb_resolve_path
  [ "$status" -eq 0 ]
  [ "$output" = "/from/env" ]
}

@test "resolve: local <project>/.memory-bank/ wins over registry when both exist" {
  cd "$PROJECT"
  mkdir -p .memory-bank
  _write_registry claude-code "$PROJECT" "$HOME/.claude/registry-bank/.memory-bank"
  export MB_AGENT=claude-code
  unset MB_PATH
  run mb_resolve_path
  [ "$status" -eq 0 ]
  # Must end with .memory-bank and refer to project root (relative or absolute)
  [[ "$output" == ".memory-bank" || "$output" == "$PROJECT/.memory-bank" ]]
}

@test "resolve: global registry hit when no local .memory-bank" {
  cd "$PROJECT"
  local bank="$HOME/.claude/memory-bank/projects/widgets-cafef00d/.memory-bank"
  _write_registry claude-code "$PROJECT" "$bank"
  export MB_AGENT=claude-code
  unset MB_PATH
  run mb_resolve_path
  [ "$status" -eq 0 ]
  [ "$output" = "$bank" ]
}

@test "resolve: legacy .claude-workspace still resolves after registry miss" {
  cd "$PROJECT"
  printf 'storage: external\nproject_id: legacy-proj\n' > .claude-workspace
  export MB_AGENT=claude-code
  unset MB_PATH
  run mb_resolve_path
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude/workspaces/legacy-proj/.memory-bank" ]
}

@test "resolve: nothing configured → relative .memory-bank fallback" {
  cd "$PROJECT"
  unset MB_PATH
  unset MB_AGENT
  run mb_resolve_path
  [ "$status" -eq 0 ]
  [ "$output" = ".memory-bank" ]
}

@test "resolve: corrupt registry falls back to legacy/local, not to a fake path" {
  cd "$PROJECT"
  mkdir -p "$HOME/.claude/memory-bank"
  printf '{broken' > "$HOME/.claude/memory-bank/registry.json"
  export MB_AGENT=claude-code
  unset MB_PATH
  run mb_resolve_path
  [ "$status" -eq 0 ]
  # Must NOT produce a path under the broken registry; fallback is local .memory-bank
  [ "$output" = ".memory-bank" ]
}

# ═══ Integration: mb-context.sh consumes resolver for global mode ═════════════

@test "context integration: global registry maps current project to external bank" {
  [ -x "$CONTEXT_SCRIPT" ] || [ -f "$CONTEXT_SCRIPT" ] || {
    echo "scripts/mb-context.sh missing — repo broken" >&2
    return 1
  }

  local bank="$HOME/.claude/memory-bank/projects/widgets-abc/.memory-bank"
  mkdir -p "$bank"
  echo "# Status"  > "$bank/status.md"
  echo "# Roadmap" > "$bank/roadmap.md"
  echo "# check"   > "$bank/checklist.md"
  echo "# rsr"     > "$bank/research.md"

  _write_registry claude-code "$PROJECT" "$bank"

  cd "$PROJECT"
  export MB_AGENT=claude-code
  unset MB_PATH
  run bash "$CONTEXT_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[MEMORY BANK: ACTIVE]"* ]]
  [[ "$output" == *"status.md"* ]]
}
