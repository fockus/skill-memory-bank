#!/usr/bin/env bash
# OpenCode 2 installation boundary; native Markdown discovery remains compatible.
set -euo pipefail
ACTION="${1:-}"
PROJECT_ROOT_RAW="${2:-$(pwd)}"
if [ ! -d "$PROJECT_ROOT_RAW" ]; then
  echo "[opencode-adapter] project root not found: $PROJECT_ROOT_RAW" >&2
  exit 1
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT_RAW" && pwd)"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
OC_DIR="$PROJECT_ROOT/.opencode"
COMMANDS_DIR="$OC_DIR/commands"
AGENT_DIR="$OC_DIR/agent"
PLUGIN_DIR="$OC_DIR/plugins"
PLUGIN_FILE="$PLUGIN_DIR/memory-bank.js"
PLUGIN_REF="./.opencode/plugins/memory-bank.js"
OC_JSON="$PROJECT_ROOT/opencode.json"
MANIFEST="$OC_DIR/.mb-manifest.json"
OC_GLOBAL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
OC_GLOBAL_AGENT_DIR="$OC_GLOBAL_DIR/agent"
OC_GLOBAL_MANIFEST="$OC_GLOBAL_DIR/.mb-global-extensions-manifest.json"
# shellcheck source=_lib_agents_md.sh
. "$SKILL_DIR/adapters/_lib_agents_md.sh"
# shellcheck source=_framework.sh
. "$SKILL_DIR/adapters/_framework.sh"
# shellcheck source=_contract.sh
. "$SKILL_DIR/adapters/_contract.sh"
# shellcheck source=_opencode_preflight.sh
. "$SKILL_DIR/adapters/_opencode_preflight.sh"

plugin_body() {
  python3 - "$SKILL_DIR" "${1:-0}" <<'PY'
import json
import sys
from pathlib import Path

runtime = (Path(sys.argv[1]) / "adapters/opencode_plugin.mjs").as_uri()
print("// memory-bank: managed plugin (do not remove marker line)")
print(f"import {{ createMemoryBankPlugin }} from {json.dumps(runtime)};")
print(f"export default createMemoryBankPlugin({{ extended: {str(sys.argv[2] == '1').lower()} }});")
PY
}

opencode_backup_json() {
  _mb_strict_file regular "$OC_JSON" "$MANIFEST" "$PROJECT_ROOT" || return 1
  [ -f "$OC_JSON" ] || return 0
  local b="${1:-}"
  if [ -z "$b" ]; then
    for b in "$OC_JSON".pre-mb-backup.*; do [ ! -L "$b" ] && [ -f "$b" ] && return 0; done
    b=$(mktemp "$OC_JSON.pre-mb-backup.XXXXXXXX") || return 1
  fi
  cp -p "$OC_JSON" "$b" || { rm -f "$b"; return 1; }
}

_opencode_json_operation() {
  [ -f "$OC_JSON" ] || return 0
  local b backup="" paths OC_IO_ROOT="$OC_DIR" OC_IO_WRITTEN=""
  paths="$(_mb_oc_paths "$OC_JSON")" || return 1
  for b in "$OC_JSON".pre-mb-backup.*; do
    if [ ! -L "$b" ] && [ -f "$b" ]; then
      _mb_strict_file regular "$b" "$MANIFEST" "$PROJECT_ROOT" || return 1
      backup=existing; break
    fi
  done
  if [ -z "$backup" ]; then
    backup="$(mktemp "$OC_JSON.pre-mb-backup.XXXXXXXX")" || return 1
    rm -f "$backup" || return 1
    paths="$(_mb_oc_paths "$OC_JSON" "$backup")" || return 1
  fi
  _mb_oc_apply "$MANIFEST" "$PROJECT_ROOT" "$paths" _opencode_checkpoint _opencode_change_json "$backup"
}

_opencode_change_json() {
  if [ "$1" != existing ]; then opencode_backup_json "$1" || return 1; fi
  _opencode_strip_plugin_ref
}

_opencode_strip_plugin_ref() {
  _mb_strict_file regular "$OC_JSON" "$MANIFEST" "$PROJECT_ROOT" || return 1
  [ -f "$OC_JSON" ] || return 0
  local tmp out mode
  if ! tmp=$(jq --arg ref "$PLUGIN_REF" '
    def is_mb: . == $ref or (type == "object" and .package == $ref)
      or (type == "array" and .[0] == $ref);
    reduce ["plugin", "plugins"][] as $key (.;
      if (.[$key] | type) == "array" then
        .[$key] |= map(select(is_mb | not))
        | if (.[$key] | length) == 0 then del(.[$key]) else . end
      else . end)
  ' "$OC_JSON" 2>/dev/null); then return 0; fi
  if [ "$(printf '%s' "$tmp" | jq 'length')" = 0 ]; then
    rm -f "$OC_JSON"
  else
    out="$(mktemp "$(dirname "$OC_JSON")/.opencode.json.mbXXXXXX")" || return 1
    mode="$(mb_file_mode "$OC_JSON")" || return 1
    if ! printf '%s\n' "$tmp" > "$out" || ! chmod "${mode:-644}" "$out" || ! mv "$out" "$OC_JSON"; then
      rm -f "$out"
      return 1
    fi
  fi
}

_opencode_agent_is_partial() {
  head -5 "$1" 2>/dev/null | grep -qiE '^partial:[[:space:]]*true[[:space:]]*$'
}

_opencode_save_manifest() {
  _mb_oc_save_manifest "$@"
}

_opencode_begin_io() {
  _mb_oc_start "$1" "$2" || return 1
  [ -f "$1" ] || _opencode_save_manifest "$1" "$2" "" '{}'
}

_opencode_checkpoint() {
  local extra="${OC_IO_EXTRA:-}"
  [ -n "$extra" ] || extra='{}'
  _opencode_save_manifest "$_MB_OC_IO_RECORD" "$OC_IO_ROOT" "${OC_IO_WRITTEN:-}" "$extra"
}

_opencode_write_owned() {
  local dst="$1" record="$2" root="$3" source="$4" OC_IO_WRITTEN="$1" OC_IO_ROOT="$3"
  _mb_oc_require_owned "$dst" "$record" "$root" || return $?
  _mb_oc_apply "$record" "$root" "$(_mb_oc_source_paths "$dst" "$source")" _opencode_checkpoint _mb_strict_file write "$dst" "$record" "$root" "$source"
}

_opencode_write_agent_file() {
  local src="$1" dst="$2" pipeline="${3:-}" record="${4:-$MANIFEST}" root="${5:-$OC_DIR}" tmp rc=0
  tmp="$(mktemp)"
  if ! "${MB_PYTHON:-python3}" "$SKILL_DIR/adapters/opencode_resources.py" "$src" --skill-dir "$SKILL_DIR" \
    ${pipeline:+--pipeline "$pipeline"} > "$tmp"; then rm -f "$tmp"; return 1; fi
  _opencode_write_owned "$dst" "$record" "$root" "$tmp" || rc=$?
  rm -f "$tmp"
  return "$rc"
}

_opencode_project_pipeline() {
  (cd "$PROJECT_ROOT" && MB_AGENT=opencode MB_PIPELINE_HOST=opencode bash "$SKILL_DIR/scripts/mb-pipeline.sh" path)
}

render_opencode_agents() {
  local pipeline="${1:-}" f dst n=0 failed=0
  [ -n "$pipeline" ] || pipeline="$(_opencode_project_pipeline)" || return $?
  "${MB_PYTHON:-python3}" "$SKILL_DIR/adapters/opencode_models.py" "$pipeline" >/dev/null || return $?
  if [ ! -f "$MANIFEST" ]; then
    echo "[opencode-adapter] not installed in $PROJECT_ROOT; agents not rendered"
    return 0
  fi
  _opencode_begin_io "$MANIFEST" "$OC_DIR" || return 1
  for f in "$SKILL_DIR"/agents/*.md; do
    [ -f "$f" ] || continue
    _opencode_agent_is_partial "$f" && continue
    dst="$AGENT_DIR/$(basename "$f")"
    { [ -e "$dst" ] || [ -L "$dst" ]; } || continue
    if _opencode_write_agent_file "$f" "$dst" "$pipeline"; then
      n=$((n + 1))
    else
      failed=1
      [ ! -f "$_MB_OC_IO_CONTEXT/failed" ] && [ ! -f "$_MB_OC_IO_CONTEXT/pending.json" ] || return 1
    fi
  done
  _opencode_save_manifest "$MANIFEST" "$OC_DIR" "" "$(jq '{plugin_ref,agents_md_owned,platform_limited,platform_limited_notes}' "$MANIFEST")" || return 1
  [ "$failed" = 0 ] || { echo "[opencode-adapter] partial rerender; preserved modified/unmanaged paths" >&2; return 1; }
  echo "[opencode-adapter] agents re-rendered: $n ($AGENT_DIR)"
}

install_opencode() {
  adapter_require_jq "opencode-adapter" || exit 1
  local pipeline
  pipeline="$(_opencode_project_pipeline)" || return $?
  "${MB_PYTHON:-python3}" "$SKILL_DIR/adapters/opencode_models.py" "$pipeline" >/dev/null || return $?
  _mb_strict_file regular "$MANIFEST" "$MANIFEST" "$OC_DIR" || return 1
  _mb_strict_file regular "$PROJECT_ROOT/AGENTS.md" "$MANIFEST" "$PROJECT_ROOT" || return 1
  _mb_strict_file regular "$PROJECT_ROOT/.mb-agents-owners.json" "$MANIFEST" "$PROJECT_ROOT" || return 1
  _opencode_begin_io "$MANIFEST" "$OC_DIR" || return 1
  local owned plugin_tmp plugin_extended=0 f dst failed=0 OC_IO_ROOT="$OC_DIR" OC_IO_WRITTEN=""
  owned=$(_mb_oc_apply "$MANIFEST" "$PROJECT_ROOT" "$(_mb_oc_paths "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/.mb-agents-owners.json")" \
    _opencode_checkpoint bash -euo pipefail -c '
      source "$1/adapters/_lib_agents_md.sh"
      source "$1/adapters/_framework.sh"
      mb_upsert_marked_block() { _mb_oc_upsert "$@"; }
      agents_md_install "$2" opencode "$1"
    ' _ "$SKILL_DIR" "$PROJECT_ROOT") || return 1
  [ "${MB_OC_PARITY_ACCEPTED:-0}" != 1 ] || plugin_extended=1
  plugin_tmp="$(mktemp)" || return 1
  plugin_body "$plugin_extended" > "$plugin_tmp" || { rm -f "$plugin_tmp"; return 1; }
  if ! _opencode_write_owned "$PLUGIN_FILE" "$MANIFEST" "$OC_DIR" "$plugin_tmp"; then failed=1; fi
  rm -f "$plugin_tmp"
  [ ! -f "$_MB_OC_IO_CONTEXT/failed" ] && [ ! -f "$_MB_OC_IO_CONTEXT/pending.json" ] || return 1
  if [ "${MB_INSTALL_ONLY:-}" != opencode ]; then
    if _mb_strict_file regular "$OC_JSON" "$MANIFEST" "$PROJECT_ROOT"; then
      _opencode_json_operation || return 1
    else failed=1; fi
  fi
  for f in "$SKILL_DIR"/commands/*.md; do
    [ -f "$f" ] || continue
    dst="$COMMANDS_DIR/$(basename "$f")"
    if ! _opencode_write_owned "$dst" "$MANIFEST" "$OC_DIR" "$f"; then failed=1; fi
    [ ! -f "$_MB_OC_IO_CONTEXT/failed" ] && [ ! -f "$_MB_OC_IO_CONTEXT/pending.json" ] || return 1
  done
  for f in "$SKILL_DIR"/agents/*.md; do
    [ -f "$f" ] || continue
    _opencode_agent_is_partial "$f" && continue
    dst="$AGENT_DIR/$(basename "$f")"
    if ! _opencode_write_agent_file "$f" "$dst" "$pipeline"; then failed=1; fi
    [ ! -f "$_MB_OC_IO_CONTEXT/failed" ] && [ ! -f "$_MB_OC_IO_CONTEXT/pending.json" ] || return 1
  done
  _opencode_save_manifest "$MANIFEST" "$OC_DIR" "" \
    "{\"plugin_ref\": $(jq -Rn --arg ref "$PLUGIN_REF" '$ref'), \"agents_md_owned\": $owned, $(_opencode_limits)}" || return 1
  [ "$failed" = 0 ] || { echo "[opencode-adapter] partial install; preserved modified/unmanaged paths" >&2; return 1; }
  echo "[opencode-adapter] installed to $PROJECT_ROOT"
}

_opencode_limits() {
  printf '%s' '"platform_limited": ["statusline","role-routing"], "platform_limited_notes": {
    "statusline": "No Claude Code stdin-JSON statusLine surface; no blocking Stop veto in V2.",
    "role-routing": "Native subagent({agent,description,prompt}) discovery works; full governed workflow runtime acceptance is pending."
  }'
}

# Explicit accept-path only. No global lifecycle plugin is installed.
install_global_extensions() {
  adapter_require_jq "opencode-adapter" || return 1
  _mb_strict_file regular "$OC_GLOBAL_MANIFEST" "$OC_GLOBAL_MANIFEST" "$OC_GLOBAL_DIR" || return 1
  _opencode_begin_io "$OC_GLOBAL_MANIFEST" "$OC_GLOBAL_DIR" || return 1
  local f dst agent_count=0 failed=0
  for f in "$SKILL_DIR"/agents/*.md; do
    [ -f "$f" ] || continue
    _opencode_agent_is_partial "$f" && continue
    dst="$OC_GLOBAL_AGENT_DIR/$(basename "$f")"
    if _opencode_write_agent_file "$f" "$dst" "" "$OC_GLOBAL_MANIFEST" "$OC_GLOBAL_DIR"; then
      agent_count=$((agent_count + 1))
    else failed=1; fi
    [ ! -f "$_MB_OC_IO_CONTEXT/failed" ] && [ ! -f "$_MB_OC_IO_CONTEXT/pending.json" ] || return 1
  done
  _opencode_save_manifest "$OC_GLOBAL_MANIFEST" "$OC_GLOBAL_DIR" "" \
    "{\"agents_installed\": $agent_count, $(_opencode_limits)}" || return 1
  [ "$failed" = 0 ] || { echo "[opencode-adapter] partial global install; preserved modified/unmanaged paths" >&2; return 1; }
  echo "[opencode-adapter] global agents: $agent_count installed -> $OC_GLOBAL_AGENT_DIR"
  [ "$agent_count" -gt 0 ]
}

uninstall_opencode() {
  if [ ! -f "$MANIFEST" ]; then
    echo "[opencode-adapter] no manifest found, nothing to uninstall"
    return 0
  fi
  adapter_require_jq "opencode-adapter" || exit 1
  adapter_remove_manifest_files "$MANIFEST" "$OC_DIR" || return 1
  if [ "${MB_INSTALL_ONLY:-}" != opencode ]; then _opencode_strip_plugin_ref || return 1; fi
  _mb_strict_file regular "$PROJECT_ROOT/AGENTS.md" "$MANIFEST" "$PROJECT_ROOT" || return 1
  agents_md_uninstall "$PROJECT_ROOT" "opencode" || return 1
  rm -f "$MANIFEST" || return 1
  rmdir "$PLUGIN_DIR" "$COMMANDS_DIR" "$AGENT_DIR" "$OC_DIR" 2>/dev/null || true
  echo "[opencode-adapter] uninstalled from $PROJECT_ROOT"
}

case "$ACTION" in install|install-global-agents|render-agents) trap _mb_oc_exit EXIT ;; esac
case "$ACTION" in
  preflight) opencode_preflight ;;
  preflight-remove)
    opencode_preflight_remove "$MANIFEST" "$OC_DIR"
    opencode_preflight_instructions ;;
  install) install_opencode ;;
  uninstall) uninstall_opencode ;;
  install-global-agents) install_global_extensions ;;
  render-agents) render_opencode_agents "${3:-}" ;;
  *) echo "Usage: $0 install|uninstall|install-global-agents [PROJECT_ROOT] | render-agents PROJECT_ROOT [PIPELINE]" >&2; exit 1 ;;
esac
adapter_contract_require_functions install_opencode uninstall_opencode >/dev/null
