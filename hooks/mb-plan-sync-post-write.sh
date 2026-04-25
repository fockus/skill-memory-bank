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

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

# Match plans/ or specs/ markdown files anywhere in the path
case "$FILE_PATH" in
  *plans/*.md|*specs/*.md)
    ;;
  *)
    echo "[plan-sync-post-write] skipping: $FILE_PATH not under plans/ or specs/" >&2
    exit 0
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../scripts"

run_chain_step() {
  local script="$1"
  local path="$SCRIPTS/$script"
  if [ ! -f "$path" ]; then
    echo "[plan-sync-post-write] skip: $script (not installed)" >&2
    return 0
  fi
  if ! bash "$path" >/dev/null 2>&1; then
    echo "[plan-sync-post-write] warn: $script failed (best-effort)" >&2
  fi
}

echo "[plan-sync-post-write] running chain for $FILE_PATH" >&2
run_chain_step "mb-plan-sync.sh"
run_chain_step "mb-roadmap-sync.sh"
run_chain_step "mb-traceability-gen.sh"
exit 0
