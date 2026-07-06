#!/usr/bin/env bash
# Shared skill-root resolver for Memory Bank hook scripts.
# Used by hooks that need bundled scripts/ or global bank registry lookup.

# Print candidate skill roots (best first), one per line.
mb_skill_root_candidates() {
  local hook_dir="${1:-}"

  if [ -n "${MB_SKILL_ROOT:-}" ] && [ -d "$MB_SKILL_ROOT" ]; then
    (cd "$MB_SKILL_ROOT" && pwd)
  fi

  if [ -n "$hook_dir" ] && [ -d "$hook_dir" ]; then
    local parent
    parent="$(cd "$hook_dir/.." && pwd)"
    if [ -f "$parent/SKILL.md" ] || [ -f "$parent/VERSION" ]; then
      printf '%s\n' "$parent"
    fi
  fi

  local candidate real
  for candidate in \
    "$HOME/.cursor/skills/memory-bank" \
    "$HOME/.claude/skills/memory-bank" \
    "$HOME/.claude/skills/skill-memory-bank" \
    "$HOME/.codex/skills/memory-bank"; do
    if [ -d "$candidate" ]; then
      real="$(cd "$candidate" && pwd -P 2>/dev/null || cd "$candidate" && pwd)"
      printf '%s\n' "$real"
    fi
  done
}

# Resolve the best skill root for the calling hook.
mb_skill_root_resolve() {
  local hook_dir="${1:-}"
  local root
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    printf '%s' "$root"
    return 0
  done <<EOF
$(mb_skill_root_candidates "$hook_dir")
EOF
  return 1
}

# Print absolute path to scripts/ or empty when unavailable.
mb_skill_scripts_dir() {
  local hook_dir="${1:-}"
  local root scripts
  root="$(mb_skill_root_resolve "$hook_dir")"
  [ -n "$root" ] || return 1
  scripts="$root/scripts"
  [ -d "$scripts" ] && printf '%s' "$scripts"
}

# Print absolute path to scripts/_lib.sh or empty.
mb_skill_lib_sh() {
  local hook_dir="${1:-}"
  local scripts lib
  scripts="$(mb_skill_scripts_dir "$hook_dir")" || return 1
  lib="$scripts/_lib.sh"
  [ -f "$lib" ] && printf '%s' "$lib"
}

# Print absolute path to a bundled script by basename or empty.
mb_skill_script_path() {
  local script_name="$1"
  local hook_dir="${2:-}"
  local scripts path
  scripts="$(mb_skill_scripts_dir "$hook_dir")" || return 1
  path="$scripts/$script_name"
  [ -f "$path" ] && printf '%s' "$path"
}

# Default Memory Bank agent for registry lookup when MB_AGENT is unset.
mb_hook_default_agent() {
  if [ -n "${MB_AGENT:-}" ]; then
    printf '%s' "$MB_AGENT"
    return 0
  fi
  if [ -d "$HOME/.cursor/skills/memory-bank" ]; then
    printf '%s' "cursor"
    return 0
  fi
  printf '%s' "claude-code"
}

# Resolve effective Memory Bank directory for hook context.
# Prints path on success; returns 1 when no bank is found.
mb_hook_resolve_mb_path() {
  local cwd="${1:-$PWD}"
  local agent lib hit hook_dir

  if [ -n "${MB_PATH:-}" ]; then
    printf '%s' "$MB_PATH"
    return 0
  fi

  if [ -d "$cwd/.memory-bank" ]; then
    printf '%s' "$cwd/.memory-bank"
    return 0
  fi

  agent="$(mb_hook_default_agent)"
  hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  lib="$(mb_skill_lib_sh "$hook_dir" 2>/dev/null || true)"
  if [ -n "$lib" ] && [ -f "$lib" ]; then
    hit=$(
      # shellcheck source=/dev/null
      . "$lib" >/dev/null 2>&1 || exit 0
      mb_registry_lookup "$agent" "${MB_PROJECT_ROOT:-$cwd}" 2>/dev/null || true
    )
    if [ -n "$hit" ] && [ -d "$hit" ]; then
      printf '%s' "$hit"
      return 0
    fi
  fi

  return 1
}
