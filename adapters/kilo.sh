#!/usr/bin/env bash
# adapters/kilo.sh — Kilo Code cross-agent adapter.
#
# Kilo is the only target client without a first-class hooks API
# (FR Kilo-Org/kilocode#5827 open). Adapter writes .kilocode/rules/memory-bank.md
# and installs git-hooks-fallback for lifecycle events.
#
# Usage:
#   adapters/kilo.sh install [PROJECT_ROOT]
#   adapters/kilo.sh uninstall [PROJECT_ROOT]

set -euo pipefail

ACTION="${1:-}"
PROJECT_ROOT_RAW="${2:-$(pwd)}"

if [ ! -d "$PROJECT_ROOT_RAW" ]; then
  echo "[kilo-adapter] project root not found: $PROJECT_ROOT_RAW" >&2
  exit 1
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT_RAW" && pwd)"

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ADAPTERS_DIR="$SKILL_DIR/adapters"
KILO_DIR="$PROJECT_ROOT/.kilocode"
RULES_FILE="$KILO_DIR/rules/memory-bank.md"
MANIFEST="$KILO_DIR/.mb-manifest.json"
GIT_FALLBACK="$ADAPTERS_DIR/git-hooks-fallback.sh"

require_jq() { command -v jq >/dev/null 2>&1 || { echo "[kilo-adapter] jq required" >&2; exit 1; }; }
require_git() {
  if [ ! -d "$PROJECT_ROOT/.git" ]; then
    echo "[kilo-adapter] Kilo requires git repo (git-hooks-fallback is mandatory — no native hooks API)" >&2
    exit 1
  fi
}

install_kilo() {
  require_jq
  require_git
  mkdir -p "$KILO_DIR/rules"

  # 1. Rules file
  {
    echo '# Memory Bank — Project Rules'
    echo ''
    echo 'This project uses the Memory Bank skill for long-term memory + dev workflow.'
    echo ''
    echo '**Workflow:**'
    echo '- Start of session: read `.memory-bank/STATUS.md`, `checklist.md`, `plan.md`, `RESEARCH.md`'
    echo '- Update `checklist.md` immediately (⬜ → ✅) when tasks done'
    echo '- Before context window fill: manual actualize'
    echo ''
    if [ -f "$SKILL_DIR/rules/RULES.md" ]; then
      echo '---'
      echo ''
      echo '# Global Rules'
      echo ''
      cat "$SKILL_DIR/rules/RULES.md"
    fi
  } > "$RULES_FILE"

  # 2. Install git-hooks-fallback (mandatory — Kilo has no native hooks)
  bash "$GIT_FALLBACK" install "$PROJECT_ROOT" >/dev/null

  # 3. Manifest
  local files_json
  files_json=$(printf '%s\n' "$RULES_FILE" | jq -R . | jq -s .)
  jq -n \
    --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg skill_version "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    --argjson files "$files_json" \
    '{installed_at: $installed_at, adapter: "kilo", skill_version: $skill_version, files: $files, git_hooks_installed: true}' \
    > "$MANIFEST"

  echo "[kilo-adapter] installed to $PROJECT_ROOT"
}

uninstall_kilo() {
  if [ ! -f "$MANIFEST" ]; then
    echo "[kilo-adapter] no manifest found, nothing to uninstall"
    return 0
  fi
  require_jq

  # 1. Remove tracked files
  local files
  files=$(jq -r '.files[]' "$MANIFEST")
  local f
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] && rm -f "$f"
  done <<< "$files"

  # 2. Uninstall git-hooks-fallback if we installed it
  local installed_git
  installed_git=$(jq -r '.git_hooks_installed // false' "$MANIFEST")
  if [ "$installed_git" = "true" ]; then
    bash "$GIT_FALLBACK" uninstall "$PROJECT_ROOT" >/dev/null
  fi

  # 3. Remove manifest
  rm -f "$MANIFEST"

  # 4. Clean empty dirs (only if we were sole owner)
  rmdir "$KILO_DIR/rules" 2>/dev/null || true
  rmdir "$KILO_DIR" 2>/dev/null || true

  echo "[kilo-adapter] uninstalled from $PROJECT_ROOT"
}

case "$ACTION" in
  install)   install_kilo ;;
  uninstall) uninstall_kilo ;;
  *)
    echo "Usage: $0 install|uninstall [PROJECT_ROOT]" >&2
    exit 1
    ;;
esac
