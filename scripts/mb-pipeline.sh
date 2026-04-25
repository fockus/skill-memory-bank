#!/usr/bin/env bash
# mb-pipeline.sh — manage the project's pipeline.yaml (spec §9).
#
# Subcommands:
#   init  [--force] [mb_path]   Copy bundled default into <bank>/pipeline.yaml
#   show              [mb_path] Print the resolved pipeline (project → default)
#   path              [mb_path] Print absolute path to the resolved pipeline
#   validate [path]   [mb_path] Validate the resolved (or given) pipeline
#
# Resolution order for "the pipeline":
#   1. <mb_path>/pipeline.yaml   (project override)
#   2. references/pipeline.default.yaml (shipped default)
#
# Exit codes:
#   0 — success
#   1 — runtime/idempotency/validation error
#   2 — usage error / unknown subcommand

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_YAML="$SCRIPT_DIR/../references/pipeline.default.yaml"
VALIDATOR="$SCRIPT_DIR/mb-pipeline-validate.sh"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  cat <<'USAGE'
mb-pipeline — manage execution pipeline.yaml

Usage:
  mb-pipeline init  [--force] [mb_path]
  mb-pipeline show              [mb_path]
  mb-pipeline path              [mb_path]
  mb-pipeline validate [path]   [mb_path]
  mb-pipeline --help

Resolution: <mb_path>/pipeline.yaml → references/pipeline.default.yaml
USAGE
}

resolve_default() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$DEFAULT_YAML" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
  else
    printf '%s\n' "$DEFAULT_YAML"
  fi
}

resolve_pipeline_path() {
  # $1 = mb_path arg (may be empty)
  local mb
  mb=$(mb_resolve_path "${1:-}")
  local project="$mb/pipeline.yaml"
  if [ -f "$project" ]; then
    if command -v python3 >/dev/null 2>&1; then
      python3 - "$project" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
    else
      printf '%s\n' "$project"
    fi
    return 0
  fi
  resolve_default
}

cmd_init() {
  local force=0
  local mb_arg=""
  for arg in "$@"; do
    case "$arg" in
      --force) force=1 ;;
      -h|--help) usage; exit 0 ;;
      *) if [ -z "$mb_arg" ]; then mb_arg="$arg"; fi ;;
    esac
  done

  local mb
  mb=$(mb_resolve_path "$mb_arg")
  if [ ! -d "$mb" ]; then
    echo "[pipeline] bank directory does not exist: $mb" >&2
    exit 1
  fi
  local target="$mb/pipeline.yaml"
  if [ -f "$target" ] && [ "$force" -eq 0 ]; then
    echo "[pipeline] $target already exists (use --force to overwrite)" >&2
    exit 1
  fi
  if [ ! -f "$DEFAULT_YAML" ]; then
    echo "[pipeline] bundled default missing: $DEFAULT_YAML" >&2
    exit 1
  fi
  cp "$DEFAULT_YAML" "$target"
  echo "[pipeline] created $target"
}

cmd_show() {
  local mb_arg="${1:-}"
  local resolved
  resolved=$(resolve_pipeline_path "$mb_arg")
  cat "$resolved"
}

cmd_path() {
  local mb_arg="${1:-}"
  resolve_pipeline_path "$mb_arg"
}

cmd_validate() {
  # Forms:
  #   validate                      — resolve project/default, validate
  #   validate <yaml_file>          — validate explicit file
  #   validate <mb_path>            — resolve under bank, validate
  #   validate <yaml_file> <mb_path>— two-arg form (unambiguous)
  local explicit=""
  local mb_arg=""
  if [ "$#" -ge 2 ]; then
    case "$1" in
      -h|--help) usage; exit 0 ;;
    esac
    explicit="$1"
    mb_arg="$2"
  elif [ "$#" -eq 1 ]; then
    case "$1" in
      -h|--help) usage; exit 0 ;;
    esac
    if [ -d "$1" ]; then
      mb_arg="$1"
    else
      explicit="$1"
    fi
  fi

  local target
  if [ -n "$explicit" ]; then
    target="$explicit"
  else
    target=$(resolve_pipeline_path "$mb_arg")
  fi

  if [ ! -f "$VALIDATOR" ]; then
    echo "[pipeline] validator missing: $VALIDATOR" >&2
    exit 1
  fi
  bash "$VALIDATOR" "$target"
}

main() {
  if [ "$#" -lt 1 ]; then
    usage >&2
    exit 2
  fi
  case "$1" in
    -h|--help) usage; exit 0 ;;
    init) shift; cmd_init "$@" ;;
    show) shift; cmd_show "$@" ;;
    path) shift; cmd_path "$@" ;;
    validate) shift; cmd_validate "$@" ;;
    *)
      echo "mb-pipeline: unknown subcommand '$1'" >&2
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
