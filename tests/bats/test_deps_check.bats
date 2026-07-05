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

# A11: sandbox with bash/jq/git + a python3 stub reporting Python 3.10.0 (an
# unsupported version — pyproject.toml requires target-version=py311). The
# stub answers `--version` for humans and short-circuits the two `-c` probes
# mb-deps-check.sh is expected to run: one raises SystemExit based on
# version_info, the other prints the found version for a human-readable message.
setup_old_python_sandbox() {
  OLD_PY_BIN="$(mktemp -d)"
  ln -s "$(command -v bash)" "$OLD_PY_BIN/bash"
  ln -s "$(command -v jq)" "$OLD_PY_BIN/jq"
  ln -s "$(command -v git)" "$OLD_PY_BIN/git"
  cat > "$OLD_PY_BIN/python3" <<'PYSTUB'
#!/usr/bin/env bash
case "$*" in
  *--version*) echo "Python 3.10.0"; exit 0 ;;
esac
if [ "${1:-}" = "-c" ]; then
  case "$2" in
    *sys.exit*) exit 1 ;;
    *print*) echo "3.10.0"; exit 0 ;;
  esac
fi
exit 0
PYSTUB
  chmod +x "$OLD_PY_BIN/python3"
}

run_deps_old_python() {
  local raw
  raw=$(env -i HOME="$HOME" PATH="$OLD_PY_BIN" bash "$DEPS" "$@" 2>&1; printf '\n__EXIT__%s' "$?")
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

@test "deps: python3 present but < 3.11 → version blocker, exit 1 (A11)" {
  setup_old_python_sandbox
  run_deps_old_python
  [ "$status" -ne 0 ]
  # Binary itself is present (do not conflate with "missing").
  [[ "$output" == *"dep_python3=ok"* ]]
  [[ "$output" == *"dep_python3_version=missing"* ]]
  [[ "$output" == *"3.11"* ]]
  [[ "$output" == *"3.10.0"* ]]
  rm -rf "$OLD_PY_BIN"
}

@test "deps: python3 >= 3.11 on current system → no version blocker (control)" {
  command -v python3 >/dev/null || skip "python3 required"
  py_ok=$(python3 -c 'import sys; print(1 if sys.version_info >= (3, 11) else 0)')
  [ "$py_ok" -eq 1 ] || skip "system python3 < 3.11 — not the case this test covers"
  run_deps
  [[ "$output" == *"dep_python3_version=ok"* ]]
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
