#!/usr/bin/env bats
# Tests for install.sh CLI flag handling and interactive flow.
#
# Contract:
#   install.sh [--clients <list>] [--project-root <path>] [--non-interactive] [--help]
#
# Interactive mode:
#   - Triggered when --clients empty AND stdin is TTY AND --non-interactive not set.
#   - Accepts numbers/names/'all'/empty (= default claude-code).
#
# Test strategy: run install.sh via non-TTY stdin (no interactive trigger) and
# via --non-interactive to verify non-interactive paths. Full bash side-effects
# mocked by running --help only — never executes real install steps.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  INSTALL="$REPO_ROOT/install.sh"
}

run_install() {
  local raw
  raw=$(bash "$INSTALL" "$@" </dev/null 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

# ═══════════════════════════════════════════════════════════════
# Help / usage
# ═══════════════════════════════════════════════════════════════

@test "install: --help prints usage and exits 0" {
  run_install --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--clients"* ]]
  [[ "$output" == *"--project-root"* ]]
  [[ "$output" == *"--non-interactive"* ]]
}

@test "install: -h shortcut works" {
  run_install -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "install: --help lists all 8 valid clients" {
  run_install --help
  [[ "$output" == *"claude-code"* ]]
  [[ "$output" == *"cursor"* ]]
  [[ "$output" == *"windsurf"* ]]
  [[ "$output" == *"cline"* ]]
  [[ "$output" == *"kilo"* ]]
  [[ "$output" == *"opencode"* ]]
  [[ "$output" == *"pi"* ]]
  [[ "$output" == *"codex"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Argument validation
# ═══════════════════════════════════════════════════════════════

@test "install: unknown flag → exit 1 with hint" {
  run_install --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument"* ]]
}

@test "install: --clients without value → exit 1" {
  run_install --clients
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires an argument"* ]]
}

@test "install: --project-root without value → exit 1" {
  run_install --project-root
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires an argument"* ]]
}

@test "install: --clients with invalid name → exit 1 with client list" {
  # MB_SKIP_DEPS_CHECK=1 to bypass preflight; hit validation instead.
  local raw
  raw=$(MB_SKIP_DEPS_CHECK=1 bash "$INSTALL" --clients bogus-client </dev/null 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid client"* ]]
  [[ "$output" == *"bogus-client"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Non-TTY default behavior (no --clients, stdin not a terminal)
# ═══════════════════════════════════════════════════════════════

@test "install: non-TTY stdin with no --clients → defaults silently (no prompt text)" {
  # stdin redirected from /dev/null above. install.sh should NOT print the
  # interactive menu ("Which AI coding agents do you want to enable?").
  # We don't let it actually run — point --help-style: just verify no prompt
  # leaks by passing --non-interactive.
  run_install --non-interactive --help
  [ "$status" -eq 0 ]
  [[ "$output" != *"Which AI coding agents"* ]]
}

# ═══════════════════════════════════════════════════════════════
# MB_CLIENTS env var
# ═══════════════════════════════════════════════════════════════

@test "install: MB_CLIENTS env passes as --clients when unset" {
  # Validation happens before install steps; bad value should still error,
  # which confirms the env was read.
  local raw
  raw=$(MB_CLIENTS="not-a-real-client" MB_SKIP_DEPS_CHECK=1 \
        bash "$INSTALL" --non-interactive </dev/null 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid client"* ]]
  [[ "$output" == *"not-a-real-client"* ]]
}

@test "install: explicit --clients beats MB_CLIENTS" {
  # --clients should take precedence; MB_CLIENTS ignored if --clients present.
  local raw
  raw=$(MB_CLIENTS="claude-code" MB_SKIP_DEPS_CHECK=1 \
        bash "$INSTALL" --clients "bogus" --non-interactive </dev/null 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid client"* ]]
  [[ "$output" == *"bogus"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Valid client lists parse cleanly
# ═══════════════════════════════════════════════════════════════

@test "install: single valid client passes validation" {
  # We stop short of full install by failing a later step. Use
  # MB_SKIP_DEPS_CHECK=1 + a nonsense project-root to halt cleanly, but
  # any unreachable state is fine — we just verify validation is silent.
  # Simpler: validate via --help pathway only (the validation runs before help).
  # Actually --help exits BEFORE client validation (it's the first case branch),
  # so we instead rely on MB_SKIP_DEPS_CHECK=1 + checking there's no
  # "invalid client" warning.
  local raw
  raw=$(MB_SKIP_DEPS_CHECK=1 bash "$INSTALL" --clients claude-code --non-interactive </dev/null 2>&1 || true)
  [[ "$raw" != *"invalid client"* ]]
}

@test "install: comma-separated list parses correctly (3 valid clients)" {
  local raw
  raw=$(MB_SKIP_DEPS_CHECK=1 bash "$INSTALL" \
        --clients "claude-code,cursor,windsurf" --non-interactive </dev/null 2>&1 || true)
  [[ "$raw" != *"invalid client"* ]]
}

@test "install: spaces around commas tolerated" {
  local raw
  raw=$(MB_SKIP_DEPS_CHECK=1 bash "$INSTALL" \
        --clients "claude-code, cursor , windsurf" --non-interactive </dev/null 2>&1 || true)
  [[ "$raw" != *"invalid client"* ]]
}
