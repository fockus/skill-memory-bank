#!/usr/bin/env bash
# mb-backlog-migrate.sh — migrate a legacy backlog.md to the C3 machine (design.md C4).
#
# Usage:
#   mb-backlog-migrate.sh [--dry-run|--apply] [mb_path]
#
# --dry-run (default) prints the inventory and writes nothing. --apply backs
# backlog.md up to <bank>/.pre-migrate/<ts>/ and mutates it under
# <bank>/.locks/backlog.lock with an atomic write; a second --apply is a no-op
# (actions_pending=0, no new backup).
#
# Legacy status table: NEW stays; TRIAGED|OPEN|PROPOSED|DEFERRED → TRIAGED;
# PLANNED → IN-PROGRESS; DONE stays; RESOLVED → DONE (extra text preserved);
# DECLINED → WONTFIX and the block moves to `## Out of scope`. A token outside the
# table and the alphabet only warns (unknown_legacy_state). `[SPEC:<group>] <topic>`
# titles become typed SPEC entries. Historical entries never get `**Type:** IDEA`.
#
# Exit: 0 OK, 1 missing backlog.md / lock timeout, 2 usage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

MODE="dry-run"
MB_ARG=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry-run" ;;
    --apply) MODE="apply" ;;
    -h|--help) sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    --*) echo "[error] unknown option: $arg" >&2; exit 2 ;;
    *) if [ -z "$MB_ARG" ]; then MB_ARG="$arg"; else echo "[error] unexpected argument: $arg" >&2; exit 2; fi ;;
  esac
done

MB_PATH=$(mb_resolve_path "$MB_ARG")
BACKLOG="$MB_PATH/backlog.md"
[ -f "$BACKLOG" ] || { echo "[error] backlog.md not found: $BACKLOG" >&2; exit 1; }

run_py() { "${MB_PYTHON:-python3}" "$SCRIPT_DIR/mb_backlog_migrate.py" "$BACKLOG" "$@"; }

if [ "$MODE" = "dry-run" ]; then
  run_py dry-run
  exit 0
fi

LOCK_DIR="$MB_PATH/.locks/backlog.lock"
mkdir -p "$MB_PATH/.locks"
if ! LOCK_TOKEN="$(mb_lock_acquire "$LOCK_DIR" "${MB_BACKLOG_LOCK_TIMEOUT:-10}" "${MB_BACKLOG_LOCK_TTL:-120}")"; then
  echo "[error] could not acquire backlog lock: $LOCK_DIR" >&2
  exit 1
fi
trap 'mb_lock_release "$LOCK_DIR" "$LOCK_TOKEN" >/dev/null 2>&1 || true' EXIT

run_py apply --backup-dir "$MB_PATH/.pre-migrate/$(date +%Y%m%d_%H%M%S)"
