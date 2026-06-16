#!/usr/bin/env bats
# Tests for adapters/codex.sh — OpenAI Codex CLI adapter.
#
# Contract:
#   adapters/codex.sh install [PROJECT_ROOT]
#   adapters/codex.sh uninstall [PROJECT_ROOT]
#
# Generates:
#   <project>/AGENTS.md            — shared format (refcount via lib)
#   <project>/.codex/config.toml   — project-level settings
#   <project>/.codex/hooks.json    — experimental hooks (off by default)
#   <project>/.codex/.mb-manifest.json
#
# Codex hooks API: experimental, userpromptsubmit currently stable, lifecycle under dev.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ADAPTER="$REPO_ROOT/adapters/codex.sh"
  OC_ADAPTER="$REPO_ROOT/adapters/opencode.sh"
  PROJECT="$(mktemp -d)"
  mkdir -p "$PROJECT/.memory-bank"
  echo '# Progress' > "$PROJECT/.memory-bank/progress.md"
  command -v jq >/dev/null || skip "jq required"
  # The adapter DECLARATION must be a stable Codex contract, independent of any
  # inherited operator override — neutralise it so the clean tests are truly clean.
  unset MB_SUBINVOKE_CMD MB_SUBINVOKE_MODEL 2>/dev/null || true
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

run_adapter() {
  local raw
  raw=$(bash "$ADAPTER" "$@" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

# ═══════════════════════════════════════════════════════════════

@test "codex: install creates AGENTS.md with memory-bank section" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q "memory-bank:start" "$PROJECT/AGENTS.md"
}

@test "codex: install creates .codex/config.toml with project settings" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.codex/config.toml" ]
  grep -q "project_doc_max_bytes" "$PROJECT/.codex/config.toml"
}

@test "codex: install creates .codex/hooks.json with userpromptsubmit event" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.codex/hooks.json" ]
  jq . "$PROJECT/.codex/hooks.json" >/dev/null
  jq -e '.hooks.userpromptsubmit // .hooks."user-prompt-submit"' "$PROJECT/.codex/hooks.json" >/dev/null
}

@test "codex: install writes manifest with adapter=codex" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local m="$PROJECT/.codex/.mb-manifest.json"
  [ -f "$m" ]
  jq -e '.schema_version == 1' "$m" >/dev/null
  jq -e '.adapter == "codex"' "$m" >/dev/null
}

@test "codex: install idempotent — 2x run no section duplicates" {
  run_adapter install "$PROJECT"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local count
  count=$(grep -c "memory-bank:start" "$PROJECT/AGENTS.md")
  [ "$count" -eq 1 ]
}

@test "codex: uninstall removes our files and section" {
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.codex/config.toml" ]
  [ ! -f "$PROJECT/.codex/hooks.json" ]
  [ ! -f "$PROJECT/.codex/.mb-manifest.json" ]
  [ ! -f "$PROJECT/AGENTS.md" ]
}

@test "codex: uninstall no-op if never installed" {
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Coexistence with OpenCode (shared AGENTS.md refcount)
# ═══════════════════════════════════════════════════════════════

@test "codex+opencode: both install → single AGENTS.md section, refcount=2" {
  bash "$OC_ADAPTER" install "$PROJECT" >/dev/null
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  # Exactly one section
  local count
  count=$(grep -c "memory-bank:start" "$PROJECT/AGENTS.md")
  [ "$count" -eq 1 ]
  # Owners file has both
  jq -e '.owners | contains(["opencode","codex"])' "$PROJECT/.mb-agents-owners.json" >/dev/null
}

@test "codex+opencode: uninstall codex preserves section because opencode still owns" {
  bash "$OC_ADAPTER" install "$PROJECT" >/dev/null
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  # Section still present (opencode active)
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q "memory-bank:start" "$PROJECT/AGENTS.md"
  # Owners reduced to opencode only
  jq -e '.owners == ["opencode"]' "$PROJECT/.mb-agents-owners.json" >/dev/null
}

@test "codex+opencode: uninstall BOTH removes AGENTS.md entirely (no owners left)" {
  bash "$OC_ADAPTER" install "$PROJECT" >/dev/null
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  bash "$OC_ADAPTER" uninstall "$PROJECT" >/dev/null
  [ ! -f "$PROJECT/AGENTS.md" ]
  [ ! -f "$PROJECT/.mb-agents-owners.json" ]
}

@test "codex+opencode: existing user AGENTS.md preserved after both uninstall" {
  echo "# User preamble" > "$PROJECT/AGENTS.md"
  bash "$OC_ADAPTER" install "$PROJECT" >/dev/null
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  bash "$OC_ADAPTER" uninstall "$PROJECT" >/dev/null
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q "User preamble" "$PROJECT/AGENTS.md"
  ! grep -q "memory-bank:start" "$PROJECT/AGENTS.md"
}

# ═══════════════════════════════════════════════════════════════
# Global storage support (Stage 3 — AGENTS.md mentions resolver)
# ═══════════════════════════════════════════════════════════════

@test "codex: AGENTS.md section mentions global storage or resolver for bank path" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local agents="$PROJECT/AGENTS.md"
  [ -f "$agents" ]
  # The shared AGENTS.md section must mention that Memory Bank path can be
  # local OR global (resolved by skill), so users are not surprised in global mode
  grep -qi "MB_PATH\|global storage\|resolver\|resolved\|local OR global\|local or global" "$agents"
}

# ═══════════════════════════════════════════════════════════════
# Per-agent sub-invoke declaration (dynamic-flow Task 12, DoD#1 — REQ-DF-082)
# The adapter DECLARES the shell sub-invoke command mb-fanout uses on Codex.
# ═══════════════════════════════════════════════════════════════

@test "codex: 'subinvoke' action declares the codex sub-invoke command (codex exec, env prompt)" {
  run_adapter subinvoke
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex exec"* ]]
  # The prompt flows ONLY via $MB_FANOUT_PROMPT — never an interpolated literal.
  [[ "$output" == *"\$MB_FANOUT_PROMPT"* ]]
  [[ "$output" == *"read-only"* ]]
}

@test "codex: the adapter's declared sub-invoke MATCHES the resolver's codex table entry" {
  # DoD#1 + DoD#2 coherence: the adapter declaration and the resolver table are
  # the SAME command, so what the adapter declares is exactly what mb-fanout bakes.
  local from_adapter from_resolver
  from_adapter="$(bash "$ADAPTER" subinvoke)"
  from_resolver="$(MB_AGENT=codex bash "$REPO_ROOT/scripts/mb-subinvoke-resolve.sh")"
  [ "$from_adapter" = "$from_resolver" ]
}

@test "codex: the adapter DECLARATION ignores a polluted MB_SUBINVOKE_CMD (stable Codex contract, not an override)" {
  # DoD#1 is an adapter DECLARATION: `codex subinvoke` must always declare the
  # Codex table command, even if an operator override is exported in the env (the
  # override belongs to mb-fanout's RESOLVE path, not the adapter's declaration).
  # Without this, the declaration is non-tautologically distinct from the resolver
  # under a polluted env — which is exactly the contract we assert.
  local declared
  declared="$(MB_SUBINVOKE_CMD='evil-runner "$MB_FANOUT_PROMPT"' bash "$ADAPTER" subinvoke)"
  [[ "$declared" == *"codex exec"* ]]
  [[ "$declared" != *"evil-runner"* ]]
  # And the resolver (RESOLVE path) DOES honour the override — proving the two
  # paths intentionally differ, so the MATCHES test above is not tautological.
  local resolved
  resolved="$(MB_AGENT=codex MB_SUBINVOKE_CMD='evil-runner "$MB_FANOUT_PROMPT"' bash "$REPO_ROOT/scripts/mb-subinvoke-resolve.sh")"
  [[ "$resolved" == *"evil-runner"* ]]
}

@test "codex: declared sub-invoke is consumable by bash -c with an env prompt (seam)" {
  # Prove the declared template runs under mb-fanout's `bash -c "$CMD"` seam with
  # the prompt supplied via env — never interpolated. We stub `codex` on PATH so
  # the round-trip needs no real Codex CLI.
  local stub="$PROJECT/stubbin"
  mkdir -p "$stub"
  printf '#!/bin/sh\nprintf "{\\"got\\":\\"%%s\\"}" "$MB_FANOUT_PROMPT"\n' > "$stub/codex"
  chmod +x "$stub/codex"
  local tmpl
  tmpl="$(bash "$ADAPTER" subinvoke)"
  run env PATH="$stub:$PATH" MB_FANOUT_PROMPT="hi-there" bash -c "$tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hi-there"* ]]
}
