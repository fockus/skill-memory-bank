#!/usr/bin/env bash
# mb-agent-caps.sh — capability-aware transport + model resolver for /mb work.
#
# Picks the CLI transport (pi / opencode / claude-agent) and concrete model to
# run a governed step on, honouring BOTH availability dimensions the user cares
# about: (1) the CLI agent is installed, AND (2) the required model is actually
# offered by that CLI. Walks `dispatch.priority` (default: pi → opencode →
# claude-agent), maps the role's contract model through `dispatch.model_map`,
# and selects the first transport where CLI+model are both present. Falls back
# to the Claude Code Agent tool (opus/sonnet) only when nothing matches.
#
# Usage:
#   mb-agent-caps.sh detect [--mb <path>]
#   mb-agent-caps.sh resolve --role <role> [--mb <path>]
#
# `resolve` prints a key=value block on stdout:
#   transport=<pi|opencode|claude-agent>
#   model=<resolved model id>
#   thinking=<thinking level or empty>
#   substituted=<true|false>      # true → contract transport unavailable, fell back
#
# Testability: set MB_CAPS_FIXTURE=<file> to bypass real CLI probing. Fixture
# lines (hermetic for CI, no pi/opencode needed):
#   transport pi
#   transport opencode
#   model pi openai-codex/gpt-5.5
#   model opencode opencode-go/deepseek-v4-pro
#
# Exit codes:
#   0 — resolved (transport+model printed)
#   1 — argument error
#   2 — pipeline.yaml read/parse failure
#   3 — no transport/model available and dispatch.on_none_available == error

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

# ---- capability probes (overridable via MB_CAPS_FIXTURE) --------------------

caps_transport_available() {
  local t="$1"
  [ "$t" = "claude-agent" ] && return 0 # the host Agent tool is always reachable
  if [ -n "${MB_CAPS_FIXTURE:-}" ]; then
    grep -qxF "transport $t" "$MB_CAPS_FIXTURE"
    return
  fi
  command -v "$t" >/dev/null 2>&1
}

caps_models() { # print available model ids for transport, one id per line
  local t="$1"
  if [ -n "${MB_CAPS_FIXTURE:-}" ]; then
    awk -v t="$t" '$1=="model" && $2==t {print $3}' "$MB_CAPS_FIXTURE"
    return 0
  fi
  case "$t" in
    opencode) opencode models 2>/dev/null || true ;;
    pi) pi --list-models 2>/dev/null || true ;;
    codex) codex --list-models 2>/dev/null || codex models 2>/dev/null || true ;;
    claude-agent) printf '%s\n' opus sonnet haiku ;;
    *) : ;;
  esac
}

# Transports that can enumerate their models (strict availability check).
# Others (e.g. codex) are "trusted": if the CLI is installed, the mapped/contract
# model is assumed available. Overridden per-pipeline via dispatch.enumerable.
caps_is_enumerable() {
  case ",${CAPS_ENUMERABLE:-pi,opencode}," in
    *",$1,"*) return 0 ;;
  esac
  return 1
}

caps_model_available() {
  local t="$1" m="$2"
  # Non-enumerable transports (e.g. codex): trust the model when the CLI is present.
  caps_is_enumerable "$t" || return 0
  # Compare on the first whitespace token so "<id>  <description>" lines match.
  caps_models "$t" | awk '{print $1}' | grep -qxF "$m"
}

# ---- pipeline resolution ----------------------------------------------------

resolve_pipeline_path() {
  local mb_arg="$1"
  local mb_path_raw mb_path script_dir skill_root default_pipeline project_pipeline
  mb_path_raw=$(mb_resolve_path "$mb_arg")
  mb_path="$mb_path_raw"
  [ -d "$mb_path_raw" ] && mb_path=$(cd "$mb_path_raw" && pwd)
  script_dir=$(cd "$(dirname "$0")" && pwd)
  skill_root=$(cd "$script_dir/.." && pwd)
  default_pipeline="$skill_root/references/pipeline.default.yaml"
  project_pipeline="$mb_path/pipeline.yaml"
  if [ -f "$project_pipeline" ]; then
    printf '%s\n' "$project_pipeline"
  elif [ -f "$default_pipeline" ]; then
    printf '%s\n' "$default_pipeline"
  else
    echo "[caps] no pipeline.yaml (project: $project_pipeline, default: $default_pipeline)" >&2
    return 2
  fi
}

# Emit role facts from pipeline.yaml as a key=value protocol consumed by resolve.
emit_role_facts() {
  local pipeline="$1" role="$2"
  PIPELINE_PATH="$pipeline" ROLE="$role" python3 - <<'PY'
import os, sys

pipeline = os.environ["PIPELINE_PATH"]
role = os.environ["ROLE"]

try:
    import yaml  # type: ignore
    data = yaml.safe_load(open(pipeline, encoding="utf-8")) or {}
except Exception:
    data = {}

roles = data.get("roles", {}) or {}
role_block = roles.get(role) or {}
contract = role_block.get("model") or ""
thinking = role_block.get("thinking") or ""

dispatch = data.get("dispatch", {}) or {}
priority = dispatch.get("priority") or ["pi", "opencode", "claude-agent"]
on_none = dispatch.get("on_none_available") or "fallback"
model_map = dispatch.get("model_map", {}) or {}
fallback = dispatch.get("fallback", {}) or {}
enumerable = dispatch.get("enumerable") or ["pi", "opencode"]

# Model-family-aware preference: if the contract model matches a `prefer`
# glob, that transport is tried FIRST (e.g. chatgpt model -> codex), before the
# global priority. Falls through to priority when that transport is unavailable.
import fnmatch
prefer_map = dispatch.get("prefer", {}) or {}
prefer_transport = ""
if isinstance(prefer_map, dict):
    for pattern, transport in prefer_map.items():
        if contract and fnmatch.fnmatch(contract, str(pattern)):
            prefer_transport = str(transport)
            break

# Claude-agent fallback model for this role: explicit config, else tier default.
xhigh_roles = {"reviewer", "judge", "planner", "architect",
               "reviewer_logic", "reviewer_tests", "reviewer_quality",
               "reviewer_security", "reviewer_scalability", "reviewer_lead"}
fb_block = fallback.get("claude-agent", {}) or {}
fb_model = fb_block.get(role) if isinstance(fb_block, dict) else None
if not fb_model:
    fb_model = "opus" if role in xhigh_roles else "sonnet"

print("contract=" + contract)
print("thinking=" + str(thinking))
print("priority=" + ",".join(str(p) for p in priority))
print("prefer=" + prefer_transport)
print("enumerable=" + ",".join(str(e) for e in enumerable))
print("on_none=" + str(on_none))
print("fallback=" + str(fb_model))

per_contract = model_map.get(contract, {}) or {}
if isinstance(per_contract, dict):
    for transport, mapped in per_contract.items():
        print("map=%s:%s" % (transport, mapped))
PY
}

# ---- subcommands ------------------------------------------------------------

cmd_detect() {
  local mb_arg="$1" t avail count
  for t in pi opencode codex claude-agent; do
    if caps_transport_available "$t"; then
      count=$(caps_models "$t" | awk '{print $1}' | grep -c . || true)
      avail=true
    else
      count=0
      avail=false
    fi
    printf 'transport=%s available=%s models=%s\n' "$t" "$avail" "$count"
  done
}

cmd_resolve() {
  local mb_arg="$1" role="$2"
  local pipeline contract thinking priority prefer on_none fb_model
  # Map entries kept as "transport:model" lines (bash 3.2 — no assoc arrays).
  local map_lines=""

  pipeline=$(resolve_pipeline_path "$mb_arg") || return 2

  local line
  while IFS= read -r line; do
    case "$line" in
      contract=*) contract="${line#contract=}" ;;
      thinking=*) thinking="${line#thinking=}" ;;
      priority=*) priority="${line#priority=}" ;;
      prefer=*) prefer="${line#prefer=}" ;;
      enumerable=*) CAPS_ENUMERABLE="${line#enumerable=}" ;;
      on_none=*) on_none="${line#on_none=}" ;;
      fallback=*) fb_model="${line#fallback=}" ;;
      map=*) map_lines="${map_lines}${line#map=}"$'\n' ;;
    esac
  done < <(emit_role_facts "$pipeline" "$role")

  if [ -z "${contract:-}" ]; then
    echo "[caps] role '$role' has no model in $pipeline" >&2
    return 1
  fi

  # Effective order: model-family preference first (e.g. chatgpt -> codex), then
  # the global priority, de-duplicated.
  local eff="" p
  caps_add_unique() { case ",$eff," in *",$1,"*) ;; *) eff="${eff:+$eff,}$1" ;; esac; }
  [ -n "${prefer:-}" ] && caps_add_unique "$prefer"
  IFS=',' read -r -a prio_arr <<<"${priority:-pi,opencode,claude-agent}"
  for p in "${prio_arr[@]}"; do caps_add_unique "$p"; done

  local t cand
  IFS=',' read -r -a eff_arr <<<"$eff"
  for t in "${eff_arr[@]}"; do
    [ "$t" = "claude-agent" ] && continue # final fallback, handled below
    caps_transport_available "$t" || continue
    cand=$(printf '%s' "$map_lines" | awk -v t="$t" 'index($0,":")>0 { k=substr($0,1,index($0,":")-1); if (k==t) { print substr($0,index($0,":")+1); exit } }')
    [ -n "$cand" ] || cand="$contract"
    if caps_model_available "$t" "$cand"; then
      printf 'transport=%s\nmodel=%s\nthinking=%s\nsubstituted=false\n' "$t" "$cand" "${thinking:-}"
      return 0
    fi
  done

  # Nothing on the contract transports — fall back to the host Agent tool.
  if [[ ",${priority}," == *",claude-agent,"* ]] && [ "${on_none:-fallback}" != "error" ]; then
    printf 'transport=claude-agent\nmodel=%s\nthinking=%s\nsubstituted=true\n' "${fb_model:-opus}" "${thinking:-}"
    return 0
  fi

  echo "[caps] no available transport+model for role '$role' (priority: ${priority})" >&2
  return 3
}

# ---- arg parsing ------------------------------------------------------------

SUBCMD="${1:-}"
[ $# -gt 0 ] && shift || true

MB_ARG=""
ROLE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mb) MB_ARG="${2:-}"; shift 2 ;;
    --role) ROLE="${2:-}"; shift 2 ;;
    --help | -h)
      sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    --*) echo "[caps] unknown flag: $1" >&2; exit 1 ;;
    *) MB_ARG="$1"; shift ;;
  esac
done

case "$SUBCMD" in
  detect) cmd_detect "$MB_ARG" ;;
  resolve)
    [ -n "$ROLE" ] || { echo "[caps] resolve requires --role <role>" >&2; exit 1; }
    cmd_resolve "$MB_ARG" "$ROLE" ;;
  ""|--help|-h)
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  *) echo "[caps] unknown subcommand: $SUBCMD (expected detect|resolve)" >&2; exit 1 ;;
esac
