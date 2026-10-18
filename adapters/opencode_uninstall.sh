# shellcheck shell=bash
# Sourced by uninstall.sh: OpenCode's merged instructions and global role roster.
oc_agents_status=0
_mb_strict_file regular "$OPENCODE_DIR/AGENTS.md" "$MANIFEST" "$OPENCODE_DIR" || oc_agents_status=$?
case "$oc_agents_status" in 0|1) ;; *) return "$oc_agents_status" ;; esac
if [ "$oc_agents_status" = 0 ] && [ -f "$OPENCODE_DIR/AGENTS.md" ]; then
  oc_agents_mode=$(mb_file_mode "$OPENCODE_DIR/AGENTS.md") || return 1
  [ -n "$oc_agents_mode" ] || { echo "[opencode] cannot read mode: $OPENCODE_DIR/AGENTS.md" >&2; return 1; }
  oc_cleanup_status=0
  for oc_marker in mb-key-rules memory-bank-opencode memory-bank; do
    [ -f "$OPENCODE_DIR/AGENTS.md" ] || break
    oc_marker_status=0
    grep -qF "<!-- $oc_marker:start -->" "$OPENCODE_DIR/AGENTS.md" || oc_marker_status=$?
    case "$oc_marker_status" in 0) ;; 1) continue ;; *) oc_cleanup_status=$oc_marker_status; break ;; esac
    run_texttool strip-between-markers --path "$OPENCODE_DIR/AGENTS.md" \
      --start-marker "<!-- $oc_marker:start -->" --end-marker "<!-- $oc_marker:end -->" || { oc_cleanup_status=$?; break; }
    echo "  OpenCode AGENTS.md cleaned ($oc_marker)"
  done
  if [ -f "$OPENCODE_DIR/AGENTS.md" ]; then chmod "$oc_agents_mode" "$OPENCODE_DIR/AGENTS.md" || return 1; fi
  [ "$oc_cleanup_status" = 0 ] || return "$oc_cleanup_status"
fi

if [ -f "$OPENCODE_DIR/.mb-global-extensions-manifest.json" ]; then
  adapter_remove_manifest_files "$OPENCODE_DIR/.mb-global-extensions-manifest.json" "$OPENCODE_DIR" || return 1
  rm -f "$OPENCODE_DIR/.mb-global-extensions-manifest.json" || return 1
  rmdir "$OPENCODE_DIR/agent" 2>/dev/null || true
fi
