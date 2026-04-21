#!/usr/bin/env bash
# adapters/cursor.sh — Cursor IDE adapter for Memory Bank.
#
# Cursor 1.7+ (October 2025) added a Claude-Code-compatible hooks API.
# This adapter writes .cursor/rules/memory-bank.mdc (rules) + .cursor/hooks.json
# (events → our hook scripts) and copies the hook scripts into .cursor/hooks/ so
# the project is self-contained (no dependency on ~/.claude being present).
#
# Usage:
#   adapters/cursor.sh install [PROJECT_ROOT]
#   adapters/cursor.sh uninstall [PROJECT_ROOT]
#
# Idempotent. Preserves user-owned hooks in existing .cursor/hooks.json via jq merge.
# Manifest in .cursor/.mb-manifest.json tracks ownership for clean uninstall.

set -euo pipefail

ACTION="${1:-}"
PROJECT_ROOT_RAW="${2:-$(pwd)}"

# Resolve absolute path; fail if project root doesn't exist
if [ ! -d "$PROJECT_ROOT_RAW" ]; then
  echo "[cursor-adapter] project root not found: $PROJECT_ROOT_RAW" >&2
  exit 1
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT_RAW" && pwd)"

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CURSOR_DIR="$PROJECT_ROOT/.cursor"
RULES_FILE="$CURSOR_DIR/rules/memory-bank.mdc"
HOOKS_JSON="$CURSOR_DIR/hooks.json"
HOOKS_DIR="$CURSOR_DIR/hooks"
MANIFEST="$CURSOR_DIR/.mb-manifest.json"

# shellcheck disable=SC1091
. "$(dirname "$0")/_lib_agents_md.sh"

# Our hook scripts that get copied into .cursor/hooks/
MB_HOOKS=(
  "session-end-autosave.sh"
  "mb-compact-reminder.sh"
  "block-dangerous.sh"
)

# Event → script mapping (Cursor event names, CC-compat)
# Format: "event:script"
EVENT_BINDINGS=(
  "sessionEnd:session-end-autosave.sh"
  "preCompact:mb-compact-reminder.sh"
  "beforeShellExecution:block-dangerous.sh"
)

require_jq() {
  command -v jq >/dev/null 2>&1 || { echo "[cursor-adapter] jq required" >&2; exit 1; }
}

# ═══ Install ═══
install_cursor() {
  require_jq
  mkdir -p "$CURSOR_DIR/rules" "$HOOKS_DIR"

  # 1. Rules file (.mdc with YAML frontmatter)
  {
    echo '---'
    echo 'description: "Memory Bank — long-term project memory, workflow, and dev rules"'
    echo 'alwaysApply: true'
    echo '---'
    echo ''
    echo '# Memory Bank — Project Rules'
    echo ''
    echo 'This project uses the Memory Bank skill for long-term memory + dev workflow.'
    echo ''
    echo '**Workflow:**'
    echo '- Start of session: read `.memory-bank/STATUS.md`, `checklist.md`, `plan.md`, `RESEARCH.md`'
    echo '- Update `checklist.md` immediately (⬜ → ✅) when tasks done'
    echo '- Before context window fill: manual actualize via Memory Bank workflow'
    echo ''
    if [ -f "$SKILL_DIR/rules/RULES.md" ]; then
      echo '---'
      echo ''
      mb_emit_rules_file "$SKILL_DIR/rules/RULES.md"
    fi
  } > "$RULES_FILE"

  # 2. Copy hook scripts
  local h
  for h in "${MB_HOOKS[@]}"; do
    if [ ! -f "$SKILL_DIR/hooks/$h" ]; then
      echo "[cursor-adapter] missing hook: $SKILL_DIR/hooks/$h" >&2
      exit 1
    fi
    cp "$SKILL_DIR/hooks/$h" "$HOOKS_DIR/$h"
    chmod +x "$HOOKS_DIR/$h"
  done

  # 3. Build our hook bindings for hooks.json
  # Each event gets: { "command": "bash .cursor/hooks/<script>", "_mb_owned": true }
  local our_hooks_json
  our_hooks_json=$(jq -n '{hooks: {}}')
  local binding event script cmd
  for binding in "${EVENT_BINDINGS[@]}"; do
    event="${binding%%:*}"
    script="${binding#*:}"
    cmd="bash .cursor/hooks/$script"
    our_hooks_json=$(echo "$our_hooks_json" | jq \
      --arg event "$event" \
      --arg cmd "$cmd" \
      '.hooks[$event] = [{command: $cmd, _mb_owned: true}]')
  done

  # 4. Merge with existing hooks.json (preserve user hooks, dedupe ours)
  local merged
  if [ -f "$HOOKS_JSON" ]; then
    # Remove any pre-existing _mb_owned entries to avoid dupes, then append ours
    merged=$(jq --slurpfile new <(echo "$our_hooks_json") '
      . as $existing |
      (.hooks // {}) as $eh |
      (.version // 1) as $ver |
      reduce ($new[0].hooks | keys[]) as $evt (
        $existing;
        .version = $ver
        | .hooks //= {}
        | .hooks[$evt] = (
            ((.hooks[$evt] // []) | map(select((._mb_owned // false) | not)))
            + ($new[0].hooks[$evt])
          )
      )
    ' "$HOOKS_JSON")
  else
    merged=$(echo "$our_hooks_json" | jq '.version = 1')
  fi
  echo "$merged" > "$HOOKS_JSON"

  # 5. Manifest (files we own + events we registered)
  local files_json events_json
  files_json=$(printf '%s\n' "$RULES_FILE" "$HOOKS_DIR"/*.sh | jq -R . | jq -s .)
  events_json=$(printf '%s\n' "${EVENT_BINDINGS[@]}" | awk -F: '{print $1}' | jq -R . | jq -s .)

  jq -n \
    --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg skill_version "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    --argjson files "$files_json" \
    --argjson hooks_events "$events_json" \
    '{installed_at: $installed_at, adapter: "cursor", skill_version: $skill_version, files: $files, hooks_events: $hooks_events}' \
    > "$MANIFEST"

  echo "[cursor-adapter] installed to $PROJECT_ROOT"
}

# ═══ Uninstall ═══
uninstall_cursor() {
  if [ ! -f "$MANIFEST" ]; then
    echo "[cursor-adapter] no manifest found, nothing to uninstall"
    return 0
  fi
  require_jq

  # 1. Remove files listed in manifest
  local files
  files=$(jq -r '.files[]' "$MANIFEST")
  local f
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] && rm -f "$f"
  done <<< "$files"

  # 2. Strip our-owned entries from hooks.json
  if [ -f "$HOOKS_JSON" ]; then
    local events
    events=$(jq -r '.hooks_events[]' "$MANIFEST")
    local cleaned="$HOOKS_JSON.tmp"
    cp "$HOOKS_JSON" "$cleaned"
    local evt
    while IFS= read -r evt; do
      [ -z "$evt" ] && continue
      jq --arg e "$evt" '
        .hooks[$e] = ((.hooks[$e] // []) | map(select((._mb_owned // false) | not)))
        | if (.hooks[$e] | length) == 0 then del(.hooks[$e]) else . end
      ' "$cleaned" > "$cleaned.2" && mv "$cleaned.2" "$cleaned"
    done <<< "$events"

    # If hooks.json now has no hooks left AND we created it (no user content) → delete
    local remaining
    remaining=$(jq '.hooks | length' "$cleaned")
    if [ "$remaining" -eq 0 ]; then
      rm -f "$HOOKS_JSON" "$cleaned"
    else
      mv "$cleaned" "$HOOKS_JSON"
    fi
  fi

  # 3. Remove manifest itself
  rm -f "$MANIFEST"

  # 4. Clean up empty dirs
  rmdir "$HOOKS_DIR" 2>/dev/null || true
  rmdir "$CURSOR_DIR/rules" 2>/dev/null || true
  rmdir "$CURSOR_DIR" 2>/dev/null || true

  echo "[cursor-adapter] uninstalled from $PROJECT_ROOT"
}

case "$ACTION" in
  install)   install_cursor ;;
  uninstall) uninstall_cursor ;;
  *)
    echo "Usage: $0 install|uninstall [PROJECT_ROOT]" >&2
    exit 1
    ;;
esac
