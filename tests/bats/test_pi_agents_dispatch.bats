#!/usr/bin/env bats
# Tests for adapter-parity Task 4 (Pi subagent definitions + role dispatch,
# REQ-008/009/022).
#
# Contract under test:
#   1. `adapters/pi.sh install-global-extensions` also installs the bundled
#      `agents/*.md` roster into the Pi-native agent-registry discovery dir
#      (<agentDir>/agents/, design.md "Subagent dispatch": the same convention
#      Pi's own reference `examples/extensions/subagent/index.ts` uses),
#      excluding partials (mirrors adapters/opencode.sh's
#      `_opencode_agent_is_partial` filter) — the global extensions manifest
#      lists every installed agent file.
#   2. `scripts/mb-subinvoke-resolve.sh --agent pi --role <name>` resolves the
#      D-09 guaranteed-floor headless dispatch template WITH the role's
#      --tools/--append-system-prompt scoping baked in (load-bearing for
#      latency/cost per design.md's measured finding) — never unscoped.
#   3. `adapters/pi_subagent_extension.ts` registers a dispatch tool whose
#      failure path NEVER drops silently (REQ-009: inline-execution warning)
#      and a native `/mb` `registerCommand` (REQ-022).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RESOLVE="$REPO_ROOT/scripts/mb-subinvoke-resolve.sh"
  PROJECT="$(mktemp -d)"
  mkdir -p "$PROJECT/.memory-bank"
  SANDBOX_HOME="$(mktemp -d)"
  export HOME="$SANDBOX_HOME"
  unset MB_AGENT MB_SUBINVOKE_CMD MB_SUBINVOKE_MODEL 2>/dev/null || true
  command -v jq >/dev/null || skip "jq required"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
  [ -n "${SANDBOX_HOME:-}" ] && [ -d "$SANDBOX_HOME" ] && rm -rf "$SANDBOX_HOME"
}

# ═══════════════════════════════════════════════════════════════
# 1. Install — agent roster lands in the Pi-native discovery dir
# ═══════════════════════════════════════════════════════════════

@test "pi agents: install-global-extensions installs the non-partial agent roster into <agentDir>/agents/" {
  run bash "$REPO_ROOT/adapters/pi.sh" install-global-extensions "$PROJECT"
  [ "$status" -eq 0 ]
  local dest="$SANDBOX_HOME/.pi/agent/agents"
  [ -d "$dest" ]
  [ -f "$dest/mb-backend.md" ]
  [ -f "$dest/mb-reviewer.md" ]
}

@test "pi agents: partials (mb-engineering-core, mb-tooling-core) are excluded from the roster" {
  run bash "$REPO_ROOT/adapters/pi.sh" install-global-extensions "$PROJECT"
  [ "$status" -eq 0 ]
  local dest="$SANDBOX_HOME/.pi/agent/agents"
  [ ! -f "$dest/mb-engineering-core.md" ]
  [ ! -f "$dest/mb-tooling-core.md" ]
}

@test "pi agents: installed roster count matches the source minus partials" {
  run bash "$REPO_ROOT/adapters/pi.sh" install-global-extensions "$PROJECT"
  [ "$status" -eq 0 ]
  local dest="$SANDBOX_HOME/.pi/agent/agents"
  local src_count dest_count
  src_count=$(find "$REPO_ROOT/agents" -maxdepth 1 -name '*.md' ! -name 'mb-engineering-core.md' ! -name 'mb-tooling-core.md' | wc -l | tr -d ' ')
  dest_count=$(find "$dest" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
  [ "$src_count" = "$dest_count" ]
}

@test "pi agents: global extensions manifest lists the installed agent files" {
  run bash "$REPO_ROOT/adapters/pi.sh" install-global-extensions "$PROJECT"
  [ "$status" -eq 0 ]
  local manifest="$SANDBOX_HOME/.pi/agent/.mb-global-extensions-manifest.json"
  [ -f "$manifest" ]
  jq -e '.files[] | select(test("agents/mb-backend.md$"))' "$manifest" >/dev/null
  jq -e '[.files[] | select(test("agents/mb-engineering-core.md$"))] | length == 0' "$manifest" >/dev/null
}

@test "pi agents: global extensions manifest declares the honest role-routing gap (post-review, backlog I-121/I-122)" {
  run bash "$REPO_ROOT/adapters/pi.sh" install-global-extensions "$PROJECT"
  [ "$status" -eq 0 ]
  local manifest="$SANDBOX_HOME/.pi/agent/.mb-global-extensions-manifest.json"
  [ -f "$manifest" ]
  jq -e '.platform_limited == ["role-routing"]' "$manifest" >/dev/null
  jq -e '.platform_limited_notes["role-routing"] | test("I-121")' "$manifest" >/dev/null
}

@test "pi agents: subagent-dispatch extension (+ its dispatch-core sibling) is installed alongside the roster" {
  run bash "$REPO_ROOT/adapters/pi.sh" install-global-extensions "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$SANDBOX_HOME/.pi/agent/extensions/memory-bank-subagent.ts" ]
  [ -f "$SANDBOX_HOME/.pi/agent/extensions/pi_subagent_dispatch_core.mjs" ]
  ! grep -qE '__MB_(SKILL_DIR|PROJECT_ROOT)_JSON__' "$SANDBOX_HOME/.pi/agent/extensions/memory-bank-subagent.ts"
}

@test "pi agents: a declined install never creates the agents dir (NFR-001)" {
  # install-global-extensions is only reachable via the explicit accepted-
  # offer path (install.sh's mb_install_host_extensions) — a plain project
  # install (no extensions) must not touch ~/.pi/agent/agents/ at all.
  run bash "$REPO_ROOT/adapters/pi.sh" install "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -d "$SANDBOX_HOME/.pi/agent/agents" ]
}

# ═══════════════════════════════════════════════════════════════
# 2. Dispatch resolver — role-scoped --tools/--append-system-prompt
# ═══════════════════════════════════════════════════════════════

@test "subinvoke-resolve: --agent pi --role mb-backend resolves a scoped headless template" {
  run bash "$RESOLVE" --agent pi --role mb-backend
  [ "$status" -eq 0 ]
  [[ "$output" == *"pi "* ]]
  [[ "$output" == *"--no-session"* ]]
  [[ "$output" == *"--tools"* ]]
  [[ "$output" == *"--append-system-prompt"* ]]
  [[ "$output" == *"\$MB_FANOUT_PROMPT"* ]]
}

@test "subinvoke-resolve: pi --role template's --tools carries the role's tools TRANSLATED to Pi's real (lowercase) names" {
  run bash "$RESOLVE" --agent pi --role mb-backend
  [ "$status" -eq 0 ]
  # mb-backend.md's frontmatter is `Bash, Read, Write, Edit, Grep, Glob,
  # SendMessage` — Pi's own --tools allowlist is an exact, case-sensitive
  # match against its built-in tool names (verified against the installed
  # @earendil-works/pi-coding-agent SDK: read/bash/edit/write/grep/find/ls).
  # The CC-capitalized names must NEVER reach the template unmatched — that
  # would silently zero out the dispatched subagent's tool set.
  [[ "$output" == *"bash"* ]]
  [[ "$output" == *"read"* ]]
  [[ "$output" == *"find"* ]] # Glob -> find (Pi's closest built-in)
  [[ "$output" != *"Bash"* ]]
  [[ "$output" != *"SendMessage"* ]] # no Pi equivalent, dropped
}

# Extracts the (now printf-%q-escaped, unquoted) --append-system-prompt path
# out of a resolved template and un-escapes it back to a real filesystem
# path via `eval` on a single, isolated token (safe here: the value being
# unescaped is OUR OWN mktemp output from the resolver under test, not
# attacker input).
_extract_append_system_prompt_path() {
  local tmpl="$1" token
  token=$(printf '%s' "$tmpl" | grep -oE -- '--append-system-prompt [^ ]+' | sed -E 's/--append-system-prompt //')
  eval "printf '%s' $token"
}

@test "subinvoke-resolve: pi --role template's --append-system-prompt file contains the role's prompt body" {
  run bash "$RESOLVE" --agent pi --role mb-backend
  [ "$status" -eq 0 ]
  local tmpfile
  tmpfile=$(_extract_append_system_prompt_path "$output")
  [ -n "$tmpfile" ]
  [ -f "$tmpfile" ]
  grep -q "MB Backend" "$tmpfile"
  rm -f "$tmpfile"
}

@test "subinvoke-resolve: pi --role WITHOUT --role stays the pre-existing unscoped template (backward compat)" {
  run bash "$RESOLVE" --agent pi
  [ "$status" -eq 0 ]
  [[ "$output" != *"--tools"* ]]
  [[ "$output" != *"--append-system-prompt"* ]]
}

@test "subinvoke-resolve: pi --role for an unknown role fails loud, never emits a usable template" {
  run bash "$RESOLVE" --agent pi --role totally-unknown-role
  [ "$status" -ne 0 ]
  [[ "$output" == *"WARN"* || "$output" == *"warn"* ]]
  [[ "$output" != *"pi --mode"* ]]
}

@test "subinvoke-resolve: pi --role rejects a command-injection role name, never fires the substitution" {
  run bash "$RESOLVE" --agent pi --role 'x$(echo PWNED)'
  [ "$status" -ne 0 ]
  [[ "$output" != *"pi --mode"* ]]
  # Round-trip: even if a caller ignored the non-zero exit, the (empty)
  # resolved template cannot fire the substitution under bash -c.
  tmpl="$(bash "$RESOLVE" --agent pi --role 'x$(echo PWNED)' 2>/dev/null || true)"
  run env MB_FANOUT_PROMPT="x" bash -c "${tmpl:-true}"
  [[ "$output" != *"PWNED"* ]]
}

@test "subinvoke-resolve: pi --role template cleans up its system-prompt tmpfile after execution, WITHOUT masking the exit code" {
  local stub
  stub="$(mktemp -d)"
  # A failing stub `pi` — the round-trip must still report the FAILURE exit
  # code (not rm's success) while removing the tmpfile it was pointed at.
  printf '#!/bin/sh\nexit 7\n' > "$stub/pi"
  chmod +x "$stub/pi"
  local tmpl tmpfile
  tmpl="$(bash "$RESOLVE" --agent pi --role mb-backend)"
  tmpfile=$(_extract_append_system_prompt_path "$tmpl")
  [ -f "$tmpfile" ]
  run env PATH="$stub:$PATH" MB_FANOUT_PROMPT="hi" bash -c "$tmpl"
  [ "$status" -eq 7 ]
  [ ! -f "$tmpfile" ]
  rm -rf "$stub"
}

@test "subinvoke-resolve: pi --role template is consumable by bash -c with a stubbed pi (round-trip)" {
  local stub
  stub="$(mktemp -d)"
  printf '#!/bin/sh\nprintf "got:%%s args:%%s" "$MB_FANOUT_PROMPT" "$*"\n' > "$stub/pi"
  chmod +x "$stub/pi"
  local tmpl
  tmpl="$(bash "$RESOLVE" --agent pi --role mb-backend)"
  run env PATH="$stub:$PATH" MB_FANOUT_PROMPT="hi-role" bash -c "$tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hi-role"* ]]
  [[ "$output" == *"--tools"* ]]
}

# ═══════════════════════════════════════════════════════════════
# 3a. pi_subagent_extension.ts — registration surface (source-level, like
#     tests/bats/test_mb_python_resolution.bats' pi_graph_rag_extension.ts
#     coverage: no `typebox` package installed here, so the file that does
#     `import { Type } from "typebox"` can't be import()'d in a bare node
#     harness — assert the contract at the source level instead.)
# ═══════════════════════════════════════════════════════════════

@test "pi_subagent_extension.ts registers the mb_dispatch_subagent tool and a native /mb command" {
  local ext="$REPO_ROOT/adapters/pi_subagent_extension.ts"
  [ -f "$ext" ]
  grep -q 'name: "mb_dispatch_subagent"' "$ext"
  grep -q 'registerCommand("mb"' "$ext"
  grep -q 'pi.registerTool' "$ext"
}

@test "pi_subagent_extension.ts imports its dispatch-core sibling by the SAME basename installed alongside it" {
  local ext="$REPO_ROOT/adapters/pi_subagent_extension.ts"
  grep -q 'from "./pi_subagent_dispatch_core.mjs"' "$ext"
  [ -f "$REPO_ROOT/adapters/pi_subagent_dispatch_core.mjs" ]
}

# ═══════════════════════════════════════════════════════════════
# 3b. pi_subagent_dispatch_core.mjs — the real, executable dispatch logic
#     (no Pi SDK dependency, so this half genuinely runs under plain node —
#     this is where REQ-009 "never silent" is actually exercised).
# ═══════════════════════════════════════════════════════════════

@test "pi_subagent_dispatch_core: dispatching an unknown role never drops silently (dispatched:false + warning)" {
  command -v node >/dev/null || skip "node required"

  local core="$REPO_ROOT/adapters/pi_subagent_dispatch_core.mjs"
  [ -f "$core" ]

  local harness="$PROJECT/harness-dispatch-fail.mjs"
  cat > "$harness" <<EOF
import { dispatchRole } from "$core";
const result = await dispatchRole("totally-unknown-role", "do the thing", undefined, process.cwd());
console.log(JSON.stringify(result));
EOF
  run env PI_CODING_AGENT_DIR="$SANDBOX_HOME/.pi/agent" node "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dispatched\":false"* ]]
  [[ "$output" == *"inline execution"* ]] || [[ "$output" == *"falling back"* ]]
}

@test "pi_subagent_dispatch_core: a tmpfile setup failure (mkdtemp/writeFile) returns dispatched:false, never throws (Codex MAJOR #1)" {
  command -v node >/dev/null || skip "node required"

  local core="$REPO_ROOT/adapters/pi_subagent_dispatch_core.mjs"
  local agents_dir="$SANDBOX_HOME/.pi/agent/agents"
  mkdir -p "$agents_dir"
  cp "$REPO_ROOT/agents/mb-backend.md" "$agents_dir/mb-backend.md"

  local harness="$PROJECT/harness-tmpdir-fail.mjs"
  cat > "$harness" <<EOF
import { dispatchRole } from "$core";
try {
  const result = await dispatchRole("mb-backend", "do the thing", undefined, process.cwd());
  console.log(JSON.stringify({ threw: false, result }));
} catch (err) {
  console.log(JSON.stringify({ threw: true, message: err.message }));
}
EOF
  # TMPDIR pointed at a non-existent parent — os.tmpdir() honours it, so
  # mkdtemp(join(tmpdir(), ...)) fails with ENOENT before any subprocess
  # is ever spawned.
  run env PI_CODING_AGENT_DIR="$SANDBOX_HOME/.pi/agent" TMPDIR="/nonexistent-mb-pi-dispatch-test-dir-xyz/deeper" node "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"threw\":false"* ]]
  [[ "$output" == *"dispatched\":false"* ]]
  [[ "$output" == *"falling back to inline execution"* ]]
}

@test "pi_subagent_dispatch_core: a resolvable role is scoped with the role's --tools/--append-system-prompt (stubbed pi)" {
  command -v node >/dev/null || skip "node required"

  local core="$REPO_ROOT/adapters/pi_subagent_dispatch_core.mjs"
  local agents_dir="$SANDBOX_HOME/.pi/agent/agents"
  mkdir -p "$agents_dir"
  cp "$REPO_ROOT/agents/mb-backend.md" "$agents_dir/mb-backend.md"

  local stub
  stub="$(mktemp -d)"
  cat > "$stub/pi" <<'STUB'
#!/bin/sh
echo "ARGS:$*"
echo '{"type":"message_end","message":{"role":"assistant","content":"ok"}}'
STUB
  chmod +x "$stub/pi"

  local harness="$PROJECT/harness-dispatch-ok.mjs"
  cat > "$harness" <<EOF
import { dispatchRole } from "$core";
const result = await dispatchRole("mb-backend", "do the thing", "test-model", process.cwd());
console.log(JSON.stringify(result));
EOF
  run env PI_CODING_AGENT_DIR="$SANDBOX_HOME/.pi/agent" PATH="$stub:$PATH" node "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dispatched\":true"* ]]
  [[ "$output" == *"--tools"* ]]
  # Pi's real (lowercase, translated) tool names, never the raw CC frontmatter
  # names — see translateToolsToPi()'s doc comment for the SDK-verified mapping.
  [[ "$output" == *"bash"* ]]
  [[ "$output" != *"Bash"* ]]
  [[ "$output" == *"--append-system-prompt"* ]]
  rm -rf "$stub"
}

@test "pi_subagent_dispatch_core: translateToolsToPi maps CC names to Pi's exact SDK-verified names, drops the rest" {
  command -v node >/dev/null || skip "node required"
  local core="$REPO_ROOT/adapters/pi_subagent_dispatch_core.mjs"
  local harness="$PROJECT/harness-translate.mjs"
  cat > "$harness" <<EOF
import { translateToolsToPi } from "$core";
console.log(JSON.stringify(translateToolsToPi(["Bash", "Read", "Write", "Edit", "Grep", "Glob", "SendMessage", "Unknown"])));
EOF
  run node "$harness"
  [ "$status" -eq 0 ]
  [ "$output" = '["bash","read","write","edit","grep","find"]' ]
}
