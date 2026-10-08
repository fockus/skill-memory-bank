#!/usr/bin/env bash
# mb-rules.sh — the managed `## Key rules` block at the top of CLAUDE.md / AGENTS.md.
#
# The selection comes from `mb-profile.sh key-rules` (rules/key-rules.json defaults,
# then the user, then the project rules profile). The block sits first in the file —
# after the mb-language block when present — between
# <!-- mb-key-rules:start --> and <!-- mb-key-rules:end -->, and ends with a pointer
# to the detailed rules (AGR-066).
#
# Usage:
#   mb-rules.sh render [--target=project|global] [--host=claude|codex|pi|opencode|cursor]
#                      [--mode=delta|full] [--project=DIR] [--mb=PATH]
#       Print the block to stdout; writes nothing. Project target: delta (default) =
#       only the project's differences from the user-level rules (AGR-083); full =
#       every rule. Global target: always full.
#   mb-rules.sh sync [--scope=project|user] [--project=DIR] [--mb=PATH]
#       project: every managed project block — Key rules in <project>/CLAUDE.md and
#       AGENTS.md (delta), the AGENTS.md Memory Bank block, the body of existing per-host
#       rule files (Cursor .mdc delta, Windsurf/Cline/Kilo full), plus the settings block
#       <!-- mb-project-rules:start/end --> on top of <project>/RULES.md (else
#       <bank>/RULES.md). Each block is stamped (mb-stamp:); the session-start hook
#       prints this command when a stamp is stale (MB_AUTO_REFRESH=on runs it).
#       user: ~/.claude/CLAUDE.md and the global AGENTS.md of Codex,
#       Pi, OpenCode and Cursor. Only files that already exist (init --scope=project
#       creates <project>/RULES.md when neither RULES.md exists).
#   mb-rules.sh list | enable <id> | disable <id> | add "<text>" | remove <n> [--scope=...]
#   mb-rules.sh init [--enable=id,id] [--disable=id,id] [--custom="<text>"]... [--scope=...]
#   mb-rules.sh init --interactive [--scope=...]   (checklist on stdin; install.sh onboarding)
#   mb-rules.sh set architecture <name[,name…][,custom:<text>]> | tdd on|off|small+
#       | trophy on|off | coverage off|<overall>/<core>/<infra>
#       | principle solid|dry|kiss|yagni on|off | discipline auto|strict|calm  [--scope=...]
#   mb-rules.sh discipline auto|strict|calm [--scope=...]   (alias of set discipline)
#       Edit the scope's rules profile (key_rules; architecture; quality — also the switch
#       of solid/dry/kiss/yagni, tdd, testing-trophy, coverage; discipline), then sync that
#       scope. init replaces the scope's selection.
#       Exit 2: unknown or locked id, bad rule text, bad setting value.
#       --scope defaults to project when a bank resolves, else user.
#   discipline strict adds the strict lines to the block; auto renders calm (the host's
#   main model is not known at render time).

# shellcheck shell=bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# shellcheck source=../adapters/_lib_agents_md.sh
source "$SCRIPT_DIR/../adapters/_lib_agents_md.sh"
# shellcheck source=mb_rules_sync_lib.sh
source "$SCRIPT_DIR/mb_rules_sync_lib.sh"

KR_START="<!-- mb-key-rules:start -->"
KR_END="<!-- mb-key-rules:end -->"
PR_START="<!-- mb-project-rules:start -->"
PR_END="<!-- mb-project-rules:end -->"
LANGUAGE_END="<!-- mb-language:end -->"
GLOBAL_HOSTS="claude codex pi opencode cursor"

_die() {
  printf 'mb-rules: %s\n' "$*" >&2
  exit 1
}

# Global instructions file of a host.
_host_file() {
  case "$1" in
    claude)   printf '%s\n' "$HOME/.claude/CLAUDE.md" ;;
    codex)    printf '%s\n' "$HOME/.codex/AGENTS.md" ;;
    pi)       printf '%s\n' "$HOME/.pi/agent/AGENTS.md" ;;
    opencode) printf '%s\n' "$HOME/.config/opencode/AGENTS.md" ;;
    cursor)   printf '%s\n' "$HOME/.cursor/AGENTS.md" ;;
    *)        _die "unknown host: $1" ;;
  esac
}

# Global RULES.md as the host sees it — same paths install.sh writes into the
# hosts' global blocks. The `~` is literal text for the agent to read.
# shellcheck disable=SC2088
_host_rules() {
  case "$1" in
    claude)   printf '%s\n' '~/.claude/RULES.md' ;;
    codex)    printf '%s\n' '~/.codex/skills/memory-bank/rules/RULES.md' ;;
    pi)       printf '%s\n' '~/.pi/agent/skills/memory-bank/rules/RULES.md' ;;
    opencode) printf '%s\n' '~/.config/opencode/skills/memory-bank/rules/RULES.md' ;;
    cursor)   printf '%s\n' '~/.cursor/skills/memory-bank/rules/RULES.md' ;;
    *)        _die "unknown host: $1" ;;
  esac
}

# Absolute bank path for PROJECT (explicit --mb, else mb_resolve_path from PROJECT).
_bank_dir() {
  local project="$1" mb="$2"
  [ -n "$mb" ] || mb="$(cd "$project" && mb_resolve_path "")"
  case "$mb" in
    /*) printf '%s\n' "$mb" ;;
    *)  printf '%s\n' "$project/$mb" ;;
  esac
}

# Project pointer: <repo>/RULES.md, else <bank>/RULES.md, else a create hint.
# Backticks are literal markdown.
# shellcheck disable=SC2016
_project_pointer() {
  local project="$1" bank="$2" shown
  if [ -f "$project/RULES.md" ]; then
    printf 'Details: `RULES.md`.\n'
  elif [ -f "$bank/RULES.md" ]; then
    case "$bank" in
      "$project"/*) shown="${bank#"$project"/}/RULES.md" ;;
      *)            shown="$bank/RULES.md" ;;
    esac
    printf 'Details: `%s`.\n' "$shown"
  else
    printf 'Your own rules: create `RULES.md` in the project root.\n'
  fi
}

# _resolved PROFILE — the effective selection (JSON) for the user profile plus PROFILE;
# /dev/null is not a regular file, so the resolver skips the project layer.
_resolved() { bash "$SCRIPT_DIR/mb-profile.sh" key-rules --json "--project=$1"; }

# render_block TARGET HOST PROJECT BANK [MODE] — the block on stdout, no writes.
# MODE (project target only): delta (default) = only the project's differences from
# the user-level rules, for files next to a host's global instructions file (AGR-083);
# full = every rule, for hosts without one (Windsurf, Cline, Kilo rule files).
render_block() {
  local target="$1" host="$2" project="$3" bank="$4" mode="${5:-delta}" profile pointer
  local -a base=() stamp=()
  if [ "$target" = project ]; then
    profile="$bank/rules-profile.json"
    pointer="$(_project_pointer "$project" "$bank")"
    stamp=("--stamp=$(mb_project_stamp "$project")")
    [ "$mode" = delta ] && base=("--base=/dev/fd/3")
  else
    # Global files carry the user selection only, always in full.
    profile=/dev/null
    pointer="Details: \`$(_host_rules "$host")\`."
  fi
  _resolved "$profile" \
    | PYTHONPATH="$SCRIPT_DIR/..${PYTHONPATH:+:$PYTHONPATH}" \
      "$(mb_resolve_python "$SCRIPT_DIR/..")" -m memory_bank_skill.key_rules block "--pointer=$pointer" ${base[@]+"${base[@]}"} ${stamp[@]+"${stamp[@]}"} \
      3< <([ ${#base[@]} -eq 0 ] || _resolved /dev/null)
}

# _edit OP SCOPE PROJECT BANK [ARGS...] — change the scope's key_rules, then sync it.
_edit() {
  local op="$1" scope="$2" project="$3" bank="$4" user_profile rc=0
  shift 4
  user_profile="$(mb_agent_config_dir claude-code)/memory-bank/rules-profile.json"
  if [ "$scope" = project ] && [ ! -d "$bank" ]; then
    _die "no Memory Bank at $bank — use --scope=user or run /mb init"
  fi
  PYTHONPATH="$SCRIPT_DIR/..${PYTHONPATH:+:$PYTHONPATH}" \
    "$(mb_resolve_python "$SCRIPT_DIR/..")" -m memory_bank_skill.key_rules_edit "$op" "--scope=$scope" \
    "--user=$user_profile" "--project=$bank/rules-profile.json" "$@" || rc=$?
  [ "$rc" -eq 0 ] || exit "$rc"
  case "$op" in init|prompt) CREATE_RULES_MD=1 ;; esac
  [ "$op" = list ] || _sync "$scope" "$project" "$bank"
}

_sync() {
  local scope="$1" project="$2" bank="$3" h f
  case "$scope" in
    project)
      # RULES.md first: a freshly created one changes the Key rules pointer.
      _sync_rules_md "$project" "$bank"
      _sync_file "$project/CLAUDE.md" project claude "$project" "$bank" delta
      if grep -qxF -- "$MB_START_MARKER" "$project/AGENTS.md" 2>/dev/null; then
        _sync_agents_md "$project"
      else
        _sync_file "$project/AGENTS.md" project claude "$project" "$bank" delta
      fi
      # Per-host rule files, as the adapters write them: the Cursor .mdc skips the Key
      # rules when AGENTS.md carries them (else the delta — Cursor has a global
      # AGENTS.md); Windsurf, Cline and Kilo have no global file and keep the full block.
      if grep -qF -- "$KR_START" "$project/AGENTS.md" 2>/dev/null; then
        _sync_rule_file "$project/.cursor/rules/memory-bank.mdc" "$project" 0
      else
        _sync_rule_file "$project/.cursor/rules/memory-bank.mdc" "$project" 1 delta
      fi
      for f in .windsurf/rules/memory-bank.md .clinerules/memory-bank.md .clinerules \
               .kilocode/rules/memory-bank.md; do
        _sync_rule_file "$project/$f" "$project"
      done
      ;;
    user)
      for h in $GLOBAL_HOSTS; do
        _sync_file "$(_host_file "$h")" global "$h" "$project" "$bank" full
      done
      ;;
    *) _die "--scope must be project or user" ;;
  esac
}

main() {
  local cmd="${1:-}" target=project scope="" host=claude project="$PWD" mb="" mode=delta arg bank
  local -a pass=()
  [ $# -gt 0 ] && shift
  for arg in "$@"; do
    case "$arg" in
      --target=*)  target="${arg#--target=}" ;;
      --scope=*)   scope="${arg#--scope=}" ;;
      --host=*)    host="${arg#--host=}" ;;
      --mode=*)    mode="${arg#--mode=}" ;;
      --project=*) project="${arg#--project=}" ;;
      --mb=*)      mb="${arg#--mb=}" ;;
      --enable=*|--disable=*|--custom=*) pass+=("$arg") ;;
      --interactive) cmd=prompt ;;
      --*)         _die "unknown option: $arg" ;;
      *)           pass+=("$arg") ;;
    esac
  done
  [ -d "$project" ] || _die "project directory not found: $project"
  project="$(cd "$project" && pwd -P)"
  bank="$(_bank_dir "$project" "$mb")"
  if [ -z "$scope" ]; then
    scope=user
    [ -d "$bank" ] && scope=project
  fi
  case "$scope" in project|user) ;; *) _die "--scope must be project or user" ;; esac
  case "$mode" in delta|full) ;; *) _die "--mode must be delta or full" ;; esac

  case "$cmd" in
    render)
      case "$target" in
        project|global) render_block "$target" "$host" "$project" "$bank" "$mode" ;;
        *) _die "--target must be project or global" ;;
      esac
      ;;
    sync) _sync "$scope" "$project" "$bank" ;;
    list|enable|disable|add|remove|init|prompt|set|discipline)
      _edit "$cmd" "$scope" "$project" "$bank" ${pass[@]+"${pass[@]}"}
      ;;
    *)
      sed -n '2,39p' "$0" | sed 's/^# \{0,1\}//'
      [ "$cmd" = "-h" ] || [ "$cmd" = "--help" ] || exit 1
      ;;
  esac
}

main "$@"
