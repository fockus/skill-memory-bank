#!/usr/bin/env bash
# Shared bank resolution, shell targets and legacy progress/checkpoint transport.
set -euo pipefail
umask 077
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../hooks/lib/session-common.sh
. "$SKILL_DIR/hooks/lib/session-common.sh"
action="$1" cwd="$2" sid="${3:-}"
export MB_AGENT=opencode
if [ "$action" = targets ]; then
  # shellcheck source=../hooks/lib/protected-bash-parse.sh
  . "$SKILL_DIR/hooks/lib/protected-bash-parse.sh"
  extract_write_targets "$(jq -r '.tool_input.command' )"
  exit 0
fi
mb="$(sc_resolve_mb "$cwd")"
[ -n "$mb" ] && [ -d "$mb" ] || exit 0
if [ "$action" = resolve ]; then printf '%s\n' "$mb"; exit 0; fi
if [ "$action" = hint ]; then
  lib="$SKILL_DIR/adapters/_lib_agents_md.sh"
  # shellcheck source=_lib_agents_md.sh
  . "$lib"
  mb_project_blocks_hint "$cwd"
  exit 0
fi
[[ "$sid" =~ ^[a-zA-Z0-9_-]+$ ]] || exit 0
case "$action" in
  idle)
    case "${MB_AUTO_CAPTURE:-auto}" in off|strict) exit 0 ;; esac
    progress="$mb/progress.md"
    [ -f "$progress" ] || exit 0
    marker="oc-${sid:0:8}"
    grep -qF "$marker" "$progress" && exit 0
    printf '\n## %s\n\n### Auto-capture (%s)\n- OpenCode session observed; use /mb update to record decisions and unfinished work.\n' "$(date +%F)" "$marker" >> "$progress"
    ;;
  compact)
    [ -f "$mb/progress.md" ] || exit 0
    marker="opencode-compacting-checkpoint $(date -u +%FT%TZ) session=${sid:0:8}"
    printf '\n<!-- %s -->\n' "$marker" >> "$mb/progress.md"
    printf 'Memory Bank checkpoint: %s\n' "$marker"
    ;;
esac
