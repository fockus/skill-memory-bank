#!/usr/bin/env bash
# mb-config.sh — memory-bank config resolver + locale auto-detector
#
# Usage:
#   mb-config get <key>          — print resolved value to stdout
#   mb-config set <key> <value>  — persist to $MB_ROOT/.memory-bank/.mb-config
#   mb-config detect-lang        — heuristic scan of existing bank (stdout: detected code)
#
# Keys:
#   lang ∈ {en, ru, es, zh}
#
# Resolution order for `get lang` (highest → lowest):
#   1. MB_LANG env var
#   2. $MB_ROOT/.memory-bank/.mb-config (`lang=XX`)
#   3. auto-detect from existing bank content (and WRITE BACK to .mb-config)
#   4. default → en
#
# Exit codes:
#   0 — success
#   2 — unknown key / invalid locale

set -eu

SUPPORTED_LOCALES=(en ru es zh)

print_usage() {
  cat <<'USAGE'
mb-config — memory-bank config resolver

Usage:
  mb-config get <key>              Resolve and print a key
  mb-config set <key> <value>      Persist <key>=<value> to .mb-config
  mb-config detect-lang            Print best-guess locale from existing bank
  mb-config --help                 Show this help

Keys:
  lang   ∈ {en, ru, es, zh}

Resolution for `get lang` (highest → lowest):
  1. $MB_LANG                              (session override)
  2. $MB_ROOT/.memory-bank/.mb-config      (lang=XX)
  3. auto-detect existing bank content     (write-back to .mb-config)
  4. default → en
USAGE
}

is_supported_locale() {
  local code="$1"
  for l in "${SUPPORTED_LOCALES[@]}"; do
    [ "$l" = "$code" ] && return 0
  done
  return 1
}

bank_dir() {
  echo "${MB_ROOT:-$PWD}/.memory-bank"
}

config_path() {
  echo "$(bank_dir)/.mb-config"
}

read_config_value() {
  # $1 = key
  local cfg
  cfg="$(config_path)"
  [ -f "$cfg" ] || return 1
  local val
  val="$(grep -E "^$1=" "$cfg" 2>/dev/null | tail -1 | cut -d= -f2-)"
  [ -n "$val" ] || return 1
  printf '%s' "$val"
}

write_config_value() {
  # $1 = key, $2 = value
  local key="$1"
  local val="$2"
  local cfg
  cfg="$(config_path)"
  mkdir -p "$(dirname "$cfg")"
  if [ -f "$cfg" ] && grep -qE "^$key=" "$cfg"; then
    # replace existing line
    local tmp
    tmp="$(mktemp)"
    grep -vE "^$key=" "$cfg" > "$tmp" || true
    printf '%s=%s\n' "$key" "$val" >> "$tmp"
    mv "$tmp" "$cfg"
  else
    printf '%s=%s\n' "$key" "$val" >> "$cfg"
  fi
}

# Heuristic: scan bank content for locale hints.
# Today we look for Cyrillic bytes in STATUS.md / plan.md — covers the
# only non-English locale that shipped before v3.1.1 (ru). For es/zh we
# currently return en (users must opt in explicitly via --lang).
detect_lang_from_bank() {
  local bank
  bank="$(bank_dir)"
  [ -d "$bank" ] || { echo en; return 0; }
  local f
  for f in "$bank/plan.md" "$bank/STATUS.md" "$bank/checklist.md"; do
    [ -f "$f" ] || continue
    # LC_ALL=C grep for any cyrillic UTF-8 lead byte (0xD0 or 0xD1)
    if LC_ALL=C grep -q $'[\xd0\xd1]' "$f" 2>/dev/null; then
      echo ru
      return 0
    fi
  done
  echo en
}

cmd_get() {
  local key="${1:-}"
  [ -n "$key" ] || { echo "mb-config: get requires a key" >&2; exit 2; }
  case "$key" in
    lang)
      # 1. env override
      if [ -n "${MB_LANG:-}" ]; then
        if ! is_supported_locale "$MB_LANG"; then
          echo "mb-config: invalid MB_LANG='$MB_LANG' (supported: ${SUPPORTED_LOCALES[*]})" >&2
          exit 2
        fi
        printf '%s\n' "$MB_LANG"
        return 0
      fi
      # 2. config file
      local val
      if val="$(read_config_value lang)"; then
        if ! is_supported_locale "$val"; then
          echo "mb-config: invalid lang='$val' in $(config_path)" >&2
          exit 2
        fi
        printf '%s\n' "$val"
        return 0
      fi
      # 3. auto-detect + write-back
      local detected
      detected="$(detect_lang_from_bank)"
      if is_supported_locale "$detected"; then
        # Only persist when bank exists (otherwise it's purely the default)
        if [ -d "$(bank_dir)" ]; then
          write_config_value lang "$detected"
        fi
        printf '%s\n' "$detected"
        return 0
      fi
      # 4. default
      echo en
      ;;
    *)
      echo "mb-config: unknown key '$key'" >&2
      exit 2
      ;;
  esac
}

cmd_set() {
  local key="${1:-}"
  local val="${2:-}"
  if [ -z "$key" ] || [ -z "$val" ]; then
    echo "mb-config: set <key> <value>" >&2
    exit 2
  fi
  case "$key" in
    lang)
      if ! is_supported_locale "$val"; then
        echo "mb-config: invalid lang='$val' (supported: ${SUPPORTED_LOCALES[*]})" >&2
        exit 2
      fi
      write_config_value lang "$val"
      ;;
    *)
      echo "mb-config: unknown key '$key'" >&2
      exit 2
      ;;
  esac
}

cmd_detect_lang() {
  detect_lang_from_bank
}

main() {
  case "${1:-}" in
    -h|--help|"") print_usage; [ -z "${1:-}" ] && exit 2 || exit 0 ;;
    get) shift; cmd_get "$@" ;;
    set) shift; cmd_set "$@" ;;
    detect-lang) shift; cmd_detect_lang "$@" ;;
    *) echo "mb-config: unknown subcommand '$1'" >&2; exit 2 ;;
  esac
}

main "$@"
