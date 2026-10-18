# shellcheck shell=bash
# Install options when there is no previous install manifest — `pipx install
# --force` / `pipx reinstall` recreated the venv that held it, or Homebrew
# cleaned the old keg. Sourced by install.sh after scripts/_lib.sh
# (MB_VALID_CLIENTS, MB_VALID_LANGUAGES).

# Keep selective options outside a package-manager-owned bundle. No inference
# from markers, incoming bytes or aliases confers ownership of installed files.
mb_opencode_install_scope() {
  local native="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/.mb-install-manifest.json" saved=""
  if [ -z "${MB_MANIFEST_PATH:-}" ] && { [ "${ONLY:-}" = opencode ] || [ -f "$native" ]; }; then
    MANIFEST="$native"
  fi
  if [ -f "$MANIFEST" ]; then
    if ! saved=$(jq -r --arg home "$HOME" 'if .home == $home then .install_scope // "" else "" end' "$MANIFEST" 2>/dev/null); then
      # Leave the old unscoped corrupt-manifest policy to its existing validator.
      if [ -n "${ONLY:-}" ] || [ "$MANIFEST" = "$native" ]; then
        echo "[install] cannot read selective ownership/options: $MANIFEST; restore its authoritative record" >&2
        return 1
      fi
      saved=""
    fi
  fi
  ONLY="${ONLY:-$saved}"
  [ -z "$ONLY" ] || [ "$ONLY" = opencode ] || { echo '[install] unsupported saved scope' >&2; return 1; }
}

mb_validate_opencode_scope() {
  [ "${ONLY:-}" = opencode ] || return 0
  if [ -n "${CLIENTS:-}" ] && [ "$CLIENTS" != opencode ]; then
    echo '[install] --only opencode conflicts with --clients; omit --clients or use opencode' >&2
    return 1
  fi
  if [ -n "${KEY_RULES_MODE:-}" ] || [ "${FORCE:-0}" = 1 ]; then
    echo '[install] --only opencode does not support --key-rules or --force; preserve existing selections' >&2
    return 1
  fi
  case "${WITH_EXTENSIONS_VALUE:-}" in
    ''|opencode) ;;
    *) echo '[install] --only opencode accepts only --with-extensions=opencode' >&2; return 1 ;;
  esac
  export MB_INSTALL_ONLY=opencode
}

# mb_inferred_install_options <project_root> — the options an earlier install
# left traces of. Sets the same MB_SAVED_* variables as mb_saved_install_options
# (MB_SAVED_PROJECT_ROOT stays empty: the caller's cwd rule decides) plus
# MB_INFERRED_FROM (the files read, for the stderr line). Returns 1 when there
# is no trace at all (a first install).
#   - language, comments language: ~/.claude/memory-bank-config.json;
#   - clients: claude-code by its block in ~/.claude/CLAUDE.md; the others by
#     the manifest their adapter writes into the project (Cursor also keeps a
#     global one). Global Codex/OpenCode/Pi files are written on every install
#     (A25), so they do not tell which clients were picked.
mb_inferred_install_options() {
  local project="${1:?project_root required}" cfg="$HOME/.claude/memory-bank-config.json"
  local lang="" comments="" clients="" from="" c f
  local -a traces
  if [ -f "$cfg" ]; then
    lang="$(sed -n 's/.*"preferred_language": *"\([^"]*\)".*/\1/p' "$cfg" | head -n 1)"
    comments="$(sed -n 's/.*"comments_language": *"\([^"]*\)".*/\1/p' "$cfg" | head -n 1)"
    case " ${MB_VALID_LANGUAGES[*]} " in *" $lang "*) from="$cfg" ;; *) lang="" ;; esac
    case " ${MB_VALID_LANGUAGES[*]} " in *" $comments "*) ;; *) comments="" ;; esac
  fi
  for c in "${MB_VALID_CLIENTS[@]}"; do
    case "$c" in
      claude-code) traces=("$HOME/.claude/CLAUDE.md") ;;
      cursor) traces=("$project/.cursor/.mb-manifest.json" "$HOME/.cursor/.mb-manifest.json") ;;
      windsurf) traces=("$project/.windsurf/.mb-manifest.json") ;;
      cline) traces=("$project/.clinerules/.mb-manifest.json") ;;
      kilo) traces=("$project/.kilocode/.mb-manifest.json") ;;
      opencode) traces=("$project/.opencode/.mb-manifest.json") ;;
      pi) traces=("$project/.mb-pi-manifest.json") ;;
      codex) traces=("$project/.codex/.mb-manifest.json") ;;
      *) traces=() ;;
    esac
    for f in ${traces[@]+"${traces[@]}"}; do
      [ -f "$f" ] || continue
      if [ "$c" != claude-code ] || grep -qxF '# [MEMORY-BANK-SKILL]' "$f"; then
        clients="${clients:+$clients,}$c"
        from="${from:+$from, }$f"
        break
      fi
    done
  done
  [ -n "$from" ] || return 1
  # shellcheck disable=SC2034  # read by install.sh
  MB_SAVED_LANGUAGE="$lang" MB_SAVED_COMMENTS_LANGUAGE="$comments" MB_SAVED_CLIENTS="$clients" \
    MB_SAVED_PROJECT_ROOT="" MB_INFERRED_FROM="$from"
}


# mb_written_by_last_install <file> — with no previous manifest, is <file>
# exactly as the last install left it? Every install rewrites
# ~/.claude/memory-bank-config.json; install.sh reads its mtime into
# MB_LAST_INSTALL_AT before this run writes anything. A file modified within a
# minute of it was written by that run and not edited since → ours, replaced
# without a backup. Older files (the user's own, or carried over unchanged from
# an earlier run) and newer ones (edited) keep today's backup. Orphans of the
# old version cannot be known without its file list, so they are left in place.
# ponytail: ±60 s around one reference file instead of per-file hashes; files
# that survived several installs unchanged still get a backup — the manifest
# (kept outside the venv/keg) is the real fix.
mb_written_by_last_install() {
  [ -n "${MB_LAST_INSTALL_AT:-}" ] || return 1
  local m
  m="$(mb_mtime "$1")"
  [ "$m" -ge $((MB_LAST_INSTALL_AT - 60)) ] && [ "$m" -le $((MB_LAST_INSTALL_AT + 60)) ]
}
