#!/usr/bin/env bash
# mb-checklist-autoprune.sh — SessionEnd hook. OPT-IN compaction of a checklist.md that has
# grown past the line cap (MB_CHECKLIST_CAP_LINES / MB_CHECKLIST_MAX_LINES / `.mb-config`
# `checklist_max_lines=` / 100). Off by default: the compaction mutates user data, so it
# stays opt-in even though it is non-destructive (done blocks move verbatim into
# progress.md and a `.bak` is written first). Set MB_CHECKLIST_AUTOPRUNE=on to enable.
#
# Fail-safe: any missing dependency / unresolved bank / prune error → exit 0. Runs under a
# lock so a concurrent SessionEnd can't double-apply. Never runs while the env is unset.
set -u

[ "${MB_CHECKLIST_AUTOPRUNE:-off}" = "on" ] || exit 0

HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
# shellcheck source=lib/session-common.sh
. "$HOOK_DIR/lib/session-common.sh"

MB="$(sc_resolve_mb "${CLAUDE_PROJECT_DIR:-$PWD}")"
[ -n "$MB" ] || exit 0
CHECKLIST="$MB/checklist.md"
[ -f "$CHECKLIST" ] || exit 0

# Same cap resolution as mb-checklist-prune.sh, plus the hook's own legacy env name.
cap="${MB_CHECKLIST_CAP_LINES:-${MB_CHECKLIST_MAX_LINES:-}}"
if [ -z "$cap" ] && [ -f "$MB/.mb-config" ] && [ ! -L "$MB/.mb-config" ]; then
  cap="$(grep -E '^checklist_max_lines=' "$MB/.mb-config" 2>/dev/null | tail -1 | cut -d= -f2- || true)"
fi
case "$cap" in ''|*[!0-9]*) cap=100 ;; esac
lines="$(wc -l < "$CHECKLIST" 2>/dev/null | tr -d ' ')"
case "$lines" in ''|*[!0-9]*) exit 0 ;; esac
[ "$lines" -gt "$cap" ] || exit 0

# locate the prune script (repo layout OR installed skill layout)
PRUNE="$HOOK_DIR/../scripts/mb-checklist-prune.sh"
[ -f "$PRUNE" ] || PRUNE="$HOME/.claude/skills/memory-bank/scripts/mb-checklist-prune.sh"
[ -f "$PRUNE" ] || exit 0

LOCK="$MB/.checklist-autoprune.lock"
sc_lock "$LOCK" 5 || exit 0
trap 'sc_unlock "$LOCK"' EXIT INT TERM
bash "$PRUNE" --apply --mb "$MB" >/dev/null 2>&1 || true
exit 0
