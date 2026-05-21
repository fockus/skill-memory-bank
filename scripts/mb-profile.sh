#!/usr/bin/env bash
# mb-profile.sh — Rules profile CLI for Memory Bank.
#
# Subcommands:
#   init     Create a user or project rules profile.
#   show     Print the resolved merged profile as JSON.
#   path     Print active profile file paths and which layers exist.
#   validate Validate a profile file; non-zero exit on failure.
#   set      Update one field in an existing profile (--scope required).
#
# Usage examples:
#   mb-profile.sh init --scope=user --role=backend --stack=go \
#       --architecture=clean --delivery=tdd --agent=claude-code
#   mb-profile.sh init --scope=project --role=frontend --stack=typescript \
#       --architecture=fsd --delivery=sdd --mb=.memory-bank
#   mb-profile.sh show
#   mb-profile.sh show --user=<path> --project=<path>
#   mb-profile.sh path
#   mb-profile.sh validate /path/to/rules-profile.json
#   mb-profile.sh set --scope=user --file=<path> role=frontend

# shellcheck shell=bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

MB_PROFILE_PYTHON_MODULE="memory_bank_skill.rules_profile"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_python() {
  python3 -m "$MB_PROFILE_PYTHON_MODULE" "$@"
}

_die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

_die2() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 2
}

# Resolve user profile path for a given agent.
# Falls back to claude-code if agent is empty or unrecognised.
_user_profile_path() {
  local agent="${1:-claude-code}"
  local base
  if ! base=$(mb_agent_config_dir "$agent" 2>/dev/null); then
    base="$HOME/.claude"
  fi
  printf '%s\n' "$base/memory-bank/rules-profile.json"
}

# Print usage and exit 0.
_usage() {
  cat <<'USAGE'
Usage: mb-profile.sh <subcommand> [options]

Subcommands:
  init     Create a user or project rules profile.
           --scope=user|project   (required)
           --role=<role>          backend|frontend|mobile
           --stack=<stack>        go|python|javascript|typescript|java|generic
           --architecture=<arch>  clean|hexagonal|modular-monolith|microservices|
                                  ddd|fsd|mobile-udf|event-driven|custom
           --delivery=<delivery>  tdd|contract-first|api-first|sdd|legacy-safe|exploratory
           --strictness=<s>       advisory|warn|block  (default: warn)
           --agent=<agent>        code-agent name for user-scope path (default: claude-code)
           --mb=<path>            explicit Memory Bank path for project scope

  show     Print resolved profile JSON.
           --user=<path>      override user profile path
           --project=<path>   override project profile path

  path     Print active profile paths and existence status.

  validate <file>   Validate profile file; exit 2 on failure.

  set      Update a single field in a profile.
           --scope=user|project   (required)
           --file=<path>          profile file to update
           <key>=<value>          field to update

Examples:
  mb-profile.sh init --scope=user --role=backend --stack=go --architecture=clean \
      --delivery=tdd --agent=claude-code
  mb-profile.sh init --scope=project --role=frontend --stack=typescript \
      --architecture=fsd --delivery=sdd --mb=.memory-bank
  mb-profile.sh show
  mb-profile.sh validate /path/to/rules-profile.json
  mb-profile.sh set --scope=user --file=~/.claude/memory-bank/rules-profile.json role=frontend
USAGE
  exit 0
}

# ---------------------------------------------------------------------------
# Subcommand: init
# ---------------------------------------------------------------------------

_cmd_init() {
  local scope="" role="" stack="" architecture="" delivery="" strictness="warn"
  local agent="claude-code" mb_path="" output_path=""

  for arg in "$@"; do
    case "$arg" in
      --scope=*)        scope="${arg#--scope=}" ;;
      --role=*)         role="${arg#--role=}" ;;
      --stack=*)        stack="${arg#--stack=}" ;;
      --architecture=*) architecture="${arg#--architecture=}" ;;
      --delivery=*)     delivery="${arg#--delivery=}" ;;
      --strictness=*)   strictness="${arg#--strictness=}" ;;
      --agent=*)        agent="${arg#--agent=}" ;;
      --mb=*)           mb_path="${arg#--mb=}" ;;
      *)                _die "unknown option: $arg" ;;
    esac
  done

  [ -n "$scope" ]    || _die "init requires --scope=user|project"
  [ -n "$role" ]     || _die "init requires --role=<role>"
  [ -n "$stack" ]    || _die "init requires --stack=<stack>"

  case "$scope" in
    user)
      output_path="$(_user_profile_path "$agent")"
      ;;
    project)
      # Resolve mb path
      if [ -z "$mb_path" ]; then
        mb_path="$(mb_resolve_path "")" || true
      fi
      # Check if Memory Bank actually exists
      if [ ! -d "$mb_path" ]; then
        printf 'ERROR: No Memory Bank found at %s.\n' "$mb_path" >&2
        printf 'Hint: run /mb init to create a project Memory Bank, or use --scope=user for a global profile.\n' >&2
        exit 1
      fi
      output_path="$mb_path/rules-profile.json"
      ;;
    *)
      _die "scope must be 'user' or 'project', got: $scope"
      ;;
  esac

  # Build args for Python init subcommand
  local py_args
  py_args=(
    init
    "--scope=$scope"
    "--output=$output_path"
  )
  [ -n "$role" ]         && py_args+=("--role=$role")
  [ -n "$stack" ]        && py_args+=("--stack=$stack")
  [ -n "$architecture" ] && py_args+=("--architecture=$architecture")
  [ -n "$delivery" ]     && py_args+=("--delivery=$delivery")
  [ -n "$strictness" ]   && py_args+=("--strictness=$strictness")

  if ! _python "${py_args[@]}" 2>&1; then
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# Subcommand: show
# ---------------------------------------------------------------------------

_cmd_show() {
  local user_path="" project_path="" agent="claude-code"

  for arg in "$@"; do
    case "$arg" in
      --user=*)    user_path="${arg#--user=}" ;;
      --project=*) project_path="${arg#--project=}" ;;
      --agent=*)   agent="${arg#--agent=}" ;;
      *)           _die "unknown option: $arg" ;;
    esac
  done

  # Auto-resolve user profile if not explicit
  if [ -z "$user_path" ]; then
    local auto_user
    auto_user="$(_user_profile_path "$agent")"
    if [ -f "$auto_user" ]; then
      user_path="$auto_user"
    fi
  fi

  # Auto-resolve project profile if not explicit
  if [ -z "$project_path" ]; then
    local mb
    mb="$(mb_resolve_path "")" || true
    if [ -n "$mb" ] && [ -f "$mb/rules-profile.json" ]; then
      project_path="$mb/rules-profile.json"
    fi
  fi

  local py_args=(resolve)
  [ -n "$user_path" ]    && py_args+=("--user=$user_path")
  [ -n "$project_path" ] && py_args+=("--project=$project_path")

  _python "${py_args[@]}"
}

# ---------------------------------------------------------------------------
# Subcommand: path
# ---------------------------------------------------------------------------

_cmd_path() {
  local agent="claude-code"
  for arg in "$@"; do
    case "$arg" in
      --agent=*) agent="${arg#--agent=}" ;;
      *)         _die "unknown option: $arg" ;;
    esac
  done

  local user_path mb project_path
  user_path="$(_user_profile_path "$agent")"
  mb="$(mb_resolve_path "")" || true
  project_path="$mb/rules-profile.json"

  printf '{"user_profile":{"path":"%s","exists":%s},"project_profile":{"path":"%s","exists":%s}}\n' \
    "$user_path" \
    "$([ -f "$user_path" ] && printf 'true' || printf 'false')" \
    "$project_path" \
    "$([ -f "$project_path" ] && printf 'true' || printf 'false')"
}

# ---------------------------------------------------------------------------
# Subcommand: validate
# ---------------------------------------------------------------------------

_cmd_validate() {
  local file="${1:-}"
  [ -n "$file" ] || _die "validate requires a file path"
  [ -f "$file" ]  || _die "file not found: $file"

  if ! _python validate "$file"; then
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# Subcommand: set
# ---------------------------------------------------------------------------

_cmd_set() {
  local scope="" file="" kv=""

  for arg in "$@"; do
    case "$arg" in
      --scope=*) scope="${arg#--scope=}" ;;
      --file=*)  file="${arg#--file=}" ;;
      *)
        # Treat as key=value if no leading --
        if [[ "$arg" == *"="* ]] && [[ "$arg" != --* ]]; then
          kv="$arg"
        else
          _die "unknown option: $arg"
        fi
        ;;
    esac
  done

  [ -n "$scope" ] || _die "set requires --scope=user|project"
  [ -n "$file" ]  || _die "set requires --file=<path>"
  [ -n "$kv" ]    || _die "set requires a key=value argument"
  [ -f "$file" ]  || _die "file not found: $file"

  # Reject attempts to touch baseline (immutable rules).
  local key="${kv%%=*}"
  if [[ "$key" == baseline* ]]; then
    printf 'ERROR: immutable baseline rules cannot be modified via set.\n' >&2
    exit 2
  fi

  if ! _python set "--file=$file" "$kv" 2>&1; then
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

main() {
  if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    _usage
  fi

  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    init)     _cmd_init     "$@" ;;
    show)     _cmd_show     "$@" ;;
    path)     _cmd_path     "$@" ;;
    validate) _cmd_validate "$@" ;;
    set)      _cmd_set      "$@" ;;
    "")       _usage ;;
    *)        _die "unknown subcommand: $subcommand. Run --help for usage." ;;
  esac
}

main "$@"
