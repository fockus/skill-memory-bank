#!/usr/bin/env bash
# adapters/pi.sh — Pi Code (pi-mono) cross-agent adapter.
#
# Pi global install is handled by install.sh. This adapter adds project-local wiring.
#
#   MB_PI_MODE=agents-md  (default)  — project AGENTS.md (shared, refcount) +
#                                       git-hooks-fallback when PROJECT_ROOT is a git repo.
#                                       Safe, stable today.
#
# Compatibility path:
#   MB_PI_MODE=skill adapters/pi.sh install [PROJECT_ROOT]
#                                       Native ~/.pi/agent/skills/memory-bank/ package.
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
# shellcheck source=../scripts/_lib.sh
. "$SKILL_DIR/scripts/_lib.sh"
# shellcheck disable=SC1091
. "$(dirname "$0")/_framework.sh"
# shellcheck disable=SC1091
. "$(dirname "$0")/_contract.sh"

# ═══ Skill mode (native ~/.pi/agent/skills/memory-bank/) ═══
PI_SKILL_DIR="$HOME/.pi/agent/skills/memory-bank"

install_skill_mode() {
  if [ -L "$PI_SKILL_DIR" ]; then
    adapter_write_manifest \
      "$MANIFEST" \
      "pi" \
      "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
      '[]' \
      '{"mode": "skill", "pi_skill_dir": "", "global_skill_alias_detected": true}'
    echo "[pi-adapter] global Pi skill alias already exists; leaving it unchanged"
    return 0
  fi

  mkdir -p "$PI_SKILL_DIR"

  # Minimal Agent Skills-compatible SKILL.md for Pi discovery.
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
    echo '- Start of session: read `.memory-bank/status.md`, `checklist.md`, `roadmap.md`, `research.md`'
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
  files_json=$(printf '%s\n' "$PI_SKILL_DIR/SKILL.md" | adapter_json_array_from_lines)

  adapter_write_manifest \
    "$MANIFEST" \
    "pi" \
    "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    "$files_json" \
    "{\"mode\": \"skill\", \"pi_skill_dir\": $(jq -Rn --arg p "$PI_SKILL_DIR" '$p')}"

  echo "[pi-adapter] installed (mode: skill, path: $PI_SKILL_DIR)"
}

uninstall_skill_mode() {
  local skill_path
  skill_path=$(jq -r '.pi_skill_dir // empty' "$MANIFEST")
  if [ -n "$skill_path" ] && [ -d "$skill_path" ]; then
    if mb_path_is_within "$skill_path" "$HOME/.pi/agent/skills"; then
      rm -rf "$skill_path"
    else
      echo "[pi-adapter] skip unsafe manifest path: $skill_path" >&2
    fi
  fi
  rm -f "$MANIFEST"
  # Clean empty parent dirs
  rmdir "$HOME/.pi/agent/skills" 2>/dev/null || true
  rmdir "$HOME/.pi/agent" 2>/dev/null || true
  rmdir "$HOME/.pi" 2>/dev/null || true
}

# ═══ AGENTS.md mode (default) ═══
install_agents_md_mode() {
  local owned git_hooks_installed graph_ext_installed
  owned=$(agents_md_install "$PROJECT_ROOT" "pi" "$SKILL_DIR")
  git_hooks_installed=false
  if [ -d "$PROJECT_ROOT/.git" ]; then
    bash "$GIT_FALLBACK" install "$PROJECT_ROOT" >/dev/null
    git_hooks_installed=true
  else
    echo "[pi-adapter] project is not a git repo; installed AGENTS.md only" >&2
  fi

  graph_ext_installed=$(_install_graph_rag_extension)

  adapter_write_manifest \
    "$MANIFEST" \
    "pi" \
    "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    "[\"$PROJECT_ROOT/.pi/extensions/memory-bank-graph-rag.ts\"]" \
    "{\"mode\": \"agents-md\", \"agents_md_owned\": $owned, \"git_hooks_installed\": $git_hooks_installed, \"graph_ext_installed\": $graph_ext_installed}"

  echo "[pi-adapter] installed (mode: agents-md)"
}

# Copy adapters/pi_graph_rag_extension.ts → $PROJECT_ROOT/.pi/extensions/.
# Provides native Pi tool wrappers (code_context, graph_neighbors,
# graph_impact, graph_tests) that delegate to scripts/mb-*-query.py and
# scripts/mb-code-context.py. Fail-open contract: missing source file
# is not fatal — returns "false" so caller can record skipped state.
_install_graph_rag_extension() {
  local src="$SKILL_DIR/adapters/pi_graph_rag_extension.ts"
  local dest="$PROJECT_ROOT/.pi/extensions/memory-bank-graph-rag.ts"
  if [ ! -f "$src" ]; then
    echo "false"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  echo "true"
}

uninstall_agents_md_mode() {
  local installed_git installed_graph_ext
  installed_git=$(jq -r '.git_hooks_installed // false' "$MANIFEST")
  installed_graph_ext=$(jq -r '.graph_ext_installed // false' "$MANIFEST")

  agents_md_uninstall "$PROJECT_ROOT" "pi"

  if [ "$installed_git" = "true" ]; then
    bash "$GIT_FALLBACK" uninstall "$PROJECT_ROOT" >/dev/null
  fi

  if [ "$installed_graph_ext" = "true" ]; then
    rm -f "$PROJECT_ROOT/.pi/extensions/memory-bank-graph-rag.ts"
    rmdir "$PROJECT_ROOT/.pi/extensions" 2>/dev/null || true
    rmdir "$PROJECT_ROOT/.pi" 2>/dev/null || true
  fi

  rm -f "$MANIFEST"
}

# ═══ Dispatch ═══
install_pi() {
  adapter_require_jq "pi-adapter" || exit 1
  case "$MODE" in
    skill)
      install_skill_mode
      ;;
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
  adapter_require_jq "pi-adapter" || exit 1
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

adapter_contract_require_functions install_pi uninstall_pi >/dev/null
