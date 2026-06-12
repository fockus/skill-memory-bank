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
  mb-pipeline show     [--pipeline NAME] [mb_path]
  mb-pipeline path     [--pipeline NAME] [mb_path]
  mb-pipeline validate [--pipeline NAME] [path] [mb_path]
  mb-pipeline --help

Selection ladder (path/show/validate):
  1. --pipeline NAME / $MB_PIPELINE   → <mb_path>/pipelines/NAME.yaml
  2. host-agent binding               → pipeline whose agents: includes the detected host
  3. <mb_path>/.mb-config pipeline=NAME
  4. in-file default: true            → <mb_path>/pipelines/*.yaml
  5. <mb_path>/pipeline.yaml          (legacy / back-compat)
  6. references/pipeline.default.yaml (bundled default)
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

# ─────────────────────────────────────────────────────────────────────────────
# Named-pipeline selection (Stage 2)
# ─────────────────────────────────────────────────────────────────────────────
abspath() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$1" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
  else
    printf '%s\n' "$1"
  fi
}

# Read the `pipeline=<name>` pointer from <bank>/.mb-config (set by `pipeline use`).
read_mbconfig_pipeline() {
  local cfg="$1/.mb-config"
  [ -f "$cfg" ] || return 0
  grep -E '^pipeline=' "$cfg" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

# Parse optional [--pipeline NAME | --name NAME] and a trailing [mb_path].
# Defaults SELECT_NAME from $MB_PIPELINE so the env behaves like the flag.
parse_select_args() {
  SELECT_NAME="${MB_PIPELINE:-}"
  SELECT_MB=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --pipeline=*|--name=*) SELECT_NAME="${1#*=}"; shift ;;
      --pipeline|--name)
        if [ "$#" -ge 2 ]; then SELECT_NAME="$2"; shift 2;
        else echo "[pipeline] $1 requires a name" >&2; exit 2; fi ;;
      -h|--help) usage; exit 0 ;;
      *) if [ -z "$SELECT_MB" ]; then SELECT_MB="$1"; fi; shift ;;
    esac
  done
}

# Resolve a named pipeline through the selection ladder.
#   stdout: absolute path of the selected pipeline (empty when none selected here)
#   return: 0 selected · 1 nothing selected (caller falls back to legacy) · 3 explicit name missing
select_named_pipeline() {
  local mb_arg="$1" requested="$2"
  local mb pdir
  mb=$(mb_resolve_path "$mb_arg")
  pdir="$mb/pipelines"

  # 1. explicit name (flag or MB_PIPELINE)
  if [ -n "$requested" ]; then
    if [ -f "$pdir/$requested.yaml" ]; then
      abspath "$pdir/$requested.yaml"
      return 0
    fi
    echo "[pipeline] named pipeline not found: $pdir/$requested.yaml" >&2
    return 3
  fi

  [ -d "$pdir" ] || return 1

  # 2. host-agent binding
  local host
  host=$(mb_detect_host)
  if [ -n "$host" ]; then
    local match="" match_default="" match_count=0 f a
    for f in "$pdir"/*.yaml; do
      [ -f "$f" ] || continue
      for a in $(mb_pipeline_meta "$f" agents); do
        if [ "$a" = "$host" ]; then
          match_count=$((match_count + 1))
          if [ -z "$match" ]; then match="$f"; fi
          if [ "$(mb_pipeline_meta "$f" default)" = "true" ]; then match_default="$f"; fi
          break
        fi
      done
    done
    if [ -n "$match_default" ]; then abspath "$match_default"; return 0; fi
    if [ -n "$match" ]; then
      if [ "$match_count" -gt 1 ]; then
        echo "[pipeline] $match_count pipelines bind host '$host'; using $(basename "$match") (no default among them)" >&2
      fi
      abspath "$match"
      return 0
    fi
  fi

  # 3. .mb-config pointer
  local cfgname
  cfgname=$(read_mbconfig_pipeline "$mb")
  if [ -n "$cfgname" ] && [ -f "$pdir/$cfgname.yaml" ]; then
    abspath "$pdir/$cfgname.yaml"
    return 0
  fi

  # 4. in-file default: true
  local g
  for g in "$pdir"/*.yaml; do
    [ -f "$g" ] || continue
    if [ "$(mb_pipeline_meta "$g" default)" = "true" ]; then
      abspath "$g"
      return 0
    fi
  done

  return 1
}

# Full ladder: named selection (steps 1-4) → legacy <bank>/pipeline.yaml → bundled default.
resolve_selected_pipeline_path() {
  local mb_arg="$1" name="$2"
  local sel rc=0
  sel=$(select_named_pipeline "$mb_arg" "$name") || rc=$?
  if [ "$rc" -eq 0 ] && [ -n "$sel" ]; then
    printf '%s\n' "$sel"
    return 0
  fi
  if [ "$rc" -eq 3 ]; then
    return 3
  fi
  resolve_pipeline_path "$mb_arg"
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
  parse_select_args "$@"
  local resolved rc=0
  resolved=$(resolve_selected_pipeline_path "$SELECT_MB" "$SELECT_NAME") || rc=$?
  if [ "$rc" -ne 0 ]; then exit "$rc"; fi
  cat "$resolved"
}

cmd_path() {
  parse_select_args "$@"
  local out rc=0
  out=$(resolve_selected_pipeline_path "$SELECT_MB" "$SELECT_NAME") || rc=$?
  if [ "$rc" -ne 0 ]; then exit "$rc"; fi
  printf '%s\n' "$out"
}

cmd_validate() {
  # Forms:
  #   validate                          — resolve project/default, validate
  #   validate <yaml_file>              — validate explicit file
  #   validate <mb_path>                — resolve under bank, validate
  #   validate --pipeline NAME [mb_path]— validate a named pipeline via the ladder
  parse_select_args "$@"

  local target rc=0
  if [ -n "$SELECT_NAME" ]; then
    target=$(resolve_selected_pipeline_path "$SELECT_MB" "$SELECT_NAME") || rc=$?
    if [ "$rc" -ne 0 ]; then exit "$rc"; fi
  elif [ -n "$SELECT_MB" ] && [ -f "$SELECT_MB" ]; then
    target="$SELECT_MB"            # explicit yaml file
  else
    target=$(resolve_selected_pipeline_path "$SELECT_MB" "")
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
