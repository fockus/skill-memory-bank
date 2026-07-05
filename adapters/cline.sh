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
# Cline supports `.clinerules` as EITHER a directory OR a single file. When it is
# a plain file we can't mkdir it or nest hooks — append a marker-delimited MB
# block and track ownership in a sibling manifest.
CLINE_FILE_MANIFEST="$PROJECT_ROOT/.mb-cline-manifest.json"
CLINE_START_MARKER="<!-- memory-bank-cline:start -->"
CLINE_END_MARKER="<!-- memory-bank-cline:end -->"

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

# Resolve Memory Bank path: MB_PATH env override → local project bank → no-op
if [ -n "${MB_PATH:-}" ]; then
  MB="$MB_PATH"
elif [ -d "$CWD/.memory-bank" ]; then
  MB="$CWD/.memory-bank"
fi
[ -d "${MB:-}" ] || exit 0

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

# Resolve Memory Bank path: MB_PATH env override → local project bank → no-op
if [ -n "${MB_PATH:-}" ]; then
  MB="$MB_PATH"
elif [ -d "$CWD/.memory-bank" ]; then
  MB="$CWD/.memory-bank"
fi
[ -d "${MB:-}" ] || exit 0

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

# Resolve .clinerules through a symlink CHAIN to its real target, so we write
# THROUGH the link(s) (mv onto the final target) instead of replacing a link with
# a regular file and detaching a shared rules file. Bounded loop = cycle-safe.
_cline_real_path() {
  local p="$CLINE_DIR" t hops=0
  while [ -L "$p" ] && [ "$hops" -lt 40 ]; do
    t="$(readlink "$p")"
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
    hops=$((hops + 1))
  done
  printf '%s' "$p"
}

# Back up the real .clinerules target ONCE before any destructive rewrite, so a
# hand-corrupted file is always recoverable (project-wide backup-before-overwrite).
_cline_backup_once() {
  local f="$1" b
  [ -f "$f" ] || return 0
  for b in "$f".pre-mb-backup.*; do [ -f "$b" ] && return 0; done
  cp "$f" "$f.pre-mb-backup.$$" 2>/dev/null || true
}

# Remove the MB block from a file-form .clinerules (idempotency + uninstall).
# True no-op unless a COMPLETE block (BOTH markers) is present — a lone/corrupted
# marker must never trigger a destructive strip-to-EOF. Drops START..END inclusive
# AND the single adapter-owned blank line emitted right before START (1-line delay
# buffer preserves every other line, incl. the user's own trailing blanks).
# Symlink-safe (writes onto the resolved target) + mode-safe.
_cline_strip_block() {
  [ -f "$CLINE_DIR" ] || return 0
  local real
  real="$(_cline_real_path)"
  grep -qF "$CLINE_START_MARKER" "$real" 2>/dev/null || return 0
  grep -qF "$CLINE_END_MARKER" "$real" 2>/dev/null || return 0
  _cline_backup_once "$real"
  local tmp mode
  tmp="$(mktemp "$(dirname "$real")/.clinerules.mbXXXXXX")" || return 1
  mode="$(mb_file_mode "$real")"
  awk -v s="$CLINE_START_MARKER" -v e="$CLINE_END_MARKER" '
    $0==s { if (hasprev && prev!="") print prev; hasprev=0; skip=1; next }
    $0==e { skip=0; next }
    skip  { next }
    { if (hasprev) print prev; prev=$0; hasprev=1 }
    END   { if (hasprev) print prev }
  ' "$real" > "$tmp" || { rm -f "$tmp"; return 1; }
  [ -n "$mode" ] && chmod "$mode" "$tmp" 2>/dev/null
  mv "$tmp" "$real" || { rm -f "$tmp"; return 1; }
}

# File-form install: append a marker-delimited MB rules block. No hooks (a file
# can't host .clinerules/hooks/). Idempotent — strips any prior block first.
install_cline_file_form() {
  _cline_backup_once "$(_cline_real_path)"   # safety net before any rewrite (incl. first install)
  _cline_strip_block
  {
    echo ""
    echo "$CLINE_START_MARKER"
    echo "# Memory Bank — Project Rules"
    echo ""
    # shellcheck disable=SC2016
    echo '- Start of session: read `.memory-bank/status.md`, `checklist.md`, `roadmap.md`, `research.md`'
    # shellcheck disable=SC2016
    echo '- Update `checklist.md` immediately (⬜ → ✅) when tasks done'
    if [ -f "$SKILL_DIR/rules/RULES.md" ]; then
      echo ''
      echo '# Global Rules'
      echo ''
      mb_emit_rules_file "$SKILL_DIR/rules/RULES.md"
    fi
    echo "$CLINE_END_MARKER"
  } >> "$CLINE_DIR"

  adapter_write_manifest \
    "$CLINE_FILE_MANIFEST" \
    "cline" \
    "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    "[]" \
    '{"mode": "file"}'

  echo "[cline-adapter] installed to $PROJECT_ROOT (mode: file .clinerules)"
}

# ═══ Install ═══
install_cline() {
  adapter_require_jq "cline-adapter" || exit 1
  if [ -f "$CLINE_DIR" ]; then
    install_cline_file_form
    return
  fi
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

  # 2. Hook scripts — A16 (M-8): back up a pre-existing (possibly
  # user-modified) hook before overwriting, and write atomically (tmp in the
  # same dir + mv) so a crash mid-write never leaves a truncated hook script
  # that then silently fails on every tool call. Reuses the same
  # backup-once idiom as _cline_strip_block/install_cline_file_form above.
  local hook_name hook_tmp
  for hook_name in before-tool after-tool on-notification; do
    _cline_backup_once "$HOOKS_DIR/$hook_name.sh"
  done
  hook_tmp=$(mktemp "$HOOKS_DIR/.before-tool.sh.XXXXXXXX")
  before_tool_body > "$hook_tmp"
  mv "$hook_tmp" "$HOOKS_DIR/before-tool.sh"
  hook_tmp=$(mktemp "$HOOKS_DIR/.after-tool.sh.XXXXXXXX")
  after_tool_body > "$hook_tmp"
  mv "$hook_tmp" "$HOOKS_DIR/after-tool.sh"
  hook_tmp=$(mktemp "$HOOKS_DIR/.on-notification.sh.XXXXXXXX")
  on_notification_body > "$hook_tmp"
  mv "$hook_tmp" "$HOOKS_DIR/on-notification.sh"
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
  # File-form: strip the MB block, keep the user's file + content.
  if [ -f "$CLINE_FILE_MANIFEST" ]; then
    _cline_strip_block
    rm -f "$CLINE_FILE_MANIFEST"
    echo "[cline-adapter] uninstalled from $PROJECT_ROOT (file .clinerules)"
    return 0
  fi
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
