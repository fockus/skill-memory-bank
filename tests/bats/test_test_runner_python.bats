#!/usr/bin/env bats
# Tests for scripts/mb-test-run.sh against a Python / pytest fixture.
#
# Contract (Stage 3 of plans/2026-04-21_refactor_agents-quality.md):
#   Usage: mb-test-run.sh [--dir <path>] [--out json|human|both]
#   JSON shape:
#     {
#       "stack": "python",
#       "tests_pass": bool | null,
#       "tests_total": N,
#       "tests_failed": N,
#       "failures": [
#         {"file": "<path>", "name": "<nodeid>", "error_head": "<first lines>"}
#       ],
#       "coverage": {"overall": "<pct>" | null, "per_file": {}},
#       "duration_ms": N
#     }
#   Exit code: 0 always — pass/fail is in the JSON, not the shell exit.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-test-run.sh"
  command -v jq >/dev/null  || skip "jq required"
  command -v pytest >/dev/null || skip "pytest required"

  TMPROOT="$(mktemp -d)"
  cd "$TMPROOT"
  cat > pyproject.toml <<'TOML'
[project]
name = "fixture"
version = "0.0.0"
TOML
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

@test "python: all-passing suite → tests_pass=true, tests_failed=0" {
  mkdir -p tests
  cat > tests/test_ok.py <<'PY'
def test_one(): assert 1 == 1
def test_two(): assert "a" + "b" == "ab"
PY
  run bash "$RUN" --dir "$TMPROOT" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.stack == "python"'
  echo "$output" | jq -e '.tests_pass == true'
  echo "$output" | jq -e '.tests_total == 2'
  echo "$output" | jq -e '.tests_failed == 0'
  echo "$output" | jq -e '.failures | length == 0'
}

@test "python: 1 pass + 1 fail → tests_pass=false, tests_failed=1, failures[0].name set" {
  mkdir -p tests
  cat > tests/test_mix.py <<'PY'
def test_pass(): assert True
def test_fail():
    expected = 2
    actual = 1 + 0
    assert actual == expected
PY
  run bash "$RUN" --dir "$TMPROOT" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.tests_pass == false'
  echo "$output" | jq -e '.tests_total == 2'
  echo "$output" | jq -e '.tests_failed == 1'
  echo "$output" | jq -e '.failures | length == 1'
  # nodeid-style name: some form of "tests/test_mix.py" and "test_fail".
  echo "$output" | jq -e '.failures[0].name | test("test_fail")'
  echo "$output" | jq -e '.failures[0].file | test("test_mix.py")'
  # error_head must contain *something* — not empty.
  echo "$output" | jq -e '(.failures[0].error_head | length) > 0'
}

@test "python: duration_ms is a non-negative integer" {
  mkdir -p tests
  echo "def test_one(): assert True" > tests/test_single.py
  run bash "$RUN" --dir "$TMPROOT" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.duration_ms >= 0'
  echo "$output" | jq -e '(.duration_ms | type) == "number"'
}

@test "python: empty tests dir → tests_total=0, tests_pass=null or true (pytest contract)" {
  mkdir -p tests
  # No test files at all; pytest returns exit 5 "no tests collected".
  run bash "$RUN" --dir "$TMPROOT" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.tests_total == 0'
  echo "$output" | jq -e '.tests_pass == null or .tests_pass == true'
}
