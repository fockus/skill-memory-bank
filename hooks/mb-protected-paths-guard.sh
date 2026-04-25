#!/usr/bin/env bash
# mb-protected-paths-guard.sh — PreToolUse hook for Write/Edit.
#
# Blocks writes to paths matching pipeline.yaml:protected_paths globs unless
# `MB_ALLOW_PROTECTED=1` is set in the environment (mirrors `--allow-protected`
# flag from /mb work).
#
# Exit codes:
#   0  allow (path is not protected, or override flag set, or unrelated tool)
#   2  hard block (path is protected and no override)

set -eu

if ! command -v jq >/dev/null 2>&1; then
  echo "[protected-paths-guard] jq required" >&2
  exit 0  # Don't block on missing dep
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only fire on Write / Edit
case "$TOOL" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

if [ "${MB_ALLOW_PROTECTED:-0}" = "1" ]; then
  echo "[protected-paths-guard] MB_ALLOW_PROTECTED=1 — bypassing guard for: $FILE_PATH" >&2
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKER="$SCRIPT_DIR/../scripts/mb-work-protected-check.sh"

if [ ! -f "$CHECKER" ]; then
  # Cannot verify; fail open (do not block on infrastructure error)
  exit 0
fi

if bash "$CHECKER" "$FILE_PATH" >/dev/null 2>&1; then
  exit 0
fi

# Re-run to capture stderr for the user
bash "$CHECKER" "$FILE_PATH" 2>&1 >/dev/null | sed 's/^/[protected-paths-guard] /' >&2
echo "[protected-paths-guard] BLOCKED: '$FILE_PATH' is in pipeline.yaml:protected_paths." >&2
echo "[protected-paths-guard] Set MB_ALLOW_PROTECTED=1 to override (or pass --allow-protected to /mb work)." >&2
exit 2
