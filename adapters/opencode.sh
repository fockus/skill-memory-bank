#!/usr/bin/env bash
# adapters/opencode.sh — OpenCode cross-agent adapter.
#
# OpenCode plugins are JS/TS modules auto-discovered from .opencode/plugins/.
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
# shellcheck disable=SC1091
. "$(dirname "$0")/_framework.sh"
# shellcheck disable=SC1091
. "$(dirname "$0")/_contract.sh"

# ═══ Plugin file ═══
plugin_body() {
  cat <<'PLUGIN_EOF'
// Memory Bank — OpenCode plugin
// Registers hooks for session lifecycle + tool guard + compact-reminder.
// Auto-captures session placeholder to .memory-bank/progress.md.
// GraphRAG-lite native tool wrappers may expose code_context, graph_neighbors,
// graph_impact, and graph_tests; CLI fallback is scripts/mb-code-context.py
// plus scripts/mb-graph-query.py when native tool support is unavailable.
// memory-bank: managed plugin (do not remove marker line)

import { execSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';

export const MemoryBankPlugin = async ({ directory }) => {
  // Resolve Memory Bank path: MB_PATH env override → local project bank
  const mbDir = () => {
    const override = process.env.MB_PATH;
    if (override && fs.existsSync(override)) return override;
    return path.resolve(directory, '.memory-bank');
  };
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
    event: async ({ event }) => {
      if (event?.type === 'session.idle' || event?.type === 'session.deleted') {
        appendProgress(event?.properties?.info?.id ?? event?.properties?.sessionID ?? 'oc-unknown');
      }
    },
    'tool.execute.before': async (input, output) => {
      // Block dangerous shell commands.
      const cmd = String(output?.args?.command ?? '');
      const dangerous = [
        /rm\s+-rf\s+\//,
        /rm\s+-rf\s+~/,
        /:\(\)\s*\{\s*:\|:&\s*\};:/,
      ];
      if (dangerous.some((re) => re.test(cmd))) {
        throw new Error(`[MB-opencode] BLOCKED dangerous command: ${cmd}`);
      }
    },
    'experimental.session.compacting': async (input, output) => {
      // Direct PreCompact equivalent: persist a checkpoint and enrich compaction context.
      if (!hasMb()) return;
      const stamp = new Date().toISOString();
      const progress = path.join(mbDir(), 'progress.md');
      if (!fs.existsSync(progress)) return;
      const sessionId = input?.session?.id ?? 'unknown';
      const marker = `opencode-compacting-checkpoint ${stamp} session=${String(sessionId).slice(0, 8)}`;
      fs.appendFileSync(progress, `\n<!-- ${marker} -->\n`);
      if (Array.isArray(output?.context)) {
        output.context.push(`Memory Bank checkpoint: ${marker}`);
      }
    },
  };
};

export default MemoryBankPlugin;
PLUGIN_EOF
}

# ═══ opencode.json management ═══
# Back up the user's TRUE original opencode.json exactly once (rotation-safe:
# never clobber it on re-install). Skip only if a real regular-FILE MB backup
# already exists — a coincidental dir/other match must not suppress the backup.
opencode_backup_json() {
  [ -f "$OC_JSON" ] || return 0
  local b
  for b in "$OC_JSON".pre-mb-backup.*; do
    [ -f "$b" ] && return 0
  done
  cp "$OC_JSON" "$OC_JSON.pre-mb-backup.$$"
}

# Strip MB's plugin ref, write atomically (unique tmp + mv, same dir). Broken
# JSON → leave the user's file untouched (jq failed; a backup was already taken
# on install). Empty object → remove. Foreign keys are preserved by jq.
_opencode_strip_plugin_ref() {
  [ -f "$OC_JSON" ] || return 0
  local tmp
  if ! tmp=$(jq --arg ref "$PLUGIN_REF" '
    .plugin = ((.plugin // []) - [$ref])
    | if (.plugin | length) == 0 then del(.plugin) else . end
  ' "$OC_JSON" 2>/dev/null); then
    return 0
  fi
  if [ "$(printf '%s' "$tmp" | jq 'length' 2>/dev/null)" = "0" ]; then
    rm -f "$OC_JSON"
  else
    local out mode
    out="$(mktemp "$(dirname "$OC_JSON")/.opencode.json.mbXXXXXX")" || return 1
    mode="$(mb_file_mode "$OC_JSON")"
    if printf '%s\n' "$tmp" > "$out"; then
      [ -n "$mode" ] && chmod "$mode" "$out" 2>/dev/null
      mv "$out" "$OC_JSON"
    else
      rm -f "$out"; return 1
    fi
  fi
}

install_opencode_json() {
  [ -f "$OC_JSON" ] || return 0
  opencode_backup_json
  _opencode_strip_plugin_ref
}

uninstall_opencode_json() {
  _opencode_strip_plugin_ref
}

# ═══ Install ═══
install_opencode() {
  adapter_require_jq "opencode-adapter" || exit 1
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
    } | adapter_json_array_from_lines
  )

  adapter_write_manifest \
    "$MANIFEST" \
    "opencode" \
    "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    "$files_json" \
    "{\"plugin_ref\": $(jq -Rn --arg ref "$PLUGIN_REF" '$ref'), \"agents_md_owned\": $owned}"

  echo "[opencode-adapter] installed to $PROJECT_ROOT"
}

# ═══ Uninstall ═══
uninstall_opencode() {
  if [ ! -f "$MANIFEST" ]; then
    echo "[opencode-adapter] no manifest found, nothing to uninstall"
    return 0
  fi
  adapter_require_jq "opencode-adapter" || exit 1

  # 1. Remove plugin file
  adapter_remove_manifest_files "$MANIFEST"

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

adapter_contract_require_functions install_opencode uninstall_opencode >/dev/null
