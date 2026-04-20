#!/usr/bin/env bats
# End-to-end: build wheel → install in isolated venv → exercise `memory-bank` CLI.
#
# Verifies the Stage 9 distribution story: `pip install memory-bank-skill` produces
# a working `memory-bank` command that can resolve its shared bundle (install.sh,
# adapters/, hooks/, rules/) via the venv's share/ directory.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  WHEEL_DIR="/tmp/mb-e2e-dist-$$"
  VENV_DIR="$(mktemp -d)/venv"
  command -v python3 >/dev/null || skip "python3 required"
  python3 -c "import build" 2>/dev/null || skip "python build module missing"
  mkdir -p "$WHEEL_DIR"
}

teardown() {
  [ -n "${WHEEL_DIR:-}" ] && rm -rf "$WHEEL_DIR"
  [ -n "${VENV_DIR:-}" ] && [ -d "$VENV_DIR" ] && rm -rf "$(dirname "$VENV_DIR")"
}

build_and_install() {
  (cd "$REPO_ROOT" && python3 -m build --wheel --outdir "$WHEEL_DIR" >/dev/null 2>&1)
  python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install --quiet "$WHEEL_DIR"/*.whl
}

# ═══════════════════════════════════════════════════════════════

@test "pipx-like install: wheel builds and memory-bank command exists" {
  build_and_install
  [ -x "$VENV_DIR/bin/memory-bank" ]
}

@test "pipx-like install: memory-bank version prints package version" {
  build_and_install
  local out
  out=$("$VENV_DIR/bin/memory-bank" version)
  [[ "$out" == *"memory-bank-skill"* ]]
  [[ "$out" == *"3.0.0"* ]]
}

@test "pipx-like install: memory-bank doctor resolves bundle from venv share/" {
  build_and_install
  local out
  out=$("$VENV_DIR/bin/memory-bank" doctor)
  [[ "$out" == *"Bundle root:"* ]]
  [[ "$out" == *"install.sh: True"* ]]
  [[ "$out" == *"adapters/: True"* ]]
}

@test "pipx-like install: --help works" {
  build_and_install
  local out
  out=$("$VENV_DIR/bin/memory-bank" --help)
  [[ "$out" == *"install"* ]]
  [[ "$out" == *"uninstall"* ]]
  [[ "$out" == *"version"* ]]
  [[ "$out" == *"doctor"* ]]
}

@test "pipx-like install: self-update suggests pipx upgrade" {
  build_and_install
  local out
  out=$("$VENV_DIR/bin/memory-bank" self-update)
  [[ "$out" == *"pipx upgrade"* ]]
  [[ "$out" == *"memory-bank-skill"* ]]
}

@test "pipx-like install: install --clients validation rejects bad name" {
  build_and_install
  # Exit non-zero on invalid client (validation happens in install.sh, which CLI wraps)
  run "$VENV_DIR/bin/memory-bank" install --clients invalidname --project-root /tmp
  [ "$status" -ne 0 ]
}

@test "pipx-like install: init prints /mb hint" {
  build_and_install
  local out
  out=$("$VENV_DIR/bin/memory-bank" init)
  [[ "$out" == *"/mb init"* ]]
}
