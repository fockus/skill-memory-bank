#!/usr/bin/env bash
# mb-init-bank.sh — deterministic locale-aware .memory-bank/ scaffolder
#
# Usage:
#   mb-init-bank.sh [--lang=XX] [--mb-root=PATH]
#
# Creates PROJECT/.memory-bank/ with:
#   - 7 core files copied from templates/locales/<lang>/.memory-bank/
#   - plans/, plans/done/, notes/, reports/, experiments/, codebase/
#   - .mb-config with `lang=<lang>`
#
# Locale resolution (highest → lowest):
#   1. --lang=XX flag
#   2. MB_LANG env var
#   3. existing .mb-config value
#   4. default → en
#
# Safety: never overwrites existing files.
#
# Exit codes:
#   0 — success
#   2 — invalid locale
#   3 — missing template bundle

set -eu

SUPPORTED_LOCALES=(en ru es zh)
CORE_FILES=(STATUS.md plan.md checklist.md BACKLOG.md RESEARCH.md progress.md lessons.md)
CORE_DIRS=(plans plans/done notes reports experiments codebase)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

is_supported_locale() {
  local code="$1"
  for l in "${SUPPORTED_LOCALES[@]}"; do
    [ "$l" = "$code" ] && return 0
  done
  return 1
}

LANG_FLAG=""
MB_ROOT_OVERRIDE=""

for arg in "$@"; do
  case "$arg" in
    --lang=*)     LANG_FLAG="${arg#--lang=}" ;;
    --mb-root=*)  MB_ROOT_OVERRIDE="${arg#--mb-root=}" ;;
    -h|--help)
      cat <<'USAGE'
mb-init-bank — scaffold .memory-bank/ from locale template bundle

Usage:
  mb-init-bank.sh [--lang=XX] [--mb-root=PATH]

Options:
  --lang=XX       Force locale (en|ru|es|zh). Default: MB_LANG, .mb-config, or en.
  --mb-root=PATH  Project root (default: $MB_ROOT or $PWD).
USAGE
      exit 0
      ;;
  esac
done

MB_ROOT="${MB_ROOT_OVERRIDE:-${MB_ROOT:-$PWD}}"
BANK="$MB_ROOT/.memory-bank"
CONFIG="$BANK/.mb-config"

# Resolve locale
LANG_RESOLVED=""
if [ -n "$LANG_FLAG" ]; then
  LANG_RESOLVED="$LANG_FLAG"
elif [ -n "${MB_LANG:-}" ]; then
  LANG_RESOLVED="$MB_LANG"
elif [ -f "$CONFIG" ]; then
  LANG_RESOLVED="$(grep -E '^lang=' "$CONFIG" 2>/dev/null | tail -1 | cut -d= -f2-)"
fi
[ -n "$LANG_RESOLVED" ] || LANG_RESOLVED="en"

if ! is_supported_locale "$LANG_RESOLVED"; then
  echo "mb-init-bank: invalid locale '$LANG_RESOLVED' (supported: ${SUPPORTED_LOCALES[*]})" >&2
  exit 2
fi

SRC="$REPO_ROOT/templates/locales/$LANG_RESOLVED/.memory-bank"
if [ ! -d "$SRC" ]; then
  echo "mb-init-bank: missing template bundle: $SRC" >&2
  exit 3
fi

mkdir -p "$BANK"
for d in "${CORE_DIRS[@]}"; do
  mkdir -p "$BANK/$d"
done

for f in "${CORE_FILES[@]}"; do
  if [ -f "$BANK/$f" ]; then
    # never clobber user content
    continue
  fi
  cp "$SRC/$f" "$BANK/$f"
done

# write/update .mb-config
if [ -f "$CONFIG" ] && grep -qE '^lang=' "$CONFIG"; then
  tmp="$(mktemp)"
  grep -vE '^lang=' "$CONFIG" > "$tmp" || true
  printf 'lang=%s\n' "$LANG_RESOLVED" >> "$tmp"
  mv "$tmp" "$CONFIG"
else
  printf 'lang=%s\n' "$LANG_RESOLVED" >> "$CONFIG"
fi

echo "mb-init-bank: initialized $BANK (lang=$LANG_RESOLVED)"
