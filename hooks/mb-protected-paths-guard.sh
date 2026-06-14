#!/usr/bin/env bash
# mb-protected-paths-guard.sh — PreToolUse hook for Write/Edit.
#
# Escalates writes to paths matching pipeline.yaml:protected_paths globs to an
# explicit user confirmation (permissionDecision "ask") instead of hard-denying.
# Rationale (G13, 2026-06-13): a hard deny is intent-blind — sanctioned work on
# .env/Dockerfile/etc. was forced into `bash cat >` workarounds, which silently
# disables ALL Write/Edit hooks. An "ask" keeps the human in the loop while
# keeping the safe Write/Edit path (and every other hook) active.
#
# Modes:
#   default                 → protected path => permissionDecision "ask" + reason
#   MB_ALLOW_PROTECTED=1    → allow silently (mirrors /mb work --allow-protected)
#   MB_PROTECTED_MODE=deny  → legacy hard block (exit 2) for unattended runs
#
# Exit codes:
#   0  allow / ask (decision carried in stdout JSON)
#   2  hard block (only when MB_PROTECTED_MODE=deny)

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

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=hooks/_skill_root.sh
. "$HOOK_DIR/_skill_root.sh"
CHECKER="$(mb_skill_script_path "mb-work-protected-check.sh" "$HOOK_DIR" || true)"

if [ -z "$CHECKER" ] || [ ! -f "$CHECKER" ]; then
  # Cannot verify; fail open (do not block on infrastructure error)
  exit 0
fi

if bash "$CHECKER" "$FILE_PATH" >/dev/null 2>&1; then
  exit 0
fi

# Path IS protected. Legacy hard-deny only when explicitly requested
# (e.g. unattended/CI runs where no human can answer an "ask").
if [ "${MB_PROTECTED_MODE:-ask}" = "deny" ]; then
  bash "$CHECKER" "$FILE_PATH" 2>&1 >/dev/null | sed 's/^/[protected-paths-guard] /' >&2
  echo "[protected-paths-guard] BLOCKED: '$FILE_PATH' is in pipeline.yaml:protected_paths." >&2
  echo "[protected-paths-guard] Set MB_ALLOW_PROTECTED=1 to override (or pass --allow-protected to /mb work)." >&2
  exit 2
fi

# Default: escalate to the user with a reason instead of denying. The agent's
# Write/Edit proceeds only after explicit human approval in the UI.
DETAIL="$(bash "$CHECKER" "$FILE_PATH" 2>&1 >/dev/null | head -3 | tr '\n' ' ' || true)"
jq -cn --arg path "$FILE_PATH" --arg detail "$DETAIL" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: ("Protected path (pipeline.yaml:protected_paths): " + $path + (if $detail != "" then " — " + $detail else "" end) + ". Approve to write via the normal hooked path; deny to keep it untouched.")
  }
}'
exit 0
