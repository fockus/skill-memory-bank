#!/usr/bin/env bash
# adapters/claude-code.sh — install/repair Claude Code session-memory hooks.
# Ensures the canonical hook scripts from the Memory Bank skill are wired into
# the Claude Code settings.json. Handles missing catchup, precompact, and
# legacy auto-capture cleanup.
#
# Usage:
#   adapters/claude-code.sh install   — write/repair hooks in ~/.claude/settings.json
#   adapters/claude-code.sh doctor    — report what's installed vs what's needed
#   adapters/claude-code.sh uninstall — remove MB-owned session hooks

set -eo pipefail

ACTION="${1:-doctor}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$SKILL_DIR/hooks"
SETTINGS="$HOME/.claude/settings.json"

# Required session-memory hooks: name event
SESSION_HOOK_LIST=(
  "mb-session-start.sh SessionStart"
  "mb-session-end.sh SessionEnd"
  "mb-session-turn.sh Stop"
  "mb-session-catchup.sh SessionStart"
  "mb-pre-compact.sh PreCompact"
  "mb-semantic-recall.sh UserPromptSubmit"
)

# Legacy hook that should NOT be active
LEGACY_HOOK="session-end-autosave.sh"

doctor() {
  echo "=== Claude Code session-memory doctor ==="
  echo "  hooks dir: $HOOKS_DIR"
  echo "  settings:  $SETTINGS"
  echo ""

  local ok=true

  for entry in "${SESSION_HOOK_LIST[@]}"; do
    hook="${entry%% *}"
    event="${entry#* }"
    if [ -f "$HOOKS_DIR/$hook" ]; then
      echo "  [OK]  $hook (in skill, event=$event)"
    else
      echo "  [MISS] $hook (not found in skill hooks)"
      ok=false
    fi
  done

  echo ""

  if [ -f "$SETTINGS" ]; then
    if grep -q "$LEGACY_HOOK" "$SETTINGS" 2>/dev/null; then
      echo "  [WARN] legacy $LEGACY_HOOK is active in settings.json — set MB_AUTO_CAPTURE=off or remove"
      ok=false
    fi

    if grep -q 'mb-session-start.sh' "$SETTINGS" 2>/dev/null && ! grep -q 'mb-session-catchup.sh' "$SETTINGS" 2>/dev/null; then
      echo "  [WARN] SessionStart has start hook but no catchup hook — sessions left summarized:false won't be caught up"
      ok=false
    fi

    if ! grep -q 'mb-pre-compact.sh' "$SETTINGS" 2>/dev/null; then
      echo "  [WARN] PreCompact hook missing — no handoff capsule on compaction"
      ok=false
    fi
  else
    echo "  [MISS] $SETTINGS not found"
    ok=false
  fi

  if $ok; then
    echo ""
    echo "  ✓ Claude Code session-memory hooks: healthy"
  fi
}

install() {
  echo "=== Claude Code session-memory install ==="
  doctor
  echo ""
  echo "To repair, manually add these hook entries to $SETTINGS:"
  echo ""
  echo '  "SessionStart": ['
  echo '    {"command": "bash '"$HOOKS_DIR"'/mb-session-catchup.sh"},'
  echo '    {"command": "bash '"$HOOKS_DIR"'/mb-session-start.sh"}'
  echo '  ],'
  echo '  "Stop": ['
  echo '    {"command": "bash '"$HOOKS_DIR"'/mb-session-turn.sh"}'
  echo '  ],'
  echo '  "SessionEnd": ['
  echo '    {"command": "bash '"$HOOKS_DIR"'/mb-session-end.sh"}'
  echo '  ],'
  echo '  "PreCompact": ['
  echo '    {"command": "bash '"$HOOKS_DIR"'/mb-pre-compact.sh"}'
  echo '  ],'
  echo '  "UserPromptSubmit": ['
  echo '    {"command": "bash '"$HOOKS_DIR"'/mb-semantic-recall.sh"}'
  echo '  ]'
  echo ""
  echo "To disable legacy auto-capture, remove '$LEGACY_HOOK' from SessionEnd."
}

uninstall() {
  echo "To remove Claude Code session-memory hooks, edit $SETTINGS"
  echo "and remove entries pointing to $HOOKS_DIR"
}

case "$ACTION" in
  doctor) doctor ;;
  install) install ;;
  uninstall) uninstall ;;
  *) echo "Usage: $0 {doctor|install|uninstall}" >&2; exit 1 ;;
esac
