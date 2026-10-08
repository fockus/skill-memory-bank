# shellcheck shell=bash
# adapters/_lib_pi_subagent.sh — Pi agent-roster + subagent-dispatch install
# helpers (sourced by pi.sh). Extracted for SRP / file-size, same convention
# as adapters/_lib_pi_global.sh.
#
# adapter-parity Task 4 (REQ-008/009/022, design.md "Subagent dispatch").
# Expects the sourcing script to have defined these globals beforehand (they
# are resolved at call time): SKILL_DIR, PI_AGENT_DIR, and the
# _install_pi_extension_template helper (both defined in pi.sh itself).
#
# Usage (from pi.sh):
#   # shellcheck source=./_lib_pi_subagent.sh
#   . "$(dirname "$0")/_lib_pi_subagent.sh"

# Partial-agent filter for the Pi roster install below. Mirrors
# adapters/opencode.sh's `_opencode_agent_is_partial` REGEX EXACTLY (same
# convention: a partial is prepended into a dispatchable agent's own prompt
# by `/mb work`, never dispatched on its own — e.g.
# mb-engineering-core/mb-tooling-core) — kept as pi.sh's own copy rather
# than a cross-file shared helper so this task never has to touch
# adapters/opencode.sh.
_pi_agent_is_partial() {
  head -5 "$1" 2>/dev/null | grep -qiE '^partial:[[:space:]]*true[[:space:]]*$'
}

# Installs the non-partial agents/*.md roster into the Pi-NATIVE
# agent-registry discovery directory (<agentDir>/agents/ — design.md
# "Subagent dispatch": the same convention Pi's own reference
# `examples/extensions/subagent/index.ts` discovers agent definitions from
# via `getAgentDir()/agents`). Only ever invoked from
# install_global_extensions (the explicit accepted-offer path) — never from
# install_agents_md_mode's normal per-client flow (NFR-001: a declined/plain
# install never creates this directory). Prints one installed dest path per
# line to stdout so the caller can fold it into the global manifest's files[].
_install_pi_agents_roster() {
  local dest_dir="$PI_AGENT_DIR/agents"
  mkdir -p "$dest_dir"
  local f
  for f in "$SKILL_DIR"/agents/*.md; do
    [ -f "$f" ] || continue
    _pi_agent_is_partial "$f" && continue
    # Composed partials, `effort` → `thinking`, pi tool names (scripts/mb-agent-render.py).
    local tmp
    tmp="$(mktemp "$dest_dir/.$(basename "$f").mbtmp.XXXXXX")"
    python3 "$SKILL_DIR/scripts/mb-agent-render.py" "$f" --skill-dir "$SKILL_DIR" \
      --host pi > "$tmp"
    chmod 644 "$tmp"
    _pi_owned_put "$tmp" "$dest_dir/$(basename "$f")"
    printf '%s\n' "$dest_dir/$(basename "$f")"
  done
}

# Copy adapters/pi_subagent_extension.ts + its sibling
# pi_subagent_dispatch_core.mjs → the GLOBAL Pi extensions dir. Registers
# the D-09 guaranteed-floor role-dispatch tool (REQ-008/009) and the REQ-022
# native `/mb` command surface. Same fail-open template-copy contract as
# _install_graph_rag_extension / install_global_extensions' session-memory
# install (returns "false" on a missing source, never fatal).
#
# The dispatch-core module is copied VERBATIM (same basename, no rename,
# unlike the renamed *.ts siblings) because pi_subagent_extension.ts's
# `import ... from "./pi_subagent_dispatch_core.mjs"` is baked as literal
# text (placeholder substitution only touches __MB_*__ tokens) — it must
# resolve to a same-named sibling file post-install. Fail-open per file:
# either can be individually absent without the other failing.
_install_pi_subagent_extension() {
  local dest_dir="$PI_AGENT_DIR/extensions"
  local ok_ext ok_core
  ok_ext=$(_install_pi_extension_template \
    "$SKILL_DIR/adapters/pi_subagent_extension.ts" \
    "$dest_dir/memory-bank-subagent.ts" "" owned)
  ok_core=$(_install_pi_extension_template \
    "$SKILL_DIR/adapters/pi_subagent_dispatch_core.mjs" \
    "$dest_dir/pi_subagent_dispatch_core.mjs" "" owned)
  if [ "$ok_ext" = "true" ] && [ "$ok_core" = "true" ] && _install_pi_native_helpers; then
    echo "true"
  else
    echo "false"
  fi
}

# The native extension imports its pi_native_*.mjs siblings relatively, and
# bin/mb-pi imports the bootstrap from the same folder, so host authority is one
# module instance. Verbatim copies; .mjs is not auto-loaded by Pi discovery.
# Prints installed paths; fails when a helper is missing from the bundle.
_install_pi_native_helpers() {
  local f found=0
  for f in "$SKILL_DIR"/adapters/pi_native_*.mjs; do
    [ -f "$f" ] || continue
    _pi_owned_copy "$f" "$PI_AGENT_DIR/extensions/$(basename "$f")" >&2
    found=1
  done
  [ "$found" = 1 ]
}

# Owned opt-in entrypoint <agentDir>/bin/mb-pi (AGR-058). Never replaces a
# foreign file at that name; ordinary pi, PATH and shell rc files are untouched.
# The ESM lives in bin/mb-pi.mjs behind a sh launcher: an extensionless file is
# loaded as CommonJS when the agentDir package.json says {"type":"commonjs"}.
_pi_entrypoint() { printf '%s\n' "$PI_AGENT_DIR/bin/mb-pi"; }
_pi_entrypoint_module() { printf '%s\n' "$PI_AGENT_DIR/bin/mb-pi.mjs"; }

_pi_launcher_write() {
  cat > "$1" <<'EOF'
#!/bin/sh
# Memory Bank managed Pi launcher (owned by adapters/pi.sh): runs mb-pi.mjs from
# the directory of the real launcher file, following symlinks.
self=$0
while [ -L "$self" ]; do
  link=$(readlink -- "$self")
  case $link in
    /*) self=$link ;;
    *) self=$(dirname -- "$self")/$link ;;
  esac
done
dir=$(CDPATH='' cd -- "$(dirname -- "$self")" && pwd -P) || exit 1
# Same Node as Pi's own launcher: the Pi installer's node is not on shell PATH.
pi_node_bin=${XDG_DATA_HOME:-$HOME/.local/share}/pi-node/current/bin
if [ -x "$pi_node_bin/node" ]; then
  PATH=$pi_node_bin:$PATH
  export PATH
fi
exec node "$dir/mb-pi.mjs" "$@"
EOF
}

_pi_path_foreign() {
  [ -e "$1" ] || [ -L "$1" ] || return 1
  [ "$(_pi_owned_state "$1" "$2")" = foreign ]
}

_pi_entrypoint_foreign() {
  local tmp launcher_sha
  tmp="$(mktemp)"
  _pi_launcher_write "$tmp"
  launcher_sha="$(_pi_sha256 "$tmp")"
  rm -f "$tmp"
  _pi_path_foreign "$(_pi_entrypoint)" "$launcher_sha" ||
    _pi_path_foreign "$(_pi_entrypoint_module)" "$(_pi_sha256 "$SKILL_DIR/adapters/pi_managed_entrypoint.mjs")"
}

_install_pi_entrypoint() {
  local tmp
  _pi_owned_copy "$SKILL_DIR/adapters/pi_managed_entrypoint.mjs" "$(_pi_entrypoint_module)" 644
  tmp="$(mktemp "$(_pi_entrypoint).mbtmp.XXXXXX")"
  _pi_launcher_write "$tmp"
  chmod 755 "$tmp"
  _pi_owned_put "$tmp" "$(_pi_entrypoint)"
}
