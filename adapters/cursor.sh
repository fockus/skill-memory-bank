#!/usr/bin/env bash
# adapters/cursor.sh — Cursor IDE adapter for Memory Bank.
#
# Cursor 1.7+ (October 2025) added a Claude-Code-compatible hooks API.
# This adapter writes .cursor/rules/memory-bank.mdc (rules) + .cursor/hooks.json
# (events → bundled skill hooks under ~/.cursor/skills/memory-bank/hooks/ or the
# repo/skill bundle). Hook scripts are NOT copied into .cursor/hooks/ — commands
# reference the canonical skill bundle so bundled scripts/ resolve correctly.
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

# Hook scripts registered from the skill bundle (not copied into .cursor/hooks/)
MB_HOOKS=(
  "session-end-autosave.sh"
  "mb-pre-compact.sh"
  "block-dangerous.sh"
  "mb-protected-paths-guard.sh"
  "mb-ears-pre-write.sh"
  "mb-context-slim-pre-agent.sh"
  "mb-sprint-context-guard.sh"
  "file-change-log.sh"
  "mb-plan-sync-post-write.sh"
  "mb-session-start-context.sh"
)

# Event → script mapping (Cursor event names, CC-compat)
# Format: "event:script[:matcher]"
EVENT_BINDINGS=(
  "sessionStart:mb-session-start-context.sh"
  "sessionEnd:session-end-autosave.sh"
  "preCompact:mb-pre-compact.sh"
  "beforeShellExecution:block-dangerous.sh"
  "preToolUse:mb-protected-paths-guard.sh:Write|Edit"
  "preToolUse:mb-ears-pre-write.sh:Write"
  "preToolUse:mb-context-slim-pre-agent.sh:Task"
  "preToolUse:mb-sprint-context-guard.sh:Task"
  "postToolUse:file-change-log.sh:Write|Edit"
  "postToolUse:mb-plan-sync-post-write.sh:Write"
)

run_texttool() {
  # Use the interpreter that owns the memory_bank_skill package (exported by the
  # CLI as MB_PYTHON). A bare `python3` resolves to whatever is first on PATH —
  # under pipx/pyenv that is NOT the venv holding the package, so the import of
  # memory_bank_skill._texttools fails. Fall back to python3 for git checkouts.
  PYTHONPATH="$SKILL_DIR${PYTHONPATH:+:$PYTHONPATH}" \
    "${MB_PYTHON:-python3}" -m memory_bank_skill._texttools "$@"
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

cursor_binding_events_json() {
  printf '%s\n' "${EVENT_BINDINGS[@]}" | awk -F: '{print $1}' | sort -u | adapter_json_array_from_lines
}

cursor_resolve_skill_hooks_dir() {
  local candidate resolved=""
  for candidate in \
    "$HOME/.cursor/skills/memory-bank/hooks" \
    "$SKILL_DIR/hooks"; do
    if [ -d "$candidate" ]; then
      resolved="$(cd "$candidate" && pwd)"
      printf '%s' "$resolved"
      return 0
    fi
  done
  return 1
}

cursor_hook_env_prefix() {
  local skills_root="$HOME/.cursor/skills"
  if [ ! -d "$skills_root/memory-bank" ]; then
    skills_root="$HOME/.claude/skills"
  fi
  printf 'MB_AGENT=cursor MB_SKILLS_ROOT=%s ' "$skills_root"
}

# Hook names that were registered in previous versions but are no longer current.
# These must be removed from any copy directories on reinstall so stale binaries
# do not shadow the canonical bundled scripts.  Currently includes the
# handoff-v2 rename (mb-compact-reminder.sh → mb-pre-compact.sh).
LEGACY_MB_HOOKS=(
  "mb-compact-reminder.sh"
)

cursor_remove_legacy_hook_copies() {
  local base h
  for base in "$GLOBAL_HOOKS_DIR" "$HOOKS_DIR"; do
    [ -d "$base" ] || continue
    # Remove current hook names (in case old installs left copies here).
    for h in "${MB_HOOKS[@]}"; do
      if [ -f "$base/$h" ]; then
        rm -f "$base/$h"
      fi
    done
    # Remove legacy hook names from old installs.
    for h in "${LEGACY_MB_HOOKS[@]}"; do
      if [ -f "$base/$h" ]; then
        rm -f "$base/$h"
      fi
    done
    rmdir "$base" 2>/dev/null || true
  done
}

cursor_build_hooks_json() {
  local hooks_dir="$1"
  local our_hooks_json binding event rest script matcher cmd entry env_prefix
  env_prefix="$(cursor_hook_env_prefix)"
  our_hooks_json=$(jq -n '{hooks: {}}')
  for binding in "${EVENT_BINDINGS[@]}"; do
    event="${binding%%:*}"
    rest="${binding#*:}"
    script="${rest%%:*}"
    if [[ "$rest" == *:* ]]; then
      matcher="${rest#*:}"
    else
      matcher=""
    fi
    cmd="${env_prefix}bash \"${hooks_dir}/${script}\""
    if [ -n "$matcher" ]; then
      entry=$(jq -n --arg cmd "$cmd" --arg m "$matcher" '{command:$cmd, matcher:$m, _mb_owned:true}')
    else
      entry=$(jq -n --arg cmd "$cmd" '{command:$cmd, _mb_owned:true}')
    fi
    our_hooks_json=$(echo "$our_hooks_json" | jq \
      --arg event "$event" \
      --argjson entry "$entry" \
      '.hooks[$event] += [$entry]')
  done
  printf '%s' "$our_hooks_json"
}

copy_to_clipboard() {
  local file="$1"
  if command -v pbcopy >/dev/null 2>&1; then
    pbcopy < "$file"
    return 0
  fi
  if command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard < "$file"
    return 0
  fi
  if command -v wl-copy >/dev/null 2>&1; then
    wl-copy < "$file"
    return 0
  fi
  return 1
}

prompt_user_rules_install() {
  local rules_file="$1"
  [ -t 0 ] || return 0
  [ "${MB_USER_RULES_AUTO_PROMPT:-on}" = "off" ] && return 0

  echo
  echo "Cursor User Rules — manual paste required (Cursor has no file API)."
  echo "  1) Copy to clipboard + open Cursor (Settings → Rules → Cmd+V) [default]"
  echo "  2) Copy to clipboard only"
  echo "  3) Open file in \$EDITOR"
  echo "  4) Skip"
  read -r -p "Choice [1-4]: " choice
  case "${choice:-1}" in
    1)
      if copy_to_clipboard "$rules_file"; then
        if command -v open >/dev/null 2>&1; then
          open -a Cursor 2>/dev/null || true
        fi
        echo "→ Copied. Open Cursor → Settings → Rules → User Rules → Cmd+V"
      else
        echo "→ Clipboard unavailable. Paste manually from: $rules_file"
      fi
      ;;
    2)
      if copy_to_clipboard "$rules_file"; then
        echo "→ Copied. Settings → Rules → User Rules → Cmd+V"
      else
        echo "→ Clipboard unavailable. Paste manually from: $rules_file"
      fi
      ;;
    3)
      ${EDITOR:-vi} "$rules_file"
      ;;
    4)
      ;;
  esac
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
- Hooks: bundled at \`~/.cursor/skills/memory-bank/hooks/\` wired via \`~/.cursor/hooks.json\`

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
  mkdir -p "$CURSOR_DIR/rules"

  local skill_hooks_dir
  skill_hooks_dir="$(cursor_resolve_skill_hooks_dir)" || {
    echo "[cursor-adapter] cannot resolve skill hooks directory" >&2
    exit 1
  }

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

  # 2. Verify bundled hook scripts exist
  local h
  for h in "${MB_HOOKS[@]}"; do
    if [ ! -f "$skill_hooks_dir/$h" ]; then
      echo "[cursor-adapter] missing hook: $skill_hooks_dir/$h" >&2
      exit 1
    fi
  done

  # 3–4. Build + merge hooks.json (reference skill bundle, not local copies)
  cursor_remove_legacy_hook_copies
  local our_hooks_json
  our_hooks_json=$(cursor_build_hooks_json "$skill_hooks_dir")
  cursor_merge_hooks_json "$HOOKS_JSON" "$our_hooks_json"

  # 5. Manifest (project-owned files + hook metadata)
  local files_json events_json extra_json
  files_json=$(printf '%s\n' "$RULES_FILE" | adapter_json_array_from_lines)
  events_json=$(cursor_binding_events_json)
  extra_json=$(jq -n \
    --argjson events "$events_json" \
    --arg bundle "$skill_hooks_dir" \
    '{hooks_events: $events, hooks_bundle: $bundle}')

  adapter_write_manifest \
    "$MANIFEST" \
    "cursor" \
    "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    "$files_json" \
    "$extra_json"

  echo "[cursor-adapter] installed to $PROJECT_ROOT"
}

# ═══ Uninstall ═══
uninstall_cursor() {
  if [ ! -f "$MANIFEST" ]; then
    echo "[cursor-adapter] no manifest found, nothing to uninstall"
    return 0
  fi
  adapter_require_jq "cursor-adapter" || exit 1

  # 1. Strip our-owned entries from hooks.json before removing project files
  if [ -f "$HOOKS_JSON" ]; then
    local events
    events=$(jq -r '.hooks_events[]?' "$MANIFEST")
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

  # 2. Remove project-owned files from manifest
  adapter_remove_manifest_files "$MANIFEST"

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
  mkdir -p "$GLOBAL_CURSOR_DIR" "$GLOBAL_COMMANDS_DIR"

  local managed_files=()
  local backups=()
  local h f tmp files_json events_json backups_json our_hooks_json skill_hooks_dir

  skill_hooks_dir="$(cursor_resolve_skill_hooks_dir)" || {
    echo "[cursor-adapter] cannot resolve skill hooks directory" >&2
    exit 1
  }
  for h in "${MB_HOOKS[@]}"; do
    if [ ! -f "$skill_hooks_dir/$h" ]; then
      echo "[cursor-adapter] missing hook: $skill_hooks_dir/$h" >&2
      exit 1
    fi
  done
  cursor_remove_legacy_hook_copies

  for f in "$SKILL_DIR"/commands/*.md; do
    [ -f "$f" ] || continue
    global_install_file "$f" "$GLOBAL_COMMANDS_DIR/$(basename "$f")" managed_files backups
  done

  our_hooks_json=$(cursor_build_hooks_json "$skill_hooks_dir")
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

  local mb_version
  mb_version="$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)"
  tmp="$(mktemp)"
  {
    printf '%s\n' "<!-- memory-bank:start v${mb_version} -->"
    cat <<'EOF'
# Memory Bank — User Rules (paste into Cursor → Settings → Rules → User Rules)

> Cursor does not expose a file API for global User Rules.
> Copy this file manually: Settings → Rules → User Rules → paste (Cmd+V).

EOF
    cat "$SKILL_DIR/rules/CLAUDE-GLOBAL.md"
    printf '\n%s\n' "<!-- memory-bank:end -->"
  } > "$tmp"
  localize_file_with_language "$tmp"
  if [ -f "$GLOBAL_USER_RULES_FILE" ] && cmp -s "$tmp" "$GLOBAL_USER_RULES_FILE"; then
    rm -f "$tmp"
  else
    global_backup_if_exists "$GLOBAL_USER_RULES_FILE" backups
    mv "$tmp" "$GLOBAL_USER_RULES_FILE"
  fi

  files_json=$(printf '%s\n' ${managed_files[@]+"${managed_files[@]}"} | adapter_json_array_from_lines)
  events_json=$(cursor_binding_events_json)
  backups_json=$(printf '%s\n' ${backups[@]+"${backups[@]}"} | adapter_json_array_from_lines)
  extra_json=$(jq -n \
    --arg scope "global" \
    --arg lang "${MB_LANGUAGE:-en}" \
    --argjson events "$events_json" \
    --argjson backups "$backups_json" \
    --arg bundle "$skill_hooks_dir" \
    '{scope: $scope, lang: $lang, hooks_events: $events, backups: $backups, hooks_bundle: $bundle}')

  adapter_write_manifest \
    "$GLOBAL_MANIFEST" \
    "cursor-global" \
    "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    "$files_json" \
    "$extra_json"

  echo "[cursor-adapter] global install completed"
  echo "[cursor-adapter] User Rules paste-file: $GLOBAL_USER_RULES_FILE"
  prompt_user_rules_install "$GLOBAL_USER_RULES_FILE"
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
