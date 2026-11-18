#!/usr/bin/env bats
# I-083 Stage 2 — mb-test-run.sh bats stack + test-command + not_applicable.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-test-run.sh"
  command -v jq >/dev/null || skip "jq required"
}

@test "runner: bats red project reports tests_pass=false" {
  command -v bats >/dev/null || skip "bats not in PATH"
  run bash "$RUN" --dir "$REPO_ROOT/tests/bats/fixtures/bats-red" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.stack == "bats"'
  echo "$output" | jq -e '.tests_pass == false'
  echo "$output" | jq -e '.tests_failed >= 1'
}

@test "runner: bats green project reports tests_pass=true" {
  command -v bats >/dev/null || skip "bats not in PATH"
  run bash "$RUN" --dir "$REPO_ROOT/tests/bats/fixtures/bats-green" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.stack == "bats"'
  echo "$output" | jq -e '.tests_pass == true'
}

@test "runner: bats suites under tests/**/fixtures are not part of the project run" {
  command -v bats >/dev/null || skip "bats not in PATH"
  TMPROOT="$(mktemp -d)"
  mkdir -p "$TMPROOT/tests/fixtures/broken"
  cp "$REPO_ROOT/tests/bats/fixtures/bats-green/tests/"*.bats "$TMPROOT/tests/"
  printf '#!/usr/bin/env bats\nload missing/helper\n@test "x" { true; }\n' >"$TMPROOT/tests/fixtures/broken/test_broken.bats"
  run bash "$RUN" --dir "$TMPROOT" --out json
  rm -rf "$TMPROOT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.tests_pass == true and .tests_failed == 0'
}

@test "runner: MB_TEST_COMMAND=false reports tests_pass=false" {
  TMPROOT="$(mktemp -d)"
  run env MB_TEST_COMMAND=false bash "$RUN" --dir "$TMPROOT" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.tests_pass == false'
  rm -rf "$TMPROOT"
}

@test "runner: empty dir emits not_applicable=true" {
  TMPROOT="$(mktemp -d)"
  run bash "$RUN" --dir "$TMPROOT" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.not_applicable == true'
  echo "$output" | jq -e '.tests_pass == null'
  rm -rf "$TMPROOT"
}

@test "runner: MB_TEST_COMMAND exit 7 sets runner_error=true" {
  TMPROOT="$(mktemp -d)"
  run env MB_TEST_COMMAND='exit 7' bash "$RUN" --dir "$TMPROOT" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.runner_error == true'
  echo "$output" | jq -e '.tests_pass == false'
  rm -rf "$TMPROOT"
}
