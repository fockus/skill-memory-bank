#!/usr/bin/env bash
# adapters/_lib_agents_md.sh — shared AGENTS.md management library.
#
# AGENTS.md is the shared-format instructions file used by OpenCode, Codex,
# and Pi Code (fallback). Cline also auto-reads it. Multiple MB adapters may
# install simultaneously — this library coordinates ownership via a refcount
# file .mb-agents-owners.json in the project root.
#
# Design:
#   - Single shared MB section between <!-- memory-bank:start/end --> markers
#   - .mb-agents-owners.json tracks which clients currently reference the section
#   - First installer (empty owners list) becomes responsible for file creation;
#     we record initial_had_user_content to decide uninstall behavior
#   - Uninstall decrements owners; when list empty → remove section (and file,
#     if initial_had_user_content == false)
#
# Usage (source into adapter):
#   . "$(dirname "$0")/_lib_agents_md.sh"
#   agents_md_install  <project_root> <client_name> <skill_dir>
#   agents_md_uninstall <project_root> <client_name>

MB_START_MARKER="<!-- memory-bank:start -->"
MB_END_MARKER="<!-- memory-bank:end -->"

_owners_require_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo "[agents-md] jq required" >&2
    return 1
  }
}

mb_preferred_language() {
  local lang="${MB_LANGUAGE:-${LANGUAGE:-en}}"
  case "$lang" in
    en|ru) printf '%s' "$lang" ;;
    *) printf '%s' "en" ;;
  esac
}

mb_emit_rules_file() {
  local rules_file="$1"
  local lang
  lang="$(mb_preferred_language)"

  if [ ! -f "$rules_file" ]; then
    return 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    cat "$rules_file"
    return 0
  fi

  TARGET_RULES_FILE="$rules_file" \
  MB_RULE_LANGUAGE="$lang" \
  python3 <<'PYEOF'
from pathlib import Path
import os
import re
import sys

path = Path(os.environ["TARGET_RULES_FILE"])
text = path.read_text()
lang = os.environ["MB_RULE_LANGUAGE"]

if lang == "ru":
    replacement = "1. **Language**: Russian — responses and code comments. Technical terms may remain in English."
else:
    replacement = "1. **Language**: English — responses and code comments. Technical terms may remain in English."

text = re.sub(
    r"1\. \*\*[^*]+\*\*: .+",
    replacement,
    text,
)
sys.stdout.write(text)
PYEOF
}

# ───────── Build section content ─────────
_agents_md_section() {
  local skill_dir="$1"
  echo "$MB_START_MARKER"
  echo ''
  echo '# Memory Bank — Project Rules'
  echo ''
  echo 'This project uses Memory Bank for long-term memory + dev workflow.'
  echo ''
  echo '**Workflow:**'
  # shellcheck disable=SC2016
  echo '- Start of session: read `.memory-bank/STATUS.md`, `checklist.md`, `plan.md`, `RESEARCH.md`'
  # shellcheck disable=SC2016
  echo '- Update `checklist.md` immediately (⬜ → ✅) when tasks done'
  echo '- Before context window fill: manual actualize'
  echo ''
  if [ -f "$skill_dir/rules/RULES.md" ]; then
    echo '---'
    echo ''
    echo '## Global Rules'
    echo ''
    mb_emit_rules_file "$skill_dir/rules/RULES.md"
    echo ''
  fi
  echo "$MB_END_MARKER"
}

# ───────── Owners refcount helpers ─────────
_owners_file() { echo "$1/.mb-agents-owners.json"; }

_owners_read() {
  local f
  _owners_require_jq || return 1
  f=$(_owners_file "$1")
  if [ -f "$f" ]; then
    cat "$f"
  else
    jq -n '{owners: [], initial_had_user_content: false}'
  fi
}

_owners_write() {
  local pr="$1" data="$2"
  local target tmp
  _owners_require_jq || return 1
  target=$(_owners_file "$pr")
  tmp=$(mktemp "$target.XXXXXX.tmp")
  printf '%s\n' "$data" > "$tmp"
  mv "$tmp" "$target"
}

# ───────── Install ─────────
# Ensures our MB section exists in AGENTS.md, registers client in owners list.
# Writes to stdout: "true" if this install created the file, "false" if user file existed.
agents_md_install() {
  local project_root="$1"
  local client="$2"
  local skill_dir="$3"
  local agents_md="$project_root/AGENTS.md"

  local owners
  owners=$(_owners_read "$project_root")

  local created_by_us=false
  if [ ! -f "$agents_md" ]; then
    # First install ever — we create the file
    created_by_us=true
    _agents_md_section "$skill_dir" > "$agents_md"
    owners=$(echo "$owners" | jq '.initial_had_user_content = false')
  elif ! grep -q "$MB_START_MARKER" "$agents_md"; then
    # File exists (user content) but no MB section yet — append
    {
      echo ''
      _agents_md_section "$skill_dir"
    } >> "$agents_md"
    owners=$(echo "$owners" | jq '.initial_had_user_content = true')
  else
    # Section already present from another MB adapter — replace with fresh content
    local tmp="$agents_md.tmp"
    awk -v s="$MB_START_MARKER" -v e="$MB_END_MARKER" '
      BEGIN { inside=0 }
      index($0, s) { inside=1; next }
      index($0, e) { inside=0; next }
      !inside { print }
    ' "$agents_md" > "$tmp"
    {
      cat "$tmp"
      echo ''
      _agents_md_section "$skill_dir"
    } > "$agents_md"
    rm -f "$tmp"
  fi

  # Add client to owners (dedupe)
  owners=$(echo "$owners" | jq --arg c "$client" '.owners = ((.owners // []) - [$c] + [$c])')
  _owners_write "$project_root" "$owners"

  echo "$created_by_us"
}

# ───────── Uninstall ─────────
# Removes client from owners. If owners becomes empty: remove section (and file
# if initial_had_user_content == false).
agents_md_uninstall() {
  local project_root="$1"
  local client="$2"
  local agents_md="$project_root/AGENTS.md"
  local owners_file
  owners_file=$(_owners_file "$project_root")

  # Nothing to do if no owners file
  [ -f "$owners_file" ] || return 0

  local owners
  owners=$(cat "$owners_file")
  owners=$(echo "$owners" | jq --arg c "$client" '.owners = ((.owners // []) - [$c])')
  local remaining
  remaining=$(echo "$owners" | jq '.owners | length')

  if [ "$remaining" -gt 0 ]; then
    # Other MB adapters still installed — keep section, just update refcount
    _owners_write "$project_root" "$owners"
    return 0
  fi

  # No more MB adapters — remove section
  local had_user
  had_user=$(echo "$owners" | jq -r '.initial_had_user_content')

  if [ -f "$agents_md" ]; then
    if [ "$had_user" = "true" ]; then
      # Strip our section, preserve user content
      local tmp="$agents_md.tmp"
      awk -v s="$MB_START_MARKER" -v e="$MB_END_MARKER" '
        BEGIN { inside=0 }
        index($0, s) { inside=1; next }
        index($0, e) { inside=0; next }
        !inside { print }
      ' "$agents_md" > "$tmp"
      # Remove file if fully empty
      if ! grep -q '[^[:space:]]' "$tmp" 2>/dev/null; then
        rm -f "$agents_md"
      else
        mv "$tmp" "$agents_md"
      fi
      rm -f "$tmp"
    else
      # We created the file — remove entirely
      rm -f "$agents_md"
    fi
  fi

  rm -f "$owners_file"
}
