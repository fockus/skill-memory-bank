#!/usr/bin/env bash
# mb-ears-pre-write.sh — PreToolUse hook for Write.
#
# When the target file is `<bank>/specs/<topic>/requirements.md` or
# `<bank>/context/<topic>.md`, validate the candidate content against the EARS
# patterns via mb-ears-validate.sh. Block (exit 2) on validation failure so
# malformed REQ lines never persist.
#
# Exit codes:
#   0  pass (path doesn't match, or content valid, or unrelated tool)
#   2  EARS validation failed — block

set -eu

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL" = "Write" ] || exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

# Match specs/<topic>/requirements.md or context/<topic>.md (any prefix)
case "$FILE_PATH" in
  *specs/*/requirements.md) ;;
  *context/*.md) ;;
  *) exit 0 ;;
esac

CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
if [ -z "$CONTENT" ]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR="$SCRIPT_DIR/../scripts/mb-ears-validate.sh"

if [ ! -f "$VALIDATOR" ]; then
  # Validator missing — fail open (don't block on infrastructure issue)
  exit 0
fi

VALIDATOR_ERR=$(printf '%s' "$CONTENT" | bash "$VALIDATOR" - 2>&1 >/dev/null) && rc=0 || rc=$?
if [ "$rc" -eq 0 ]; then
  exit 0
fi

echo "[ears-pre-write] EARS validation failed for $FILE_PATH:" >&2
printf '%s\n' "$VALIDATOR_ERR" | sed 's/^/[ears-pre-write]   /' >&2
echo "[ears-pre-write] BLOCKED. Fix the REQ lines or run /mb discuss interactively." >&2
exit 2
