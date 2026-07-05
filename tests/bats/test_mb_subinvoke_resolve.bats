#!/usr/bin/env bats
# Tests for scripts/mb-subinvoke-resolve.sh — the per-agent sub-invoke command
# resolver (dynamic-flow Task 12, REQ-DF-082 / REQ-DF-051 / REQ-DF-052).
#
# Contract under test:
#   - Resolves the per-agent shell sub-invoke command TEMPLATE for the active
#     agent. Active agent = $MB_AGENT (or `--agent <name>`); default fallback is
#     claude-code (the codebase-wide default, e.g. ${MB_AGENT:-claude-code}).
#   - Built-in table for `codex`, `claude-code`, `pi`, and `opencode` (Task 12 +
#     B7/CDX-2). A genuinely unknown agent name still fails loud (below) — see
#     tests/bats/test_subinvoke_resolve.bats for the dedicated pi/opencode suite.
#   - An explicit operator override (MB_SUBINVOKE_CMD) WINS over the table, so a
#     baked env / `mb-fanout --cmd` stays authoritative.
#   - The resolved template carries the prompt ONLY via $MB_FANOUT_PROMPT — never
#     an interpolated literal prompt (consistent with mb-fanout's security seam).
#   - Unknown/missing agent with no override → non-zero + a stderr WARN naming the
#     missing sub-invoke (REQ-DF-052 fail-loud, never silently serial).
#   - On success: prints the template to stdout, exit 0.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RESOLVE="$REPO_ROOT/scripts/mb-subinvoke-resolve.sh"
  # Neutralise any inherited agent/override so each test controls its own env.
  unset MB_AGENT MB_SUBINVOKE_CMD MB_SUBINVOKE_MODEL 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════
# Existence / help
# ═══════════════════════════════════════════════════════════════

@test "subinvoke-resolve: script exists and is executable" {
  [ -f "$RESOLVE" ]
  [ -x "$RESOLVE" ]
}

@test "subinvoke-resolve: --help exits 0 and documents the contract" {
  run bash "$RESOLVE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"MB_FANOUT_PROMPT"* ]]
  [[ "$output" == *"--agent"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Resolution table — codex vs claude-code by $MB_AGENT
# ═══════════════════════════════════════════════════════════════

@test "subinvoke-resolve: MB_AGENT=codex → a 'codex exec' template via env prompt" {
  MB_AGENT=codex run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex exec"* ]]
  [[ "$output" == *"\$MB_FANOUT_PROMPT"* ]]
  # read-only sandbox per the contract.
  [[ "$output" == *"read-only"* ]]
}

@test "subinvoke-resolve: MB_AGENT=claude-code → a 'claude -p' template via env prompt" {
  MB_AGENT=claude-code run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude -p"* ]]
  [[ "$output" == *"\$MB_FANOUT_PROMPT"* ]]
}

@test "subinvoke-resolve: --agent codex overrides the env and resolves the codex template" {
  MB_AGENT=claude-code run bash "$RESOLVE" --agent codex
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex exec"* ]]
}

@test "subinvoke-resolve: no MB_AGENT, no flag → defaults to claude-code template" {
  run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude -p"* ]]
}

@test "subinvoke-resolve: MB_SUBINVOKE_MODEL is honoured in the codex template" {
  MB_AGENT=codex MB_SUBINVOKE_MODEL="gpt-test-9" run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gpt-test-9"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Operator override wins over the table
# ═══════════════════════════════════════════════════════════════

@test "subinvoke-resolve: MB_SUBINVOKE_CMD override WINS over the codex table entry" {
  MB_AGENT=codex MB_SUBINVOKE_CMD='my-runner "$MB_FANOUT_PROMPT"' run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"my-runner"* ]]
  [[ "$output" != *"codex exec"* ]]
}

@test "subinvoke-resolve: MB_SUBINVOKE_CMD override wins even for an UNKNOWN agent" {
  MB_AGENT=totally-unknown MB_SUBINVOKE_CMD='custom "$MB_FANOUT_PROMPT"' run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"custom"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Security seam — the template NEVER embeds a literal prompt
# ═══════════════════════════════════════════════════════════════

@test "subinvoke-resolve: resolved template references \$MB_FANOUT_PROMPT, never an interpolated prompt" {
  # Even if MB_FANOUT_PROMPT happens to be set in the resolver's env, the printed
  # template must contain the literal token, not its expansion.
  MB_AGENT=codex MB_FANOUT_PROMPT='SECRET_PROMPT_VALUE' run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\$MB_FANOUT_PROMPT"* ]]
  [[ "$output" != *"SECRET_PROMPT_VALUE"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Anti-recursion — a claude-code sub-invoke must NOT re-enter CC hooks
# (parity with mb-recap.sh / mb-conflicts.sh: env -u CLAUDECODE + capture flag)
# ═══════════════════════════════════════════════════════════════

@test "subinvoke-resolve: claude-code template carries the anti-recursion env (env -u CLAUDECODE + MB_CAPTURE_SUBPROCESS=1)" {
  MB_AGENT=claude-code run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  # Without these, a claude-code fan-out branch re-enters Claude Code hooks /
  # session capture (exactly what mb-recap.sh / mb-conflicts.sh guard against).
  [[ "$output" == *"env -u CLAUDECODE"* ]]
  [[ "$output" == *"MB_CAPTURE_SUBPROCESS=1"* ]]
  [[ "$output" == *"claude -p"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Model grammar — MB_SUBINVOKE_MODEL is interpolated into a bash -c
# template, so a non-model value MUST NOT become live shell (injection).
# ═══════════════════════════════════════════════════════════════

@test "subinvoke-resolve: a benign model id with . _ / - is accepted" {
  MB_AGENT=codex MB_SUBINVOKE_MODEL="anthropic/claude-4.8_turbo-x" run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"anthropic/claude-4.8_turbo-x"* ]]
}

@test "subinvoke-resolve: a command-injection MB_SUBINVOKE_MODEL is REJECTED, never emitted as live shell" {
  # A model containing command substitution must be refused at resolve time, so
  # mb-fanout's later `bash -c "$CMD"` can never fire the substitution.
  MB_AGENT=codex MB_SUBINVOKE_MODEL='$(echo PWNED >&2)' run bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output" != *"codex exec"* ]]
  # Prove the round-trip is safe even if a caller ignored the non-zero exit: the
  # template (empty here) cannot fire the substitution under bash -c.
  tmpl="$(MB_AGENT=codex MB_SUBINVOKE_MODEL='$(echo PWNED >&2)' bash "$RESOLVE" 2>/dev/null || true)"
  run env MB_FANOUT_PROMPT="x" bash -c "${tmpl:-true}"
  [[ "$output" != *"PWNED"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Fail-loud — unknown/missing agent, no override (REQ-DF-052)
# ═══════════════════════════════════════════════════════════════

@test "subinvoke-resolve: unknown agent, no override → non-zero + stderr WARN naming the missing sub-invoke" {
  run bash "$RESOLVE" --agent totally-unsupported-agent
  [ "$status" -ne 0 ]
  [[ "$output" == *"WARN"* ]]
  [[ "$output" == *"totally-unsupported-agent"* ]]
  # Never silently emit a usable template for an unsupported agent.
  [[ "$output" != *"codex exec"* ]]
  [[ "$output" != *"claude -p"* ]]
}

# B7/CDX-2 regression guard: pi/opencode used to hit the fail-loud arm above
# (Task 13 gap) — they are now resolvable builtin-table entries. Dedicated
# coverage lives in tests/bats/test_subinvoke_resolve.bats.
@test "subinvoke-resolve: opencode IS resolvable now (builtin table, B7/CDX-2 closed the old Task-13 gap)" {
  run bash "$RESOLVE" --agent opencode
  [ "$status" -eq 0 ]
  [[ "$output" == *"opencode run"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Round-trip — the template actually works inside mb-fanout's bash -c
# ═══════════════════════════════════════════════════════════════

@test "subinvoke-resolve: an override template is consumable as a bash -c command with env prompt" {
  # Mirror mb-fanout's seam: export MB_FANOUT_PROMPT, run the template via bash -c.
  tmpl="$(MB_AGENT=codex MB_SUBINVOKE_CMD='printf "got:%s" "$MB_FANOUT_PROMPT"' bash "$RESOLVE")"
  run env MB_FANOUT_PROMPT="hello-world" bash -c "$tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == "got:hello-world" ]]
}
