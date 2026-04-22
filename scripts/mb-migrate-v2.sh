#!/usr/bin/env bash
# mb-migrate-v2.sh — one-shot v1 → v2 migrator for .memory-bank/
#
# Renames STATUS/BACKLOG/RESEARCH/plan → lowercase status/backlog/research/roadmap,
# transforms plan.md → roadmap.md content structure, fixes references,
# creates a timestamped backup.
#
# Usage: mb-migrate-v2.sh [--dry-run|--apply] [mb_path]

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

MODE="dry-run"
MB_ARG=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry-run" ;;
    --apply)   MODE="apply" ;;
    --*)
      echo "[error] unknown flag: $arg" >&2
      echo "Usage: mb-migrate-v2.sh [--dry-run|--apply] [mb_path]" >&2
      exit 1
      ;;
    *) MB_ARG="$arg" ;;
  esac
done

MB_PATH=$(mb_resolve_path "$MB_ARG")
[ -d "$MB_PATH" ] || { echo "[error] .memory-bank not found at: $MB_PATH" >&2; exit 1; }
MB_PATH=$(cd "$MB_PATH" && pwd)

# === Detection ===
# Using parallel arrays (bash 3.2 compatible — macOS default shell).
RENAMES_OLD=("STATUS.md" "BACKLOG.md" "RESEARCH.md" "plan.md")
RENAMES_NEW=("status.md" "backlog.md" "research.md" "roadmap.md")

# NOTE: plain -f tests are unreliable on macOS default APFS (case-insensitive):
# STATUS.md and status.md resolve to the same inode, so `[ -f status.md ]` would
# return true just because STATUS.md exists. Use case-sensitive `find -name` to
# check whether a distinct v2 file is already present.
planned_renames=()
for i in "${!RENAMES_OLD[@]}"; do
  old="${RENAMES_OLD[$i]}"
  new="${RENAMES_NEW[$i]}"
  old_hit=$(find "$MB_PATH" -maxdepth 1 -type f -name "$old" -print -quit 2>/dev/null || true)
  new_hit=$(find "$MB_PATH" -maxdepth 1 -type f -name "$new" -print -quit 2>/dev/null || true)
  if [ -n "$old_hit" ] && [ -z "$new_hit" ]; then
    planned_renames+=("$old → $new")
  fi
done

if [ "${#planned_renames[@]}" -eq 0 ]; then
  echo "[ok] no v1 files detected — nothing to migrate"
  exit 0
fi

echo "[detected] v1 layout — planned renames:"
for r in "${planned_renames[@]}"; do
  echo "  - $r"
done

if [ "$MODE" = "dry-run" ]; then
  echo "[dry-run] no files changed — run with --apply to execute"
  exit 0
fi

# === Apply (stub until Task 4+) ===
echo "[error] --apply not yet implemented" >&2
exit 2
