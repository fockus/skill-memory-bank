#!/usr/bin/env bash
# mb-protected-paths-guard.sh — PreToolUse hook for Write/Edit/Bash writes.

set -eu

if ! command -v jq >/dev/null 2>&1; then
  echo "[protected-paths-guard] jq required" >&2
  exit 0
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=hooks/lib/protected-bash-parse.sh
. "$HOOK_DIR/lib/protected-bash-parse.sh"
# shellcheck source=hooks/_skill_root.sh
. "$HOOK_DIR/_skill_root.sh"
CHECKER="$(mb_skill_script_path "mb-work-protected-check.sh" "$HOOK_DIR" || true)"

_guard_ask() {
  local path="$1" detail="$2"
  jq -cn --arg path "$path" --arg detail "$detail" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: ("Protected path (pipeline.yaml:protected_paths): " + $path + (if $detail != "" then " — " + $detail else "" end) + ". Approve to write via the normal hooked path; deny to keep it untouched.")
  }
}'
}

_guard_check_path() {
  local path="$1"
  [ -n "$path" ] || return 0
  if [ -z "$CHECKER" ] || [ ! -f "$CHECKER" ]; then
    return 0
  fi
  if bash "$CHECKER" "$path" >/dev/null 2>&1; then
    return 0
  fi
  if [ "${MB_PROTECTED_MODE:-ask}" = "deny" ]; then
    bash "$CHECKER" "$path" 2>&1 >/dev/null | sed 's/^/[protected-paths-guard] /' >&2
    echo "[protected-paths-guard] BLOCKED: '$path' is in pipeline.yaml:protected_paths." >&2
    exit 2
  fi
  DETAIL="$(bash "$CHECKER" "$path" 2>&1 >/dev/null | head -3 | tr '\n' ' ' || true)"
  _guard_ask "$path" "$DETAIL"
  exit 0
}

case "$TOOL" in
  Write|Edit)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    [ -z "$FILE_PATH" ] && exit 0
    if [ "${MB_ALLOW_PROTECTED:-0}" = "1" ]; then
      echo "[protected-paths-guard] MB_ALLOW_PROTECTED=1 — bypassing guard for: $FILE_PATH" >&2
      exit 0
    fi
    _guard_check_path "$FILE_PATH"
    exit 0
    ;;
  Bash)
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    [ -z "$CMD" ] && exit 0
    if [ "${MB_ALLOW_PROTECTED:-0}" = "1" ]; then
      exit 0
    fi
    while IFS= read -r target; do
      [ -z "$target" ] && continue
      _guard_check_path "$target"
    done < <(extract_write_targets "$CMD")
    printf '{}\n'
    exit 0
    ;;
  *) exit 0 ;;
esac
