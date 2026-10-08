# shellcheck shell=bash
# Install options when there is no previous install manifest — `pipx install
# --force` / `pipx reinstall` recreated the venv that held it, or Homebrew
# cleaned the old keg. Sourced by install.sh after scripts/_lib.sh
# (MB_VALID_CLIENTS, MB_VALID_LANGUAGES).

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
