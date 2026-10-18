#!/usr/bin/env bash
# mb-plan-sync-post-write.sh — PostToolUse hook for Write tool.
#
# When a file under .memory-bank/plans/**.md or .memory-bank/specs/**.md is
# written, kick off the deterministic chain that keeps the bank consistent:
#   mb-plan-sync.sh → mb-roadmap-sync.sh → mb-traceability-gen.sh
#
# Each step is best-effort: missing scripts are skipped, non-zero exits log
# warnings but never block. The hook always exits 0 (PostToolUse must not
# block downstream behavior).

set -eu

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL" = "Write" ] || exit 0

# Native patches may supply a bounded batch; the existing single-path payload stays valid.
FILE_PATHS=$(printf '%s' "$INPUT" | jq -er '
  .tool_input as $i |
  if (($i.file_paths // []) | type) != "array" or (($i.file_paths // []) | length) > 128 then error("invalid paths")
  else ([$i.file_path // empty] + ($i.file_paths // [])) end |
  if all(.[]; if type == "string" then length > 0 and length <= 4096 and (explode | all(. != 0 and . != 10 and . != 13)) else false end)
  then reduce .[] as $p ([]; if index($p) then . else . + [$p] end)
  else error("invalid path") end |
  if length <= 128 then .[] else error("too many paths") end
' 2>/dev/null) || exit 0

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=hooks/_skill_root.sh
. "$HOOK_DIR/_skill_root.sh"
SCRIPTS="$(mb_skill_scripts_dir "$HOOK_DIR" || true)"

run_chain_step() {
  local script="$1"
  shift
  local path="$SCRIPTS/$script"
  if [ -z "$SCRIPTS" ] || [ ! -f "$path" ]; then
    echo "[plan-sync-post-write] skip: $script (not installed)" >&2
    return 0
  fi
  if ! bash "$path" "$@" >/dev/null 2>&1; then
    echo "[plan-sync-post-write] warn: $script failed (best-effort)" >&2
  fi
}

eligible=0
while IFS= read -r FILE_PATH; do
  case "$FILE_PATH" in
    *plans/*.md|*specs/*.md)
      echo "[plan-sync-post-write] running chain for $FILE_PATH" >&2
      MB_PLAN_SYNC_DEFER_FINALIZE=1 run_chain_step "mb-plan-sync.sh" "$FILE_PATH"
      eligible=$((eligible + 1))
      ;;
    *) echo "[plan-sync-post-write] skipping: $FILE_PATH not under plans/ or specs/" >&2 ;;
  esac
done <<< "$FILE_PATHS"
[ "$eligible" -gt 0 ] || exit 0
run_chain_step "mb-roadmap-sync.sh"
run_chain_step "mb-traceability-gen.sh"
exit 0
