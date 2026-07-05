#!/usr/bin/env bats
# Tests for scripts/mb-subinvoke-resolve.sh — B7 (CDX-2, Codex delta): the
# builtin sub-invoke table gains `pi` and `opencode` arms so a governed
# review/fan-out on those agents resolves a sub-invoke command instead of
# failing loud (REQ-DF-052 previously fired for BOTH — that stays correct for
# genuinely unknown agents, but pi/opencode are now first-class table entries).
#
# Contract under test (mirrors test_mb_subinvoke_resolve.bats for codex/cc):
#   - `--agent pi` (no MB_SUBINVOKE_CMD) → exit 0, template contains
#     `pi -p`, `--no-session`, `--model`, and the LITERAL `$MB_FANOUT_PROMPT`
#     token (never expanded).
#   - `--agent opencode` (no MB_SUBINVOKE_CMD) → exit 0, template contains
#     `opencode run`, `--model`, and the literal `$MB_FANOUT_PROMPT` token.
#   - MB_SUBINVOKE_MODEL is interpolated (subject to the existing grammar
#     guard — malformed models are still rejected, exit 1, no emission).
#   - MB_SUBINVOKE_CMD override still wins over the pi/opencode table entries.
#   - The script's own help text no longer promises "Task 13 adds pi/opencode"
#     as a future extension — pi/opencode are documented as resolved.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RESOLVE="$REPO_ROOT/scripts/mb-subinvoke-resolve.sh"
  unset MB_AGENT MB_SUBINVOKE_CMD MB_SUBINVOKE_MODEL 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════
# pi resolves (was RED: exit 2 + WARN before the fix)
# ═══════════════════════════════════════════════════════════════

@test "subinvoke-resolve: --agent pi resolves a 'pi -p' template via env prompt (exit 0)" {
  run bash "$RESOLVE" --agent pi
  [ "$status" -eq 0 ]
  [[ "$output" == *"pi -p"* ]]
  [[ "$output" == *"--no-session"* ]]
  [[ "$output" == *"--model"* ]]
  # Literal token, never expanded.
  [[ "$output" == *"\$MB_FANOUT_PROMPT"* ]]
}

@test "subinvoke-resolve: MB_AGENT=pi (env, no --agent flag) also resolves" {
  MB_AGENT=pi run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pi -p"* ]]
}

@test "subinvoke-resolve: pi template interpolates MB_SUBINVOKE_MODEL" {
  MB_AGENT=pi MB_SUBINVOKE_MODEL="openai-codex/gpt-5.5" run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"openai-codex/gpt-5.5"* ]]
}

@test "subinvoke-resolve: pi template rejects a command-injection MB_SUBINVOKE_MODEL (grammar guard still applies)" {
  MB_AGENT=pi MB_SUBINVOKE_MODEL='$(echo PWNED >&2)' run bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output" != *"pi -p"* ]]
}

# ═══════════════════════════════════════════════════════════════
# opencode resolves (was RED: exit 2 + WARN before the fix)
# ═══════════════════════════════════════════════════════════════

@test "subinvoke-resolve: --agent opencode resolves an 'opencode run' template via env prompt (exit 0)" {
  run bash "$RESOLVE" --agent opencode
  [ "$status" -eq 0 ]
  [[ "$output" == *"opencode run"* ]]
  [[ "$output" == *"--model"* ]]
  [[ "$output" == *"\$MB_FANOUT_PROMPT"* ]]
}

@test "subinvoke-resolve: opencode template interpolates MB_SUBINVOKE_MODEL" {
  MB_AGENT=opencode MB_SUBINVOKE_MODEL="opencode/gpt-5.2" run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"opencode/gpt-5.2"* ]]
}

@test "subinvoke-resolve: opencode template rejects a command-injection MB_SUBINVOKE_MODEL (grammar guard still applies)" {
  MB_AGENT=opencode MB_SUBINVOKE_MODEL='$(echo PWNED >&2)' run bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output" != *"opencode run"* ]]
}

# ═══════════════════════════════════════════════════════════════
# MB_SUBINVOKE_CMD override still wins (authoritative for every agent)
# ═══════════════════════════════════════════════════════════════

@test "subinvoke-resolve: MB_SUBINVOKE_CMD override wins over the pi table entry" {
  MB_AGENT=pi MB_SUBINVOKE_CMD='my-runner "$MB_FANOUT_PROMPT"' run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"my-runner"* ]]
  [[ "$output" != *"pi -p"* ]]
}

@test "subinvoke-resolve: MB_SUBINVOKE_CMD override wins over the opencode table entry" {
  MB_AGENT=opencode MB_SUBINVOKE_CMD='my-runner "$MB_FANOUT_PROMPT"' run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"my-runner"* ]]
  [[ "$output" != *"opencode run"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Round-trip — templates are consumable as bash -c commands (seam)
# ═══════════════════════════════════════════════════════════════

@test "subinvoke-resolve: pi template is consumable by bash -c with an env prompt (seam, stubbed pi)" {
  local stub
  stub="$(mktemp -d)"
  printf '#!/bin/sh\nprintf "got:%%s" "$MB_FANOUT_PROMPT"\n' > "$stub/pi"
  chmod +x "$stub/pi"
  local tmpl
  tmpl="$(bash "$RESOLVE" --agent pi)"
  run env PATH="$stub:$PATH" MB_FANOUT_PROMPT="hi-pi" bash -c "$tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hi-pi"* ]]
  rm -rf "$stub"
}

@test "subinvoke-resolve: opencode template is consumable by bash -c with an env prompt (seam, stubbed opencode)" {
  local stub
  stub="$(mktemp -d)"
  printf '#!/bin/sh\nprintf "got:%%s" "$MB_FANOUT_PROMPT"\n' > "$stub/opencode"
  chmod +x "$stub/opencode"
  local tmpl
  tmpl="$(bash "$RESOLVE" --agent opencode)"
  run env PATH="$stub:$PATH" MB_FANOUT_PROMPT="hi-oc" bash -c "$tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hi-oc"* ]]
  rm -rf "$stub"
}

# ═══════════════════════════════════════════════════════════════
# Help text sync — no stale "Task 13 adds pi/opencode" promise
# ═══════════════════════════════════════════════════════════════

@test "subinvoke-resolve: help text no longer promises pi/opencode as a future Task 13 addition" {
  run bash "$RESOLVE" --help
  [ "$status" -eq 0 ]
  [[ "$output" != *"Task 13 adds"* ]]
  # pi/opencode are documented as part of the real table now.
  [[ "$output" == *"pi"* ]]
  [[ "$output" == *"opencode"* ]]
}

@test "subinvoke-resolve: a genuinely unknown agent still fails loud (REQ-DF-052 preserved)" {
  run bash "$RESOLVE" --agent totally-unknown-agent
  [ "$status" -ne 0 ]
  [[ "$output" == *"WARN"* ]]
  [[ "$output" == *"totally-unknown-agent"* ]]
}
