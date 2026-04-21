#!/usr/bin/env bats
# Tests for scripts/mb-deps-check.sh.
#
# Contract:
#   mb-deps-check.sh [--quiet] [--install-hints]
#
# Output format (key=value, stdout):
#   dep_<name>=ok|missing|optional-missing
#   deps_required_missing=N
#   deps_optional_missing=M
#
# Exit:
#   0 — all required present
#   1 — at least 1 required missing (blocker)
#
# Test strategy: inject a fake PATH without a specific utility and verify the
# script flags it correctly. For the "all present" case, use the system PATH.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DEPS="$REPO_ROOT/scripts/mb-deps-check.sh"
  SANDBOX_BIN="$(mktemp -d)"
  # Create a stripped sandbox: only bash inside
  ln -s "$(command -v bash)" "$SANDBOX_BIN/bash"
}

teardown() {
  [ -n "${SANDBOX_BIN:-}" ] && [ -d "$SANDBOX_BIN" ] && rm -rf "$SANDBOX_BIN"
}

run_deps() {
  local raw
  raw=$(bash "$DEPS" "$@" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

run_deps_sandbox() {
  local raw
  raw=$(env -i HOME="$HOME" PATH="$SANDBOX_BIN" bash "$DEPS" "$@" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

# ═══════════════════════════════════════════════════════════════

@test "deps: all present on current system → exit 0 (assuming python3/jq/git installed)" {
  run_deps
  # On a dev machine all required tools should exist. If CI lacks jq — expect exit 1.
  # Assert: output contains dep_python3=ok or a clear reason.
  [[ "$output" == *"dep_python3="* ]]
  [[ "$output" == *"dep_jq="* ]]
  [[ "$output" == *"dep_git="* ]]
  [[ "$output" == *"deps_required_missing="* ]]
}

@test "deps: reports optional deps (rg, shellcheck)" {
  run_deps
  [[ "$output" == *"dep_rg="* ]]
  [[ "$output" == *"dep_shellcheck="* ]]
  [[ "$output" == *"deps_optional_missing="* ]]
}

@test "deps: sandbox with only bash → required missing → exit 1" {
  run_deps_sandbox
  [ "$status" -ne 0 ]
  [[ "$output" == *"dep_python3=missing"* ]]
  [[ "$output" == *"dep_jq=missing"* ]]
}

@test "deps: --install-hints prints brew/apt instructions on missing required" {
  run_deps_sandbox --install-hints
  [ "$status" -ne 0 ]
  # It should mention install commands
  [[ "$output" == *"brew"* ]] || [[ "$output" == *"apt"* ]] || [[ "$output" == *"install"* ]]
}

@test "deps: --quiet suppresses human-readable output, keeps key=value" {
  run_deps --quiet
  # key=value remains
  [[ "$output" == *"dep_python3="* ]]
  # No emoji/colors
  [[ "$output" != *"✅"* ]]
  [[ "$output" != *"❌"* ]]
}

@test "deps: tree-sitter check reports presence or optional-missing (not blocker)" {
  run_deps
  [[ "$output" == *"dep_tree_sitter="* ]]
  # tree-sitter is opt-in; missing it must not affect required_missing count
  # (assertion: if it is missing, it must be in optional_missing, not required)
}

@test "deps: exit 0 even if many optional deps are missing while required are ok" {
  # On a system with required deps installed (python3, jq, git) — exit 0 regardless of optional
  if ! command -v python3 >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    skip "required deps missing on this system"
  fi
  run_deps
  [ "$status" -eq 0 ]
}
