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
    cp "$f" "$dest_dir/$(basename "$f")"
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
    "$dest_dir/memory-bank-subagent.ts" "")
  ok_core=$(_install_pi_extension_template \
    "$SKILL_DIR/adapters/pi_subagent_dispatch_core.mjs" \
    "$dest_dir/pi_subagent_dispatch_core.mjs" "")
  if [ "$ok_ext" = "true" ] && [ "$ok_core" = "true" ]; then
    echo "true"
  else
    echo "false"
  fi
}
