#!/usr/bin/env bash
# adapters/pi.sh — Pi Code (pi-mono) cross-agent adapter.
#
# Pi Skills API is in active development (2026-04-20 research). We ship two modes:
#
#   MB_PI_MODE=agents-md  (default)  — AGENTS.md (shared, refcount) +
#                                       git-hooks-fallback. Safe, stable today.
#   MB_PI_MODE=skill                 — Native ~/.pi/skills/memory-bank/ package.
#                                       Preferred when Pi Skills API stabilizes.
#
# Usage:
#   adapters/pi.sh install [PROJECT_ROOT]
#   adapters/pi.sh uninstall [PROJECT_ROOT]
#
# Switch: MB_PI_MODE=skill adapters/pi.sh install [PROJECT_ROOT]

set -euo pipefail

ACTION="${1:-}"
PROJECT_ROOT_RAW="${2:-$(pwd)}"

if [ ! -d "$PROJECT_ROOT_RAW" ]; then
  echo "[pi-adapter] project root not found: $PROJECT_ROOT_RAW" >&2
  exit 1
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT_RAW" && pwd)"

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ADAPTERS_DIR="$SKILL_DIR/adapters"
GIT_FALLBACK="$ADAPTERS_DIR/git-hooks-fallback.sh"
MANIFEST="$PROJECT_ROOT/.mb-pi-manifest.json"

MODE="${MB_PI_MODE:-agents-md}"

# shellcheck source=./_lib_agents_md.sh
. "$(dirname "$0")/_lib_agents_md.sh"

require_jq() { command -v jq >/dev/null 2>&1 || { echo "[pi-adapter] jq required" >&2; exit 1; }; }

# ═══ Skill mode (native ~/.pi/skills/memory-bank/) ═══
PI_SKILL_DIR="$HOME/.pi/skills/memory-bank"

install_skill_mode() {
  mkdir -p "$PI_SKILL_DIR"

  # SKILL.md manifest (best-guess Pi format based on research; will need refinement
  # once Pi Skills API stabilizes — see notes/2026-04-20_03-36_cross-agent-research.md)
  {
    echo '---'
    echo 'name: memory-bank'
    echo 'description: "Memory Bank — long-term project memory + dev toolkit"'
    echo 'version: '"$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)"
    echo '---'
    echo ''
    echo '# Memory Bank — Pi Skill'
    echo ''
    echo 'Long-term project memory via `.memory-bank/` + dev workflow rules.'
    echo ''
    echo '**Workflow:**'
    # shellcheck disable=SC2016
    echo '- Start of session: read `.memory-bank/STATUS.md`, `checklist.md`, `plan.md`, `RESEARCH.md`'
    # shellcheck disable=SC2016
    echo '- Update `checklist.md` immediately (⬜ → ✅) when tasks done'
    echo ''
    if [ -f "$SKILL_DIR/rules/RULES.md" ]; then
      echo '---'
      echo ''
      echo '# Global Rules'
      echo ''
      mb_emit_rules_file "$SKILL_DIR/rules/RULES.md"
    fi
  } > "$PI_SKILL_DIR/SKILL.md"

  local files_json
  files_json=$(jq -n --arg p "$PI_SKILL_DIR/SKILL.md" '[$p]')

  jq -n \
    --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg skill_version "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    --arg pi_skill_dir "$PI_SKILL_DIR" \
    --argjson files "$files_json" \
    '{installed_at: $installed_at, adapter: "pi", mode: "skill", skill_version: $skill_version, pi_skill_dir: $pi_skill_dir, files: $files}' \
    > "$MANIFEST"

  echo "[pi-adapter] installed (mode: skill, path: $PI_SKILL_DIR)"
}

uninstall_skill_mode() {
  local skill_path
  skill_path=$(jq -r '.pi_skill_dir' "$MANIFEST")
  [ -n "$skill_path" ] && [ -d "$skill_path" ] && rm -rf "$skill_path"
  rm -f "$MANIFEST"
  # Clean empty parent dirs
  rmdir "$HOME/.pi/skills" 2>/dev/null || true
  rmdir "$HOME/.pi" 2>/dev/null || true
}

# ═══ AGENTS.md mode (default, transitional) ═══
install_agents_md_mode() {
  if [ ! -d "$PROJECT_ROOT/.git" ]; then
    echo "[pi-adapter] agents-md mode requires git repo (git-hooks-fallback mandatory)" >&2
    exit 1
  fi

  local owned
  owned=$(agents_md_install "$PROJECT_ROOT" "pi" "$SKILL_DIR")
  bash "$GIT_FALLBACK" install "$PROJECT_ROOT" >/dev/null

  jq -n \
    --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg skill_version "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    --argjson agents_owned "$owned" \
    '{installed_at: $installed_at, adapter: "pi", mode: "agents-md", skill_version: $skill_version, agents_md_owned: $agents_owned, git_hooks_installed: true}' \
    > "$MANIFEST"

  echo "[pi-adapter] installed (mode: agents-md, transitional)"
}

uninstall_agents_md_mode() {
  local installed_git
  installed_git=$(jq -r '.git_hooks_installed // false' "$MANIFEST")

  agents_md_uninstall "$PROJECT_ROOT" "pi"

  if [ "$installed_git" = "true" ]; then
    bash "$GIT_FALLBACK" uninstall "$PROJECT_ROOT" >/dev/null
  fi

  rm -f "$MANIFEST"
}

# ═══ Dispatch ═══
install_pi() {
  require_jq
  case "$MODE" in
    skill)     install_skill_mode ;;
    agents-md) install_agents_md_mode ;;
    *)
      echo "[pi-adapter] unknown MB_PI_MODE=$MODE (expected: agents-md|skill)" >&2
      exit 1
      ;;
  esac
}

uninstall_pi() {
  if [ ! -f "$MANIFEST" ]; then
    echo "[pi-adapter] no manifest found, nothing to uninstall"
    return 0
  fi
  require_jq
  local installed_mode
  installed_mode=$(jq -r '.mode // "agents-md"' "$MANIFEST")
  case "$installed_mode" in
    skill)     uninstall_skill_mode ;;
    agents-md) uninstall_agents_md_mode ;;
    *)
      echo "[pi-adapter] unknown mode in manifest: $installed_mode" >&2
      exit 1
      ;;
  esac
  echo "[pi-adapter] uninstalled from $PROJECT_ROOT"
}

case "$ACTION" in
  install)   install_pi ;;
  uninstall) uninstall_pi ;;
  *)
    echo "Usage: [MB_PI_MODE=agents-md|skill] $0 install|uninstall [PROJECT_ROOT]" >&2
    exit 1
    ;;
esac
