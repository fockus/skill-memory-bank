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

if [ "$ACTION" = "install" ] || [ "$ACTION" = "uninstall" ]; then
  if [ ! -d "$PROJECT_ROOT_RAW" ]; then
    echo "[cursor-adapter] project root not found: $PROJECT_ROOT_RAW" >&2
    exit 1
  fi
  PROJECT_ROOT="$(cd "$PROJECT_ROOT_RAW" && pwd)"
else
  PROJECT_ROOT=""
fi

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CURSOR_DIR="$PROJECT_ROOT/.cursor"
RULES_FILE="$CURSOR_DIR/rules/memory-bank.mdc"
HOOKS_JSON="$CURSOR_DIR/hooks.json"
HOOKS_DIR="$CURSOR_DIR/hooks"
MANIFEST="$CURSOR_DIR/.mb-manifest.json"
GLOBAL_CURSOR_DIR="$HOME/.cursor"
GLOBAL_HOOKS_DIR="$GLOBAL_CURSOR_DIR/hooks"
GLOBAL_COMMANDS_DIR="$GLOBAL_CURSOR_DIR/commands"
GLOBAL_HOOKS_JSON="$GLOBAL_CURSOR_DIR/hooks.json"
GLOBAL_AGENTS_FILE="$GLOBAL_CURSOR_DIR/AGENTS.md"
GLOBAL_USER_RULES_FILE="$GLOBAL_CURSOR_DIR/memory-bank-user-rules.md"
GLOBAL_MANIFEST="$GLOBAL_CURSOR_DIR/.mb-manifest.json"
CURSOR_START_MARKER="<!-- memory-bank-cursor:start -->"
CURSOR_END_MARKER="<!-- memory-bank-cursor:end -->"

# shellcheck disable=SC1091
. "$(dirname "$0")/_lib_agents_md.sh"
# shellcheck disable=SC1091
. "$(dirname "$0")/_framework.sh"
# shellcheck disable=SC1091
. "$(dirname "$0")/_contract.sh"

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

run_texttool() {
  PYTHONPATH="$SKILL_DIR${PYTHONPATH:+:$PYTHONPATH}" \
    python3 -m memory_bank_skill._texttools "$@"
}

language_rule_full() {
  case "${MB_LANGUAGE:-en}" in
    ru) printf '%s' "Russian — responses and code comments. Technical terms may remain in English." ;;
    *) printf '%s' "English — responses and code comments. Technical terms may remain in English." ;;
  esac
}

language_rule_short() {
  case "${MB_LANGUAGE:-en}" in
    ru) printf '%s' "respond in Russian; technical terms may remain in English." ;;
    *) printf '%s' "respond in English; technical terms may remain in English." ;;
  esac
}

comments_language_name() {
  case "${MB_LANGUAGE:-en}" in
    ru) printf '%s' "Russian" ;;
    *) printf '%s' "English" ;;
  esac
}

localize_file_with_language() {
  local path="$1"
  local after_marker="${2:-}"
  [ -f "$path" ] || return 0
  run_texttool localize-file \
    --path "$path" \
    --rule-full "$(language_rule_full)" \
    --rule-short "$(language_rule_short)" \
    --comments-language "$(comments_language_name)" \
    --after-marker "$after_marker"
}

cursor_build_hooks_json() {
  local command_prefix="$1"
  local our_hooks_json binding event script cmd
  our_hooks_json=$(jq -n '{hooks: {}}')
  for binding in "${EVENT_BINDINGS[@]}"; do
    event="${binding%%:*}"
    script="${binding#*:}"
    cmd="bash ${command_prefix}/${script}"
    our_hooks_json=$(echo "$our_hooks_json" | jq \
      --arg event "$event" \
      --arg cmd "$cmd" \
      '.hooks[$event] = [{command: $cmd, _mb_owned: true}]')
  done
  printf '%s' "$our_hooks_json"
}

cursor_merge_hooks_json() {
  local target="$1"
  local our_hooks_json="$2"
  local merged
  if [ -f "$target" ]; then
    merged=$(jq --slurpfile new <(echo "$our_hooks_json") '
      . as $existing |
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
    ' "$target")
  else
    merged=$(echo "$our_hooks_json" | jq '.version = 1')
  fi
  echo "$merged" > "$target"
}

global_backup_if_exists() {
  local target="$1"
  local backup_list_name="$2"
  local expected="${3:-}"
  local old backup
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ -n "$expected" ] && [ -f "$expected" ] && cmp -s "$target" "$expected"; then
      return 2
    fi
    for old in "$target".pre-mb-backup.*; do
      [ -e "$old" ] || [ -L "$old" ] || continue
      rm -rf -- "$old"
    done
    backup="$target.pre-mb-backup.$(date +%s)"
    mv "$target" "$backup"
    eval "$backup_list_name+=(\"$target|$backup\")"
  fi
}

global_install_file() {
  local src="$1" dst="$2" files_list_name="$3" backups_list_name="$4"
  mkdir -p "$(dirname "$dst")"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    [[ "$dst" == *.sh ]] && chmod +x "$dst"
    eval "$files_list_name+=(\"$dst\")"
    return 0
  fi
  global_backup_if_exists "$dst" "$backups_list_name"
  cp "$src" "$dst"
  [[ "$dst" == *.sh ]] && chmod +x "$dst"
  eval "$files_list_name+=(\"$dst\")"
}

global_cursor_agents_section() {
  cat <<EOF
$CURSOR_START_MARKER

# Memory Bank — Cursor Global Entry Point

Global Memory Bank skill is registered at:
- \`~/.cursor/skills/memory-bank/SKILL.md\`

Bundled resources available to Cursor agents:
- Commands: \`~/.cursor/commands/\` (mirror of skill \`commands/\`)
- Agent prompts: \`~/.cursor/skills/memory-bank/agents/\`
- Hooks: \`~/.cursor/hooks/\` wired via \`~/.cursor/hooks.json\`

Recommended workflow:
- Start by reading \`.memory-bank/status.md\`, \`checklist.md\`, \`roadmap.md\`, \`research.md\`
- Use \`/mb\` as the entrypoint for Memory Bank flows
- Update \`checklist.md\` immediately (⬜ → ✅) when tasks complete

Cursor surfaces user-level rules only through **Settings → Rules → User Rules**.
The same content is mirrored to \`~/.cursor/memory-bank-user-rules.md\` for copy-paste:
- macOS:  \`pbcopy < ~/.cursor/memory-bank-user-rules.md\`
- Linux:  \`xclip -selection clipboard < ~/.cursor/memory-bank-user-rules.md\`

---

EOF
  cat "$SKILL_DIR/rules/CLAUDE-GLOBAL.md"
  printf '\n%s\n' "$CURSOR_END_MARKER"
}

# ═══ Install ═══
install_cursor() {
  adapter_require_jq "cursor-adapter" || exit 1
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
    echo '- Start of session: read `.memory-bank/status.md`, `checklist.md`, `roadmap.md`, `research.md`'
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
  files_json=$(printf '%s\n' "$RULES_FILE" "$HOOKS_DIR"/*.sh | adapter_json_array_from_lines)
  events_json=$(printf '%s\n' "${EVENT_BINDINGS[@]}" | awk -F: '{print $1}' | adapter_json_array_from_lines)

  adapter_write_manifest \
    "$MANIFEST" \
    "cursor" \
    "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    "$files_json" \
    "{\"hooks_events\": $events_json}"

  echo "[cursor-adapter] installed to $PROJECT_ROOT"
}

# ═══ Uninstall ═══
uninstall_cursor() {
  if [ ! -f "$MANIFEST" ]; then
    echo "[cursor-adapter] no manifest found, nothing to uninstall"
    return 0
  fi
  adapter_require_jq "cursor-adapter" || exit 1

  # 1. Remove files listed in manifest
  adapter_remove_manifest_files "$MANIFEST"

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

install_cursor_global() {
  adapter_require_jq "cursor-adapter" || exit 1
  mkdir -p "$GLOBAL_CURSOR_DIR" "$GLOBAL_HOOKS_DIR" "$GLOBAL_COMMANDS_DIR"

  local managed_files=()
  local backups=()
  local h f tmp files_json events_json backups_json our_hooks_json

  for h in "${MB_HOOKS[@]}"; do
    if [ ! -f "$SKILL_DIR/hooks/$h" ]; then
      echo "[cursor-adapter] missing hook: $SKILL_DIR/hooks/$h" >&2
      exit 1
    fi
    global_install_file "$SKILL_DIR/hooks/$h" "$GLOBAL_HOOKS_DIR/$h" managed_files backups
  done

  for f in "$SKILL_DIR"/commands/*.md; do
    [ -f "$f" ] || continue
    global_install_file "$f" "$GLOBAL_COMMANDS_DIR/$(basename "$f")" managed_files backups
  done

  our_hooks_json=$(cursor_build_hooks_json "$GLOBAL_HOOKS_DIR")
  cursor_merge_hooks_json "$GLOBAL_HOOKS_JSON" "$our_hooks_json"

  if [ -f "$GLOBAL_AGENTS_FILE" ] && grep -q "$CURSOR_START_MARKER" "$GLOBAL_AGENTS_FILE" 2>/dev/null; then
    tmp="$GLOBAL_AGENTS_FILE.tmp"
    awk -v s="$CURSOR_START_MARKER" -v e="$CURSOR_END_MARKER" '
      BEGIN { inside=0 }
      index($0, s) { inside=1; next }
      index($0, e) { inside=0; next }
      !inside { print }
    ' "$GLOBAL_AGENTS_FILE" > "$tmp"
    {
      cat "$tmp"
      printf '\n'
      global_cursor_agents_section
    } > "$GLOBAL_AGENTS_FILE"
    rm -f "$tmp"
  elif [ -f "$GLOBAL_AGENTS_FILE" ]; then
    {
      printf '\n'
      global_cursor_agents_section
    } >> "$GLOBAL_AGENTS_FILE"
  else
    global_cursor_agents_section > "$GLOBAL_AGENTS_FILE"
  fi
  localize_file_with_language "$GLOBAL_AGENTS_FILE" "$CURSOR_START_MARKER"

  tmp="$(mktemp)"
  {
    cat <<'EOF'
# Memory Bank — User Rules (paste into Cursor → Settings → Rules → User Rules)

> This content mirrors the global Memory Bank skill at `~/.cursor/skills/memory-bank/`.
> Cursor does not expose a file API for global User Rules, so paste this block manually
> into Settings → Rules → User Rules once per machine.

EOF
    cat "$SKILL_DIR/rules/CLAUDE-GLOBAL.md"
  } > "$tmp"
  localize_file_with_language "$tmp"
  if [ -f "$GLOBAL_USER_RULES_FILE" ] && cmp -s "$tmp" "$GLOBAL_USER_RULES_FILE"; then
    rm -f "$tmp"
  else
    global_backup_if_exists "$GLOBAL_USER_RULES_FILE" backups
    mv "$tmp" "$GLOBAL_USER_RULES_FILE"
  fi

  files_json=$(printf '%s\n' ${managed_files[@]+"${managed_files[@]}"} | adapter_json_array_from_lines)
  events_json=$(printf '%s\n' "${EVENT_BINDINGS[@]}" | awk -F: '{print $1}' | adapter_json_array_from_lines)
  backups_json=$(printf '%s\n' ${backups[@]+"${backups[@]}"} | adapter_json_array_from_lines)

  adapter_write_manifest \
    "$GLOBAL_MANIFEST" \
    "cursor-global" \
    "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    "$files_json" \
    "{\"scope\": \"global\", \"hooks_events\": $events_json, \"backups\": $backups_json}"

  echo "[cursor-adapter] global install completed"
}

uninstall_cursor_global() {
  if [ ! -f "$GLOBAL_MANIFEST" ]; then
    echo "[cursor-adapter] no global manifest found, nothing to uninstall"
    return 0
  fi
  adapter_require_jq "cursor-adapter" || exit 1

  adapter_remove_manifest_files "$GLOBAL_MANIFEST"

  if [ -f "$GLOBAL_HOOKS_JSON" ]; then
    local events cleaned evt remaining
    events=$(jq -r '.hooks_events[]?' "$GLOBAL_MANIFEST")
    cleaned="$GLOBAL_HOOKS_JSON.tmp"
    cp "$GLOBAL_HOOKS_JSON" "$cleaned"
    while IFS= read -r evt; do
      [ -z "$evt" ] && continue
      jq --arg e "$evt" '
        .hooks[$e] = ((.hooks[$e] // []) | map(select((._mb_owned // false) | not)))
        | if (.hooks[$e] | length) == 0 then del(.hooks[$e]) else . end
      ' "$cleaned" > "$cleaned.2" && mv "$cleaned.2" "$cleaned"
    done <<< "$events"
    remaining=$(jq '.hooks | length' "$cleaned")
    if [ "$remaining" -eq 0 ]; then
      rm -f "$GLOBAL_HOOKS_JSON" "$cleaned"
    else
      mv "$cleaned" "$GLOBAL_HOOKS_JSON"
    fi
  fi

  [ -f "$GLOBAL_AGENTS_FILE" ] && grep -q "$CURSOR_START_MARKER" "$GLOBAL_AGENTS_FILE" 2>/dev/null && run_texttool strip-between-markers --path "$GLOBAL_AGENTS_FILE" --start-marker "$CURSOR_START_MARKER" --end-marker "$CURSOR_END_MARKER" 2>/dev/null || true

  [ -f "$GLOBAL_USER_RULES_FILE" ] && rm -f "$GLOBAL_USER_RULES_FILE"

  local bp orig bak
  while IFS= read -r bp; do
    [ -n "$bp" ] || continue
    echo "$bp" | grep -q '|' || continue
    orig="${bp%%|*}"
    bak="${bp##*|}"
    if [ -e "$bak" ] || [ -L "$bak" ]; then
      mv "$bak" "$orig"
    fi
  done < <(jq -r '.backups[]?' "$GLOBAL_MANIFEST")

  rm -f "$GLOBAL_MANIFEST"
  rmdir "$GLOBAL_HOOKS_DIR" 2>/dev/null || true
  rmdir "$GLOBAL_COMMANDS_DIR" 2>/dev/null || true
  rmdir "$GLOBAL_CURSOR_DIR" 2>/dev/null || true

  echo "[cursor-adapter] global uninstall completed"
}

case "$ACTION" in
  install)   install_cursor ;;
  uninstall) uninstall_cursor ;;
  install-global) install_cursor_global ;;
  uninstall-global) uninstall_cursor_global ;;
  *)
    echo "Usage: $0 install|uninstall [PROJECT_ROOT] | install-global|uninstall-global" >&2
    exit 1
    ;;
esac

adapter_contract_require_functions install_cursor uninstall_cursor >/dev/null
