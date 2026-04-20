#!/usr/bin/env bash
# adapters/opencode.sh — OpenCode cross-agent adapter.
#
# OpenCode plugins are JS/TS modules registered in opencode.json.
# Key events: session.created/idle/deleted, tool.execute.before/after,
#             experimental.session.compacting (direct PreCompact equivalent).
# AGENTS.md is the shared-format instructions file (used by OpenCode, Codex,
# Pi fallback, auto-read by Cline).
#
# Usage:
#   adapters/opencode.sh install [PROJECT_ROOT]
#   adapters/opencode.sh uninstall [PROJECT_ROOT]

set -euo pipefail

ACTION="${1:-}"
PROJECT_ROOT_RAW="${2:-$(pwd)}"

if [ ! -d "$PROJECT_ROOT_RAW" ]; then
  echo "[opencode-adapter] project root not found: $PROJECT_ROOT_RAW" >&2
  exit 1
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT_RAW" && pwd)"

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OC_DIR="$PROJECT_ROOT/.opencode"
COMMANDS_DIR="$OC_DIR/commands"
PLUGIN_DIR="$OC_DIR/plugins"
PLUGIN_FILE="$PLUGIN_DIR/memory-bank.js"
PLUGIN_REF="./.opencode/plugins/memory-bank.js"
OC_JSON="$PROJECT_ROOT/opencode.json"
MANIFEST="$OC_DIR/.mb-manifest.json"

# shellcheck disable=SC1091
. "$(dirname "$0")/_lib_agents_md.sh"

require_jq() { command -v jq >/dev/null 2>&1 || { echo "[opencode-adapter] jq required" >&2; exit 1; }; }

# ═══ Plugin file ═══
plugin_body() {
  cat <<'PLUGIN_EOF'
// Memory Bank — OpenCode plugin
// Registers hooks for session lifecycle + tool guard + compact-reminder.
// Auto-captures session placeholder to .memory-bank/progress.md.
// memory-bank: managed plugin (do not remove marker line)

import { execSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';

export const MemoryBankPlugin = async ({ app }) => {
  const mbDir = () => path.join(app.path.cwd, '.memory-bank');
  const hasMb = () => {
    try { return fs.statSync(mbDir()).isDirectory(); } catch { return false; }
  };

  const appendProgress = (sessionId) => {
    if (!hasMb()) return;
    const progress = path.join(mbDir(), 'progress.md');
    if (!fs.existsSync(progress)) return;
    const captureMode = process.env.MB_AUTO_CAPTURE ?? 'auto';
    if (captureMode === 'off' || captureMode === 'strict') return;

    const sidPrefix = String(sessionId).slice(0, 8);
    const existing = fs.readFileSync(progress, 'utf8');
    if (existing.includes(`Auto-capture`) && existing.includes(`oc-${sidPrefix}`)) return;

    const today = new Date().toISOString().slice(0, 10);
    const entry = `\n## ${today}\n\n### Auto-capture ${today} (oc-${sidPrefix})\n- OpenCode session detected via session.idle hook\n- Details will be restored on next /mb start\n`;
    fs.appendFileSync(progress, entry);
  };

  return {
    hooks: {
      'session.idle': async ({ session }) => {
        appendProgress(session?.id ?? 'oc-unknown');
      },
      'session.deleted': async ({ session }) => {
        appendProgress(session?.id ?? 'oc-unknown');
      },
      'tool.execute.before': async ({ tool, args }) => {
        // Block dangerous shell commands
        const cmd = String(args?.command ?? '');
        const dangerous = [
          /rm\s+-rf\s+\//,
          /rm\s+-rf\s+~/,
          /:\(\)\s*\{\s*:\|:&\s*\};:/,
        ];
        if (dangerous.some((re) => re.test(cmd))) {
          throw new Error(`[MB-opencode] BLOCKED dangerous command: ${cmd}`);
        }
      },
      'experimental.session.compacting': async ({ session }) => {
        // Direct PreCompact equivalent — actualize progress before compaction
        if (!hasMb()) return;
        const stamp = new Date().toISOString();
        const progress = path.join(mbDir(), 'progress.md');
        if (!fs.existsSync(progress)) return;
        fs.appendFileSync(
          progress,
          `\n<!-- opencode-compacting-checkpoint ${stamp} session=${session?.id?.slice(0, 8) ?? '?'} -->\n`,
        );
      },
    },
  };
};

export default MemoryBankPlugin;
PLUGIN_EOF
}

# ═══ opencode.json management ═══
install_opencode_json() {
  local tmp
  if [ -f "$OC_JSON" ]; then
    tmp=$(jq --arg ref "$PLUGIN_REF" '
      .plugin //= []
      | .plugin = ((.plugin // []) - [$ref] + [$ref])
    ' "$OC_JSON")
    echo "$tmp" > "$OC_JSON"
  else
    jq -n --arg ref "$PLUGIN_REF" '{plugin: [$ref]}' > "$OC_JSON"
  fi
}

uninstall_opencode_json() {
  [ -f "$OC_JSON" ] || return 0
  local tmp
  tmp=$(jq --arg ref "$PLUGIN_REF" '
    .plugin = ((.plugin // []) - [$ref])
    | if (.plugin | length) == 0 then del(.plugin) else . end
  ' "$OC_JSON")
  # If file becomes empty object → remove, otherwise write back
  if [ "$(echo "$tmp" | jq 'length')" = "0" ]; then
    rm -f "$OC_JSON"
  else
    echo "$tmp" > "$OC_JSON"
  fi
}

# ═══ Install ═══
install_opencode() {
  require_jq
  mkdir -p "$PLUGIN_DIR" "$COMMANDS_DIR"

  local owned
  owned=$(agents_md_install "$PROJECT_ROOT" "opencode" "$SKILL_DIR")
  plugin_body > "$PLUGIN_FILE"
  install_opencode_json

  local f
  for f in "$SKILL_DIR"/commands/*.md; do
    [ -f "$f" ] || continue
    cp "$f" "$COMMANDS_DIR/$(basename "$f")"
  done

  local files_json
  files_json=$(
    {
      printf '%s\n' "$PLUGIN_FILE"
      for f in "$SKILL_DIR"/commands/*.md; do
        [ -f "$f" ] || continue
        printf '%s\n' "$COMMANDS_DIR/$(basename "$f")"
      done
    } | jq -R . | jq -s .
  )

  jq -n \
    --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg skill_version "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    --arg plugin_ref "$PLUGIN_REF" \
    --argjson files "$files_json" \
    --argjson agents_owned "$owned" \
    '{installed_at: $installed_at, adapter: "opencode", skill_version: $skill_version, plugin_ref: $plugin_ref, files: $files, agents_md_owned: $agents_owned}' \
    > "$MANIFEST"

  echo "[opencode-adapter] installed to $PROJECT_ROOT"
}

# ═══ Uninstall ═══
uninstall_opencode() {
  if [ ! -f "$MANIFEST" ]; then
    echo "[opencode-adapter] no manifest found, nothing to uninstall"
    return 0
  fi
  require_jq

  # 1. Remove plugin file
  local files
  files=$(jq -r '.files[]' "$MANIFEST")
  local f
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] && rm -f "$f"
  done <<< "$files"

  # 2. Strip from opencode.json
  uninstall_opencode_json

  # 3. Decrement AGENTS.md ownership (shared lib handles file removal)
  agents_md_uninstall "$PROJECT_ROOT" "opencode"

  # 4. Remove manifest
  rm -f "$MANIFEST"

  # 5. Clean empty dirs
  rmdir "$PLUGIN_DIR" 2>/dev/null || true
  rmdir "$COMMANDS_DIR" 2>/dev/null || true
  rmdir "$OC_DIR" 2>/dev/null || true

  echo "[opencode-adapter] uninstalled from $PROJECT_ROOT"
}

case "$ACTION" in
  install)   install_opencode ;;
  uninstall) uninstall_opencode ;;
  *)
    echo "Usage: $0 install|uninstall [PROJECT_ROOT]" >&2
    exit 1
    ;;
esac
