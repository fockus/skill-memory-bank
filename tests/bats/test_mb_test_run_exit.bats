#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  PROJECT="$BATS_TEST_TMPDIR/project"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$PROJECT/tests" "$BIN" "$BATS_TEST_TMPDIR/home" "$BATS_TEST_TMPDIR/tmp"
  cd "$PROJECT" || return 1
}

# Do not inherit MB_TEST_COMMAND, pytest options or the outer Bats run's state.
run_cli() {
  local script="$1"
  shift
  run --separate-stderr env -i PATH="$BIN:$ROOT/.venv/bin:$BATS_ROOT/bin:$PATH" \
    HOME="$BATS_TEST_TMPDIR/home" TMPDIR="$BATS_TEST_TMPDIR/tmp" \
    GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR" PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 \
    GOPROXY=off GOTOOLCHAIN=local bash "$ROOT/scripts/$script" --dir "$PROJECT" --out json "$@"
}

python_pass() {
  touch pyproject.toml
  printf 'def test_one(): assert True\n' >tests/test_one.py
}

python_crash() {
  python_pass
  printf 'def pytest_unconfigure(config):\n    raise RuntimeError("late cleanup failure")\n' >conftest.py
}

bats_pass() {
  printf '@test "one" { true; }\n' >tests/one.bats
}

bats_crash() {
  bats_pass
  # Exercise the real Bats output, then fail without printing a 'not ok' line.
  printf '#!/bin/sh\n"%s/bin/bats" "$@" || exit $?\nexit 21\n' "$BATS_ROOT" >"$BIN/bats"
  chmod +x "$BIN/bats"
}

assert_crash() {
  [ "$status" -eq 0 ]
  jq -e --arg stack "$1" --argjson total "$2" '
    .stack == $stack and .tests_total == $total and .tests_failed == 0 and
    .tests_pass == false and .runner_error == true and .not_applicable == false
  ' <<<"$output"
}

@test "pytest: a cleanup crash after one pass fails the run, not the test" {
  python_crash
  run_cli mb-test-run.sh
  assert_crash python 1
}

@test "Go: TestMain exits after the test passes" {
  command -v go >/dev/null || skip "go required"
  printf 'module fixture\n\ngo 1.20\n' >go.mod
  cat >one_test.go <<'GO'
package fixture
import ("os"; "testing")
func TestOne(t *testing.T) {}
func TestMain(m *testing.M) { m.Run(); os.Exit(2) }
GO
  run_cli mb-test-run.sh
  assert_crash go 1
}

@test "Bats: a nonzero exit after ok is not a passing run" {
  bats_crash
  run_cli mb-test-run.sh
  assert_crash bats 1
}

@test "mixed: a Bats pass cannot mask a later pytest crash" {
  bats_pass
  python_crash
  run_cli mb-test-run.sh
  assert_crash bats+python 2
}

@test "mixed: a later pytest pass cannot clear an earlier Bats crash" {
  bats_crash
  python_pass
  run_cli mb-test-run.sh
  assert_crash bats+python 2
}

@test "mixed: a Bats pass cannot mask a pytest crash without a summary" {
  bats_pass
  python_pass
  printf 'def pytest_configure(config):\n    raise RuntimeError("startup failure")\n' >conftest.py
  run_cli mb-test-run.sh
  assert_crash bats+python 1
}

@test "pytest: an assertion failure is counted once, not as a runner crash" {
  python_pass
  printf 'def test_bad(): assert False\n' >>tests/test_one.py
  run_cli mb-test-run.sh
  [ "$status" -eq 0 ]
  jq -e '.tests_pass == false and .tests_total == 2 and .tests_failed == 1 and
         .runner_error == false and [.failures[].name] == ["test_bad"]' <<<"$output"
}

@test "pytest: no collected tests remains NOT-RUN despite exit 5" {
  touch pyproject.toml
  run_cli mb-test-run.sh
  [ "$status" -eq 0 ]
  jq -e '.stack == "python" and .tests_pass == null and .tests_total == 0 and
         .tests_failed == 0 and .runner_error == false and .not_applicable == false' <<<"$output"
}

@test "done gates: a late pytest crash blocks closure via the real runner" {
  python_crash
  mkdir .memory-bank
  run_cli mb-done-gates.sh --mb "$PROJECT/.memory-bank"
  [ "$status" -eq 2 ]
  jq -se '[.[] | select(.gate == "tests") | .pass] == [false]' <<<"$output"
}
