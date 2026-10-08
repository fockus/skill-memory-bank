# shellcheck shell=bash
# adapters/_lib_pi_extensions.sh — Pi extension installers, extracted from
# adapters/pi.sh for SRP / file-size (same convention as _lib_pi_global.sh and
# _lib_pi_subagent.sh). Not an executable entry point: no shebang, no main.
# Source it from adapters/pi.sh AFTER _lib_pi_subagent.sh is available.
#
# Everything here resolves SKILL_DIR / PROJECT_ROOT / PI_AGENT_DIR at call
# time, exactly as it did while inlined — the caller owns those variables.

# Copy a Pi extension template ($1=src) → $2=dest, substituting the
# __MB_SKILL_DIR_JSON__ / __MB_PROJECT_ROOT_JSON__ placeholders with
# JSON-encoded paths (@json) so the emitted .ts is syntactically valid and
# robust to spaces/quotes/backslashes in the paths. jq reads the template
# raw (--rawfile) and emits raw (-r); gsub replacements are literal, so no
# sed-escaping hazard. Atomic (tmp + mv). Fail-open contract: a missing
# source file is not fatal — echoes "false" so the caller can record a
# skipped state. adapter-parity T3: shared by the pre-existing project-local
# graph-rag install below AND install_global_extensions() (the new opt-in
# accept-path installer), so both destinations stay byte-for-byte identical
# in how they substitute placeholders.
#
# $3 (optional) = the value to bake for __MB_PROJECT_ROOT_JSON__; defaults to
# $PROJECT_ROOT (the project-local install's own contract). CRITICAL: the
# GLOBAL accept-path installer below passes an EXPLICIT EMPTY STRING here —
# baking the accept-time $PROJECT_ROOT into a file installed to the GLOBAL
# ~/.pi/agent/extensions/ dir would make every future Pi session, in every
# OTHER project, read/write session capture and graph queries against the
# accept-time project's .memory-bank (a cross-project data leak). An empty
# string is falsy in the extensions' own `PROJECT_ROOT || ctx.cwd` /
# `params.projectRoot || PROJECT_ROOT || process.cwd()` fallback chains, so
# the live per-session cwd always wins for a global install instead.
#
# $4 = "owned" routes the write through _pi_owned_put (global installs under
# $PI_AGENT_DIR: hash ledger, preimage of a replaced foreign file).
_install_pi_extension_template() {
  local src="$1" dest="$2" proj_root="${3-$PROJECT_ROOT}" owned="${4:-}"
  if [ ! -f "$src" ]; then
    echo "false"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  local tmp="$dest.mbtmp"
  if jq -rn \
      --arg skill "$SKILL_DIR" \
      --arg proj "$proj_root" \
      --rawfile tpl "$src" \
      '$tpl
       | gsub("__MB_SKILL_DIR_JSON__"; ($skill | @json))
       | gsub("__MB_PROJECT_ROOT_JSON__"; ($proj | @json))' \
      > "$tmp" 2>/dev/null; then
    if [ "$owned" = "owned" ]; then
      _pi_owned_put "$tmp" "$dest" >&2
    else
      mv "$tmp" "$dest"
    fi
    echo "true"
  else
    rm -f "$tmp"
    echo "false"
    return 0
  fi
}

# Copy adapters/pi_graph_rag_extension.ts → $PROJECT_ROOT/.pi/extensions/.
# Provides native Pi tool wrappers (code_context, graph_neighbors,
# graph_impact, graph_tests) that delegate to scripts/mb-*-query.py and
# scripts/mb-code-context.py. Fail-open contract: missing source file
# is not fatal — returns "false" so caller can record skipped state.
# Pre-existing, unconditional per-project behavior (runs whenever `pi` is a
# --clients target) — NOT gated by the adapter-parity extension offer; left
# unchanged by T3 (see install_global_extensions for the new opt-in path).
# This install IS project-scoped (dest lives under $PROJECT_ROOT/.pi/), so
# baking the real $PROJECT_ROOT (the template helper's default 3rd arg) is
# correct here — only the GLOBAL install below must not.
_install_graph_rag_extension() {
  _install_pi_extension_template \
    "$SKILL_DIR/adapters/pi_graph_rag_extension.ts" \
    "$PROJECT_ROOT/.pi/extensions/memory-bank-graph-rag.ts"
}

# adapter-parity Task 4 (REQ-008/009/022): agent-roster + subagent-dispatch
# install helpers, extracted to _lib_pi_subagent.sh for SRP / file-size
# (same convention as _lib_pi_global.sh above) — see that file for
# _pi_agent_is_partial / _install_pi_agents_roster /
# _install_pi_subagent_extension.
# shellcheck source=./_lib_pi_subagent.sh
. "$(dirname "$0")/_lib_pi_subagent.sh"
# shellcheck source=./_lib_pi_owned.sh
. "$(dirname "$0")/_lib_pi_owned.sh"

# adapter-parity T3 (REQ-006/007/010): installs BOTH parity extensions
# (session-memory + graph-rag) into the GLOBAL Pi extensions dir
# ($HOME/.pi/agent/extensions/) — the opt-in "accept" path consumed by
# install.sh's mb_install_host_extensions "pi" seam (T2). Unlike
# _install_graph_rag_extension above (unconditional, project-local,
# pre-existing behavior inherited from before this spec), this function is
# ONLY ever invoked after explicit user consent (REQ-004) — never from
# install_pi()/install_agents_md_mode's normal per-client flow.
#
# Task 4 (REQ-008/009/022) extends this SAME accept path with the agent
# roster + subagent-dispatch extension (design.md's diagram nests
# "agents/*.md for role dispatch" directly under the Pi accept branch) —
# no new offer/flag/seam, same "pi" host offer as T3.
#
# Usage: adapters/pi.sh install-global-extensions [PROJECT_ROOT]
# Fail-open per extension (same contract as _install_pi_extension_template);
# returns 1 only when session-memory, graph-rag, AND subagent-dispatch all
# fail, so one missing template doesn't mask the others' success.
#
# CRITICAL (cross-project isolation): the 3rd arg "" forces
# __MB_PROJECT_ROOT_JSON__ to bake as an empty string — NOT $PROJECT_ROOT —
# for every extension here. A global install serves every Pi project, not
# just the one active at accept time; the empty bake makes each extension's
# own runtime fallback (ctx.cwd / process.cwd()) resolve the LIVE project on
# every session/tool-call instead of a frozen accept-time path.
#
# Stage 5 (AGR-058): every write is owned (hash ledger + preimages, see
# _lib_pi_owned.sh). Refusals (foreign mb-pi, unreadable settings) happen before
# the first write; the manifest is marked in_progress with no capabilities until
# the run completes, so an interrupted install declares nothing it did not load.
install_global_extensions() {
  adapter_require_jq "pi-adapter" || return 1
  local dest_dir="$PI_AGENT_DIR/extensions"
  local global_manifest="$PI_AGENT_DIR/.mb-global-extensions-manifest.json"
  local version
  version="$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)"
  if _pi_entrypoint_foreign; then
    echo "[pi-adapter] refusing: $(_pi_entrypoint) or $(_pi_entrypoint_module) exists and is not owned by Memory Bank" >&2
    return 1
  fi
  pi_settings_tintin check || return 1
  local previous_files='[]'
  [ -f "$global_manifest" ] && previous_files="$(jq -c '.files // []' "$global_manifest" 2>/dev/null || echo '[]')"
  mkdir -p "$PI_AGENT_DIR"
  adapter_write_manifest "$global_manifest" "pi" "$version" "$previous_files" '{"install_state": "in_progress"}'

  local ok_session ok_graph ok_subagent
  ok_session=$(_install_pi_extension_template \
    "$SKILL_DIR/adapters/pi_session_memory_extension.ts" \
    "$dest_dir/memory-bank-session.ts" "" owned)
  ok_graph=$(_install_pi_extension_template \
    "$SKILL_DIR/adapters/pi_graph_rag_extension.ts" \
    "$dest_dir/memory-bank-graph-rag.ts" "" owned)
  ok_subagent=$(_install_pi_subagent_extension)

  local agent_files agent_count
  agent_files="$(_install_pi_agents_roster)"
  agent_count=0
  if [ -n "$agent_files" ]; then
    agent_count=$(printf '%s\n' "$agent_files" | grep -c .)
  fi

  local tintin_entry=""
  if [ "$ok_subagent" = "true" ]; then
    tintin_entry="$(pi_settings_tintin add)"
    # Our own entry from an earlier run is still ours, not the user's.
    local previous_entry
    previous_entry="$(jq -r '.settings.tintin_entry // empty' "$(_pi_ledger)" 2>/dev/null || true)"
    if [ "$tintin_entry" = preexisting ] && { [ "$previous_entry" = added ] || [ "$previous_entry" = created ]; }; then
      tintin_entry="$previous_entry"
    fi
    # shellcheck disable=SC2016  # jq variables, not shell
    _pi_ledger_update '.settings.tintin_entry = $e' --arg e "$tintin_entry"
    _install_pi_entrypoint
  fi

  echo "[pi-adapter] parity extensions: session-memory=$ok_session graph-rag=$ok_graph subagent-dispatch=$ok_subagent agents=$agent_count -> $dest_dir"

  # Global extensions manifest (Task 4, new): tracks every file THIS
  # accept-path install wrote (extensions + agent roster), the artifact
  # Task 8's upgrade/uninstall lifecycle needs. T3 shipped without one for
  # this path — this is the first manifest write here, additive only.
  local files_json
  files_json=$(
    {
      if [ "$ok_session" = "true" ]; then printf '%s\n' "$dest_dir/memory-bank-session.ts"; fi
      if [ "$ok_graph" = "true" ]; then printf '%s\n' "$dest_dir/memory-bank-graph-rag.ts"; fi
      if [ "$ok_subagent" = "true" ]; then
        printf '%s\n' "$dest_dir/memory-bank-subagent.ts"
        printf '%s\n' "$dest_dir/pi_subagent_dispatch_core.mjs"
        for helper in "$SKILL_DIR"/adapters/pi_native_*.mjs; do
          printf '%s\n' "$dest_dir/$(basename "$helper")"
        done
        _pi_entrypoint
        _pi_entrypoint_module
      fi
      if [ -n "$agent_files" ]; then printf '%s\n' "$agent_files"; fi
      true
    } | adapter_json_array_from_lines
  )
  local session_bool graph_bool subagent_bool
  session_bool=$( [ "$ok_session" = "true" ] && echo true || echo false )
  graph_bool=$( [ "$ok_graph" = "true" ] && echo true || echo false )
  subagent_bool=$( [ "$ok_subagent" = "true" ] && echo true || echo false )
  # Codex review (T4 fix cycle) — honest-degradation note, ahead of Task 7's
  # full platform_limited rollout across all 8 client manifests. Investigated
  # with file:line evidence (backlog I-121): NO host — Pi included — has a
  # deterministic /mb work per-role headless dispatch path today;
  # commands/work.md 5a dispatches exclusively via the Claude Code Task tool.
  # "subagents" (the existing closed-vocabulary term Codex uses) would be
  # INACCURATE here — Pi DOES have a working opt-in subagent-dispatch tool
  # (mb_dispatch_subagent) and the --role registry primitive; what's missing
  # is /mb work's OWN routing wiring to any non-CC host, which is out of this
  # single task's scope. "role-routing" is a new, narrower term pending
  # Task 7's final closed vocabulary.
  local platform_limited_json='["role-routing"]'
  local platform_limited_notes_json
  platform_limited_notes_json=$(jq -n \
    --arg note "Pi's opt-in mb_dispatch_subagent tool + the mb-subinvoke-resolve.sh --role registry primitive are the D-09 guaranteed floor; deterministic /mb work per-role dispatch on Pi (or any non-Claude-Code host) has no harness yet — see backlog I-121/I-122." \
    '{"role-routing": $note}')
  # Provenance of the managed runtime: which skill bundle, which pinned package,
  # which backend new runs select by default (AGR-088: Tintin; Nico opt-in).
  local native_json='null'
  if [ "$subagent_bool" = "true" ]; then
    native_json=$(jq -n --arg skill "$SKILL_DIR" --arg version "$version" \
      --arg pkg "$PI_TINTIN_PACKAGE" --arg entry "$tintin_entry" --arg ep "$(_pi_entrypoint)" \
      '{skill_dir: $skill, skill_version: $version, default_backend: "tintin", tintin_package: $pkg,
        tintin_entry: $entry, nico: "opt-in (mb-pi --with-nico), runtime inventory UNVERIFIED", entrypoint: $ep}')
  fi
  adapter_write_manifest \
    "$global_manifest" \
    "pi" \
    "$version" \
    "$files_json" \
    "{\"install_state\": \"complete\", \"session_memory\": $session_bool, \"graph_rag\": $graph_bool, \"subagent_dispatch\": $subagent_bool, \"managed_entrypoint\": $subagent_bool, \"native\": $native_json, \"agents_installed\": $agent_count, \"platform_limited\": $platform_limited_json, \"platform_limited_notes\": $platform_limited_notes_json}"

  if [ "$ok_session" != "true" ] && [ "$ok_graph" != "true" ] && [ "$ok_subagent" != "true" ]; then
    return 1
  fi
  return 0
}

# Reverses install_global_extensions: unchanged owned files are removed,
# replaced preimages restored, user edits kept, and the Tintin settings entry
# dropped only when this installer added it.
uninstall_global_extensions() {
  adapter_require_jq "pi-adapter" || return 1
  local ledger entry
  ledger="$(_pi_ledger)"
  if [ -f "$ledger" ]; then
    entry="$(jq -r '.settings.tintin_entry // empty' "$ledger")"
    case "$entry" in
      added) pi_settings_tintin remove ;;
      created) pi_settings_tintin remove 1 ;;
    esac
  fi
  _pi_owned_remove_all
  rm -f "$PI_AGENT_DIR/.mb-global-extensions-manifest.json"
  local dir
  for dir in extensions agents bin; do
    rmdir "$PI_AGENT_DIR/$dir" 2>/dev/null || true
  done
  echo "[pi-adapter] global extensions uninstalled from $PI_AGENT_DIR"
}
