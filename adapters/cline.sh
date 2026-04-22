#!/usr/bin/env bash
# adapters/cline.sh — Cline VS Code extension cross-agent adapter.
#
# Cline has native shell-script hooks via .clinerules/hooks/ directory.
# Events: beforeToolExecution, afterToolExecution, onNotification.
# Each hook receives JSON via stdin, stdout/stderr captured with timeout.
#
# Usage:
#   adapters/cline.sh install [PROJECT_ROOT]
#   adapters/cline.sh uninstall [PROJECT_ROOT]

set -euo pipefail

ACTION="${1:-}"
PROJECT_ROOT_RAW="${2:-$(pwd)}"

if [ ! -d "$PROJECT_ROOT_RAW" ]; then
  echo "[cline-adapter] project root not found: $PROJECT_ROOT_RAW" >&2
  exit 1
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT_RAW" && pwd)"

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLINE_DIR="$PROJECT_ROOT/.clinerules"
RULES_FILE="$CLINE_DIR/memory-bank.md"
HOOKS_DIR="$CLINE_DIR/hooks"
MANIFEST="$CLINE_DIR/.mb-manifest.json"

# shellcheck disable=SC1091
. "$(dirname "$0")/_lib_agents_md.sh"
# shellcheck disable=SC1091
. "$(dirname "$0")/_framework.sh"
# shellcheck disable=SC1091
. "$(dirname "$0")/_contract.sh"

# ═══ Hook bodies ═══
before_tool_body() {
  cat <<'HOOK_EOF'
#!/usr/bin/env bash
# Cline beforeToolExecution — block dangerous commands
# memory-bank: managed hook
set -u

INPUT=$(cat 2>/dev/null || true)
command -v jq >/dev/null 2>&1 || exit 0  # degrade gracefully

CMD=$(printf '%s' "$INPUT" | jq -r '.params.command // .command // empty' 2>/dev/null || true)
[ -z "$CMD" ] && exit 0

# Dangerous patterns
case "$CMD" in
  *"rm -rf /"*|*"rm -rf ~"*|*"rm -rf /*"*|*":(){ :|:& };:"*)
    printf '[MB-cline] BLOCKED dangerous command: %s\n' "$CMD" >&2
    exit 2  # non-zero = block
    ;;
  *"curl "*"|"*"bash"*|*"wget "*"|"*"sh"*)
    printf '[MB-cline] WARNING: pipe-to-shell detected: %s\n' "$CMD" >&2
    # warn only, don't block
    ;;
esac
exit 0
HOOK_EOF
}

after_tool_body() {
  cat <<'HOOK_EOF'
#!/usr/bin/env bash
# Cline afterToolExecution — Memory Bank auto-capture (once per session)
# memory-bank: managed hook
set -u

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.workspaceRoot // .cwd // empty' 2>/dev/null || true)
[ -z "$CWD" ] && CWD="$PWD"

MB="$CWD/.memory-bank"
[ -d "$MB" ] || exit 0

case "${MB_AUTO_CAPTURE:-auto}" in
  off|strict) exit 0 ;;
  auto|*)     ;;
esac

PROGRESS="$MB/progress.md"
[ -f "$PROGRESS" ] || exit 0

SID=$(printf '%s' "$INPUT" | jq -r '.sessionId // .conversation_id // "cline-unknown"' 2>/dev/null || echo "cline-unknown")
# Remove cline- prefix if already present to normalize
SID_NORM="${SID#cline-}"
SID_PREFIX=$(printf '%s' "$SID_NORM" | cut -c1-8)
TODAY=$(date +%Y-%m-%d)

# Idempotency: once per session
if grep -q "Auto-capture.*cline-${SID_PREFIX}" "$PROGRESS" 2>/dev/null; then
  exit 0
fi

{
  printf '\n## %s\n\n' "$TODAY"
  printf '### Auto-capture %s (cline-%s)\n' "$TODAY" "$SID_PREFIX"
  printf -- '- Cline session detected via afterToolExecution hook\n'
  printf -- '- Details will be restored on next /mb start\n'
} >> "$PROGRESS"
exit 0
HOOK_EOF
}

on_notification_body() {
  cat <<'HOOK_EOF'
#!/usr/bin/env bash
# Cline onNotification — weekly compact reminder (opt-in)
# memory-bank: managed hook
set -u

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.workspaceRoot // .cwd // empty' 2>/dev/null || true)
[ -z "$CWD" ] && CWD="$PWD"

MB="$CWD/.memory-bank"
[ -d "$MB" ] || exit 0

case "${MB_COMPACT_REMIND:-auto}" in
  off) exit 0 ;;
esac

LAST="$MB/.last-compact"
[ -f "$LAST" ] || exit 0  # opt-in: user must have run /mb compact at least once

# Age check: only remind every 7 days
now=$(date +%s)
last_ts=$(stat -f%m "$LAST" 2>/dev/null || stat -c%Y "$LAST" 2>/dev/null || echo "$now")
age_days=$(( (now - last_ts) / 86400 ))
[ "$age_days" -lt 7 ] && exit 0

printf '[MB-cline] Weekly /mb compact reminder (%d days since last). Run when idle.\n' "$age_days" >&2
exit 0
HOOK_EOF
}

# ═══ Install ═══
install_cline() {
  adapter_require_jq "cline-adapter" || exit 1
  mkdir -p "$CLINE_DIR" "$HOOKS_DIR"

  # 1. Rules file
  {
    echo '---'
    echo 'paths:'
    echo '  - "**"'
    echo '---'
    echo ''
    echo '# Memory Bank — Project Rules'
    echo ''
    echo 'This project uses Memory Bank for long-term memory + dev workflow.'
    echo ''
    echo '**Workflow:**'
    echo '- Start of session: read `.memory-bank/status.md`, `checklist.md`, `roadmap.md`, `research.md`'
    echo '- Update `checklist.md` immediately (⬜ → ✅) when tasks done'
    echo '- Before context window fill: manual actualize'
    echo ''
    if [ -f "$SKILL_DIR/rules/RULES.md" ]; then
      echo '---'
      echo ''
      echo '# Global Rules'
      echo ''
      mb_emit_rules_file "$SKILL_DIR/rules/RULES.md"
    fi
  } > "$RULES_FILE"

  # 2. Hook scripts
  before_tool_body > "$HOOKS_DIR/before-tool.sh"
  after_tool_body  > "$HOOKS_DIR/after-tool.sh"
  on_notification_body > "$HOOKS_DIR/on-notification.sh"
  chmod +x "$HOOKS_DIR"/*.sh

  # 3. Manifest
  local files_json events_json
  files_json=$(printf '%s\n' \
    "$RULES_FILE" \
    "$HOOKS_DIR/before-tool.sh" \
    "$HOOKS_DIR/after-tool.sh" \
    "$HOOKS_DIR/on-notification.sh" | adapter_json_array_from_lines)
  events_json=$(jq -n '["beforeToolExecution","afterToolExecution","onNotification"]')

  adapter_write_manifest \
    "$MANIFEST" \
    "cline" \
    "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    "$files_json" \
    "{\"hooks_events\": $events_json}"

  echo "[cline-adapter] installed to $PROJECT_ROOT"
}

# ═══ Uninstall ═══
uninstall_cline() {
  if [ ! -f "$MANIFEST" ]; then
    echo "[cline-adapter] no manifest found, nothing to uninstall"
    return 0
  fi
  adapter_require_jq "cline-adapter" || exit 1

  adapter_remove_manifest_files "$MANIFEST"

  rm -f "$MANIFEST"

  # Clean empty dirs
  rmdir "$HOOKS_DIR" 2>/dev/null || true
  rmdir "$CLINE_DIR" 2>/dev/null || true

  echo "[cline-adapter] uninstalled from $PROJECT_ROOT"
}

case "$ACTION" in
  install)   install_cline ;;
  uninstall) uninstall_cline ;;
  *)
    echo "Usage: $0 install|uninstall [PROJECT_ROOT]" >&2
    exit 1
    ;;
esac

adapter_contract_require_functions install_cline uninstall_cline >/dev/null
