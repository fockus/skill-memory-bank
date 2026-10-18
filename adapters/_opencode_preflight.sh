# shellcheck shell=bash
# Read-only checks before the selective installer starts any host mutation.
opencode_preflight_instructions() {
  local f owners="$PROJECT_ROOT/.mb-agents-owners.json"
  for f in "$PROJECT_ROOT/AGENTS.md" "$owners"; do
    _mb_strict_file regular "$f" "$MANIFEST" "$PROJECT_ROOT" || return 1
  done
  if [ -f "$owners" ] && ! jq -e 'type == "object" and
    ((.owners // []) | type == "array" and all(.[]; type == "string"))' "$owners" >/dev/null; then
    echo "[opencode] invalid owners record: $owners; restore it before retrying" >&2
    return 1
  fi
}

opencode_preflight() {
  local f dst pipeline
  adapter_require_jq opencode-adapter || return 1
  pipeline="$(_opencode_project_pipeline)" || return 1
  "${MB_PYTHON:-python3}" "$SKILL_DIR/adapters/opencode_models.py" "$pipeline" >/dev/null || return 1
  _mb_strict_file uninstall-manifest "$MANIFEST" "$MANIFEST" "$OC_DIR" || return 1
  opencode_preflight_instructions || return 1
  _mb_oc_require_owned "$PLUGIN_FILE" "$MANIFEST" "$OC_DIR" || return 1
  for f in "$SKILL_DIR"/commands/*.md; do
    [ -f "$f" ] || continue
    _mb_oc_require_owned "$COMMANDS_DIR/$(basename "$f")" "$MANIFEST" "$OC_DIR" || return 1
  done
  if [ "${MB_OC_PREFLIGHT_EXTENSIONS:-0}" = 1 ]; then
    _mb_strict_file uninstall-manifest "$OC_GLOBAL_MANIFEST" "$OC_GLOBAL_MANIFEST" "$OC_GLOBAL_DIR" || return 1
  fi
  for f in "$SKILL_DIR"/agents/*.md; do
    [ -f "$f" ] || continue
    _opencode_agent_is_partial "$f" && continue
    dst="$(basename "$f")"
    _mb_oc_require_owned "$AGENT_DIR/$dst" "$MANIFEST" "$OC_DIR" || return 1
    if [ "${MB_OC_PREFLIGHT_EXTENSIONS:-0}" = 1 ]; then
      _mb_oc_require_owned "$OC_GLOBAL_AGENT_DIR/$dst" "$OC_GLOBAL_MANIFEST" "$OC_GLOBAL_DIR" || return 1
    fi
  done
}

opencode_preflight_remove() {
  local record="$1" root="$2" file kind
  _mb_strict_file uninstall-manifest "$record" "$record" "$root" || return 1
  [ -f "$record" ] || return 0
  local files
  files="$(jq -r '.files[]?' "$record")" || return 1
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    case "$file" in
      "$root/AGENTS.md") _mb_strict_file regular "$file" "$record" "$root" || return 1; continue ;;
      "$root"/*) ;;
      *) continue ;;
    esac
    kind=owned
    [ "$file" != "$root/skills/memory-bank" ] || kind=owned-alias
    _mb_oc_require_owned "$file" "$record" "$root" "$kind" || return 1
  done <<< "$files"
}
