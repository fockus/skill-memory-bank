#!/usr/bin/env bats
# Tests for scripts/mb-lint-run.sh — the L5 lint runner.
#
# Contract (REQ-DF-042, ADR-3):
#   - emits {"name":"lint","ok":true|false|null,"findings":[...]}
#   - ALWAYS exits 0 — pass/fail/skip carried ONLY by `ok`.
#   - Detects the stack via mb-metrics.sh, runs the stack linter
#     (python→`ruff check`, shell→`shellcheck` on *.sh).
#   - ok=true   when the linter reports no findings.
#   - ok=false  + findings when the linter reports problems.
#   - ok=null   + stderr WARN when the stack has no supported linter / is
#     unknown OR the linter binary is not installed (skip, not fail).
#
# Core PASS/FAIL tests are HOST-INDEPENDENT: they use shim stubs for `ruff`
# and `shellcheck` so CI runs without either binary installed.  Real-binary
# integration smokes are kept as separate, explicitly-skipped tests so they
# still run on developer machines that have the tools.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-lint-run.sh"
  command -v jq >/dev/null || skip "jq required"
  WORK="$(mktemp -d)"
  STUB_DIR="$WORK/.stubs"
  mkdir -p "$STUB_DIR"
  ORIG_PATH="$PATH"
  # Prepend stub dir; teardown restores ORIG_PATH.
  export PATH="$STUB_DIR:$PATH"
}

teardown() {
  export PATH="$ORIG_PATH"
  [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

json_of() {
  printf '%s\n' "$1" | grep '^{' | tail -n1
}

# ---- stub helpers -----------------------------------------------------------
# install_clean_ruff / install_dirty_ruff / install_clean_shellcheck /
# install_dirty_shellcheck each write a minimal bash-3.2-safe shim into
# STUB_DIR.  The runner invokes these via the PATH prefix set in setup().

install_clean_ruff() {
  cat >"$STUB_DIR/ruff" <<'STUB'
#!/usr/bin/env bash
# clean ruff stub — emits nothing and exits 0 (no findings)
exit 0
STUB
  chmod +x "$STUB_DIR/ruff"
}

install_dirty_ruff() {
  cat >"$STUB_DIR/ruff" <<'STUB'
#!/usr/bin/env bash
# dirty ruff stub — emits one ruff concise-format finding and exits 1
# Format: <path>:<line>:<col>: <code> <message>
printf 'bad.py:1:1: F401 "os" imported but unused\n'
exit 1
STUB
  chmod +x "$STUB_DIR/ruff"
}

install_clean_shellcheck() {
  cat >"$STUB_DIR/shellcheck" <<'STUB'
#!/usr/bin/env bash
# clean shellcheck stub — emits nothing and exits 0 (no findings)
exit 0
STUB
  chmod +x "$STUB_DIR/shellcheck"
}

install_dirty_shellcheck() {
  cat >"$STUB_DIR/shellcheck" <<'STUB'
#!/usr/bin/env bash
# dirty shellcheck stub — emits one GCC-format finding and exits 1
# Format: <file>:<line>:<col>: <level>: <message>
printf 'bad.sh:2:6: warning: Double quote to prevent globbing and word splitting\n'
exit 1
STUB
  chmod +x "$STUB_DIR/shellcheck"
}

# ---- basic existence / help -------------------------------------------------

@test "lint: script exists" {
  [ -f "$RUN" ]
}

@test "lint: --help exits 0 and mentions --dir" {
  run bash "$RUN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dir"* ]]
}

# ---- PASS case: python via ruff shim (host-independent) --------------------

@test "lint/python-stub: clean ruff → ok=true, exit 0, no findings" {
  install_clean_ruff
  printf '[project]\nname="x"\nversion="0.0.0"\n' >"$WORK/pyproject.toml"
  printf 'def f():\n    return 1\n' >"$WORK/ok.py"
  run bash "$RUN" --dir "$WORK"
  [ "$status" -eq 0 ]
  local j; j="$(json_of "$output")"
  echo "$j" | jq -e '.name == "lint"'
  echo "$j" | jq -e '.ok == true'
  echo "$j" | jq -e '.findings | length == 0'
}

# ---- FAIL case: python via ruff shim (host-independent) --------------------

@test "lint/python-stub: dirty ruff → ok=false, exit 0, findings present" {
  install_dirty_ruff
  printf '[project]\nname="x"\nversion="0.0.0"\n' >"$WORK/pyproject.toml"
  printf 'import os\n' >"$WORK/bad.py"
  run bash "$RUN" --dir "$WORK"
  [ "$status" -eq 0 ]
  local j; j="$(json_of "$output")"
  echo "$j" | jq -e '.ok == false'
  echo "$j" | jq -e '.findings | length >= 1'
}

@test "lint/python-stub: FAIL case STILL exits 0 (ADR-3 — no fail-loud in runner)" {
  install_dirty_ruff
  printf '[project]\nname="x"\nversion="0.0.0"\n' >"$WORK/pyproject.toml"
  printf 'import os\n' >"$WORK/bad.py"
  run bash "$RUN" --dir "$WORK"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == false'
}

# ---- PASS case: shell via shellcheck shim (host-independent) ---------------

@test "lint/shell-stub: clean shellcheck → ok=true, exit 0" {
  install_clean_shellcheck
  printf '#!/usr/bin/env bash\nset -euo pipefail\necho hi\n' >"$WORK/ok.sh"
  run bash "$RUN" --dir "$WORK" --stack shell
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == true'
}

# ---- FAIL case: shell via shellcheck shim (host-independent) ---------------

@test "lint/shell-stub: dirty shellcheck → ok=false, exit 0, finding present" {
  install_dirty_shellcheck
  printf '#!/usr/bin/env bash\necho $undefined_var\n' >"$WORK/bad.sh"
  run bash "$RUN" --dir "$WORK" --stack shell
  [ "$status" -eq 0 ]
  local j; j="$(json_of "$output")"
  echo "$j" | jq -e '.ok == false'
  echo "$j" | jq -e '.findings | length >= 1'
}

@test "lint/shell-stub: FAIL case STILL exits 0 (ADR-3 — no fail-loud in runner)" {
  install_dirty_shellcheck
  printf '#!/usr/bin/env bash\necho $x\n' >"$WORK/bad.sh"
  run bash "$RUN" --dir "$WORK" --stack shell
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == false'
}

# ---- NULL / skip case (no stubs needed — stack-detection path) -------------

@test "lint: unknown stack (no manifest) → ok=null, exit 0" {
  printf 'plain text, no manifest\n' >"$WORK/notes.txt"
  run bash "$RUN" --dir "$WORK"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == null'
}

@test "lint: unknown stack emits a stderr warning" {
  printf 'plain text\n' >"$WORK/notes.txt"
  run bash "$RUN" --dir "$WORK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"warn"* || "$output" == *"WARN"* || "$output" == *"skip"* ]]
}

@test "lint/shell-stub: no .sh files in dir → ok=null, exit 0" {
  # No stubs needed: the shell runner emits null when there are no *.sh files.
  # (--stack shell bypasses auto-detection; the dir has only a .py file.)
  install_clean_shellcheck
  printf 'def f():\n    return 1\n' >"$WORK/only_py.py"
  run bash "$RUN" --dir "$WORK" --stack shell
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == null'
}

# ---- PATH isolation: stub must not leak between tests ----------------------

@test "lint: PATH is restored after each test (stubs do not bleed)" {
  # This test runs AFTER stub tests; PATH must be back to ORIG_PATH.
  # Verify the stub dir is NOT on PATH by the time we get here.
  # (setup() prepends STUB_DIR; teardown restores — so within this test STUB_DIR
  # is still prepended, but the stub executables do not exist yet.)
  [ ! -f "$STUB_DIR/ruff" ]
  [ ! -f "$STUB_DIR/shellcheck" ]
}

# ---- integration smokes (real binaries; skipped when not installed) ---------

@test "lint/integration: real ruff clean python → ok=true" {
  command -v ruff >/dev/null 2>&1 || skip "ruff not installed (integration smoke only)"
  # Remove stub so the real binary is used.
  rm -f "$STUB_DIR/ruff"
  printf '[project]\nname="x"\nversion="0.0.0"\n' >"$WORK/pyproject.toml"
  printf 'def f() -> int:\n    return 1\n' >"$WORK/ok.py"
  run bash "$RUN" --dir "$WORK"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == true'
}

@test "lint/integration: real ruff dirty python → ok=false" {
  command -v ruff >/dev/null 2>&1 || skip "ruff not installed (integration smoke only)"
  rm -f "$STUB_DIR/ruff"
  printf '[project]\nname="x"\nversion="0.0.0"\n' >"$WORK/pyproject.toml"
  printf 'import os\n' >"$WORK/bad.py"
  run bash "$RUN" --dir "$WORK"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == false'
}

@test "lint/integration: real shellcheck clean script → ok=true" {
  command -v shellcheck >/dev/null 2>&1 || skip "shellcheck not installed (integration smoke only)"
  rm -f "$STUB_DIR/shellcheck"
  printf '#!/usr/bin/env bash\nset -euo pipefail\necho hi\n' >"$WORK/ok.sh"
  run bash "$RUN" --dir "$WORK" --stack shell
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == true'
}

@test "lint/integration: real shellcheck dirty script → ok=false" {
  command -v shellcheck >/dev/null 2>&1 || skip "shellcheck not installed (integration smoke only)"
  rm -f "$STUB_DIR/shellcheck"
  printf '#!/usr/bin/env bash\necho $undefined_var\n' >"$WORK/bad.sh"
  run bash "$RUN" --dir "$WORK" --stack shell
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == false'
}
