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
  mb-pipeline list                 [mb_path]
  mb-pipeline new  NAME [--agent a,b] [--from NAME|default] [--default] [--force] [mb_path]
  mb-pipeline use  NAME            [mb_path]
  mb-pipeline show     [--pipeline NAME] [mb_path]
  mb-pipeline path     [--pipeline NAME] [mb_path]
  mb-pipeline validate [--pipeline NAME | --all] [path] [mb_path]
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
    valid_pipeline_name "$requested" || return 3
    local sel_yaml sel_path
    sel_yaml="$pdir/$requested.yaml"
    sel_path=$(mb_canonical_under "$pdir" "$sel_yaml") || {
      echo "[pipeline] named pipeline not found: $pdir/$requested.yaml" >&2
      return 3
    }
    if [ -f "$sel_path" ]; then
      abspath "$sel_path"
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
  if [ -n "$cfgname" ]; then
    valid_pipeline_name "$cfgname" || return 3
    local cfg_yaml cfg_path
    cfg_yaml="$pdir/$cfgname.yaml"
    cfg_path=$(mb_canonical_under "$pdir" "$cfg_yaml") || return 3
    if [ -f "$cfg_path" ]; then
      abspath "$cfg_path"
      return 0
    fi
    return 3
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

# validate --all: schema-check every <bank>/pipelines/*.yaml + detect cross-file
# conflicts (duplicate names, >1 default, an agent bound to multiple pipelines).
cmd_validate_all() {
  local mb_arg="${1:-}"
  local mb pdir
  mb=$(mb_resolve_path "$mb_arg")
  pdir="$mb/pipelines"
  if [ ! -d "$pdir" ]; then
    echo "[pipeline] no pipelines directory: $pdir" >&2
    exit 1
  fi
  if [ ! -f "$VALIDATOR" ]; then
    echo "[pipeline] validator missing: $VALIDATOR" >&2
    exit 1
  fi

  local had_error=0 f
  for f in "$pdir"/*.yaml; do
    [ -f "$f" ] || continue
    if ! bash "$VALIDATOR" "$f" >&2; then
      echo "[pipeline] schema error in $(basename "$f")" >&2
      had_error=1
    fi
  done

  REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  MB_PDIR="$pdir" PYTHONPATH="$REPO_ROOT${PYTHONPATH:+:$PYTHONPATH}" python3 - <<'PY' || had_error=1
import os, glob, sys

pdir = os.environ["MB_PDIR"]
names = {}
defaults = []
agent_owner = {}
errors = []
try:
    from memory_bank_skill.pipeline_yaml import PipelineYamlError, load_file as _pipeline_load_file
except ModuleNotFoundError:
    _pipeline_load_file = None
    PipelineYamlError = Exception

for path in sorted(glob.glob(os.path.join(pdir, "*.yaml"))):
    base = os.path.splitext(os.path.basename(path))[0]
    data = {}
    if _pipeline_load_file is not None:
        try:
            data = _pipeline_load_file(path)
        except PipelineYamlError as exc:
            errors.append(f"{os.path.basename(path)}: {exc}")
            continue
        except Exception:
            data = {}
    name = data.get("pipeline_name") or base
    if name in names:
        errors.append(f"duplicate pipeline_name '{name}': {names[name]} and {os.path.basename(path)}")
    else:
        names[name] = os.path.basename(path)
    if data.get("default") is True:
        defaults.append(name)
    for a in (data.get("agents") or []):
        if a in agent_owner:
            errors.append(f"agent '{a}' bound to multiple pipelines: {agent_owner[a]} and {name}")
        else:
            agent_owner[a] = name
if len(defaults) > 1:
    errors.append(f"more than one default pipeline: {', '.join(defaults)}")
for e in errors:
    sys.stderr.write(f"[pipeline] conflict: {e}\n")
sys.exit(1 if errors else 0)
PY

  if [ "$had_error" -ne 0 ]; then
    exit 1
  fi
  echo "[pipeline] all named pipelines valid; no conflicts"
}

cmd_validate() {
  # Forms:
  #   validate                          — resolve project/default, validate
  #   validate <yaml_file>              — validate explicit file
  #   validate <mb_path>                — resolve under bank, validate
  #   validate --pipeline NAME [mb_path]— validate a named pipeline via the ladder
  #   validate --all [mb_path]          — validate every named pipeline + cross-file conflicts
  local all=0 rest=() a
  for a in "$@"; do
    if [ "$a" = "--all" ]; then all=1; else rest+=("$a"); fi
  done
  if [ "$all" -eq 1 ]; then
    cmd_validate_all "${rest[@]+"${rest[@]}"}"
    return 0
  fi
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

# Validate a pipeline name: filename-safe, no path traversal.
valid_pipeline_name() {
  case "$1" in
    ""|*"/"*|*".."*) return 1 ;;
  esac
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

# new <name> [--agent a,b] [--from NAME|default] [--default] [--force] [mb_path]
cmd_new() {
  local name="" agents="" from="default" mkdefault=0 force=0 mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --agent|--agents)
        if [ "$#" -ge 2 ]; then agents="$2"; shift 2;
        else echo "[pipeline] $1 requires a value" >&2; exit 2; fi ;;
      --agent=*|--agents=*) agents="${1#*=}"; shift ;;
      --from)
        if [ "$#" -ge 2 ]; then from="$2"; shift 2;
        else echo "[pipeline] --from requires a value" >&2; exit 2; fi ;;
      --from=*) from="${1#*=}"; shift ;;
      --default) mkdefault=1; shift ;;
      --force) force=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) if [ -z "$name" ]; then name="$1"; elif [ -z "$mb_arg" ]; then mb_arg="$1"; fi; shift ;;
    esac
  done
  if [ -z "$name" ]; then echo "[pipeline] new requires a name" >&2; exit 2; fi
  if ! valid_pipeline_name "$name"; then
    echo "[pipeline] invalid pipeline name: '$name' (allowed: A-Z a-z 0-9 . _ -)" >&2; exit 2
  fi

  local mb pdir
  mb=$(mb_resolve_path "$mb_arg")
  if [ ! -d "$mb" ]; then echo "[pipeline] bank directory does not exist: $mb" >&2; exit 1; fi
  pdir="$mb/pipelines"
  mkdir -p "$pdir"
  local target="$pdir/$name.yaml"
  if [ -f "$target" ] && [ "$force" -eq 0 ]; then
    echo "[pipeline] $target already exists (use --force to overwrite)" >&2; exit 1
  fi

  local base
  if [ "$from" = "default" ]; then
    base="$DEFAULT_YAML"
  else
    base="$pdir/$from.yaml"
  fi
  if [ ! -f "$base" ]; then echo "[pipeline] base pipeline not found: $base" >&2; exit 1; fi

  MB_NEW_NAME="$name" MB_NEW_AGENTS="$agents" MB_NEW_DEFAULT="$mkdefault" \
    python3 - "$base" "$target" <<'PY'
import os, sys

base, target = sys.argv[1], sys.argv[2]
name = os.environ["MB_NEW_NAME"]
agents_raw = os.environ.get("MB_NEW_AGENTS", "")
is_default = os.environ.get("MB_NEW_DEFAULT") == "1"

with open(base, encoding="utf-8") as fh:
    lines = fh.readlines()

META = ("pipeline_name:", "default:", "agents:")
cleaned = []
skip_block = False
for line in lines:
    stripped = line.strip()
    if skip_block:
        if line[:1] in (" ", "\t") or stripped.startswith("- "):
            continue
        skip_block = False
    # drop any prior generated metadata header comment
    if stripped.startswith("# Named pipeline:"):
        continue
    # drop top-level metadata keys (and an agents: block list body)
    if line[:1] not in (" ", "\t") and any(stripped.startswith(k) for k in META):
        if stripped.startswith("agents:") and not stripped.split(":", 1)[1].strip():
            skip_block = True
        continue
    cleaned.append(line)

while cleaned and not cleaned[0].strip():
    cleaned.pop(0)

agents_list = [a for a in agents_raw.replace(",", " ").split() if a]
header = [
    f"# Named pipeline: {name} (created by /mb pipeline new)\n",
    f"pipeline_name: {name}\n",
    f"default: {'true' if is_default else 'false'}\n",
]
if agents_list:
    header.append("agents: [" + ", ".join(agents_list) + "]\n")
header.append("\n")

with open(target, "w", encoding="utf-8") as fh:
    fh.writelines(header + cleaned)
PY
  echo "[pipeline] created $target"
}

# use <name> [mb_path] — set <bank>/.mb-config pipeline=<name> (non-destructive default switch).
cmd_use() {
  local name="" mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      *) if [ -z "$name" ]; then name="$1"; elif [ -z "$mb_arg" ]; then mb_arg="$1"; fi; shift ;;
    esac
  done
  if [ -z "$name" ]; then echo "[pipeline] use requires a name" >&2; exit 2; fi
  local mb pdir
  mb=$(mb_resolve_path "$mb_arg")
  pdir="$mb/pipelines"
  if [ ! -f "$pdir/$name.yaml" ]; then
    echo "[pipeline] no such pipeline: $pdir/$name.yaml" >&2; exit 1
  fi
  local cfg="$mb/.mb-config"
  if [ -f "$cfg" ] && grep -qE '^pipeline=' "$cfg" 2>/dev/null; then
    local tmp; tmp=$(mktemp)
    grep -vE '^pipeline=' "$cfg" > "$tmp" || true
    printf 'pipeline=%s\n' "$name" >> "$tmp"
    mv "$tmp" "$cfg"
  else
    printf 'pipeline=%s\n' "$name" >> "$cfg"
  fi
  echo "[pipeline] default pipeline set to '$name' ($cfg)"
}

# list [mb_path] — table of named pipelines (name · default · agents · file), marking the active one.
cmd_list() {
  local mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      *) if [ -z "$mb_arg" ]; then mb_arg="$1"; fi; shift ;;
    esac
  done
  local mb pdir host active
  mb=$(mb_resolve_path "$mb_arg")
  pdir="$mb/pipelines"
  host=$(mb_detect_host)
  active=$(resolve_selected_pipeline_path "$mb_arg" "" 2>/dev/null || true)

  if [ ! -d "$pdir" ] || ! ls "$pdir"/*.yaml >/dev/null 2>&1; then
    echo "(no named pipelines under $pdir)"
    echo "active (resolved now): ${active:-<none>}"
    return 0
  fi

  printf '%-20s %-8s %-26s %s\n' "NAME" "DEFAULT" "AGENTS" "FILE"
  local f name def agents mark
  for f in "$pdir"/*.yaml; do
    [ -f "$f" ] || continue
    name=$(mb_pipeline_meta "$f" pipeline_name)
    if [ -z "$name" ]; then name=$(basename "$f" .yaml); fi
    def=$(mb_pipeline_meta "$f" default)
    agents=$(mb_pipeline_meta "$f" agents)
    mark=""
    if [ "$(abspath "$f")" = "$active" ]; then mark=" *"; fi
    printf '%-20s %-8s %-26s %s%s\n' "$name" "$def" "${agents:-—}" "$f" "$mark"
  done
  echo
  echo "detected host: ${host:-<none>}"
  echo "active (resolved now): ${active:-<none>}   (* = selected)"
}

main() {
  if [ "$#" -lt 1 ]; then
    usage >&2
    exit 2
  fi
  case "$1" in
    -h|--help) usage; exit 0 ;;
    init) shift; cmd_init "$@" ;;
    new) shift; cmd_new "$@" ;;
    use) shift; cmd_use "$@" ;;
    list) shift; cmd_list "$@" ;;
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
