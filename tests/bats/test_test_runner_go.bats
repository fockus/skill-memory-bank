#!/usr/bin/env bats
# Tests for scripts/mb-test-run.sh against a Go / `go test` fixture.
#
# Same JSON contract as the Python suite.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-test-run.sh"
  command -v jq >/dev/null || skip "jq required"
  command -v go >/dev/null || skip "go required"

  TMPROOT="$(mktemp -d)"
  cd "$TMPROOT"
  cat > go.mod <<'GO'
module fixture

go 1.21
GO
}

teardown() {
  if [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ]; then
    rm -rf "$TMPROOT"
  fi
}

@test "go: all-passing suite → tests_pass=true, tests_failed=0" {
  cat > math_test.go <<'GO'
package fixture

import "testing"

func TestAdd(t *testing.T) {
    if 1+1 != 2 { t.Fatal("math broken") }
}
func TestConcat(t *testing.T) {
    if "a"+"b" != "ab" { t.Fatal("strings broken") }
}
GO
  run bash "$RUN" --dir "$TMPROOT" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.stack == "go"'
  echo "$output" | jq -e '.tests_pass == true'
  echo "$output" | jq -e '.tests_failed == 0'
  echo "$output" | jq -e '.tests_total >= 2'
}

@test "go: 1 pass + 1 fail → tests_pass=false, tests_failed=1" {
  cat > math_test.go <<'GO'
package fixture

import "testing"

func TestGood(t *testing.T) {
    if 1 != 1 { t.Fatal("wat") }
}
func TestBad(t *testing.T) {
    t.Errorf("deliberately failing: expected %d got %d", 2, 3)
}
GO
  run bash "$RUN" --dir "$TMPROOT" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.tests_pass == false'
  echo "$output" | jq -e '.tests_failed == 1'
  echo "$output" | jq -e '.failures | length == 1'
  echo "$output" | jq -e '.failures[0].name | test("TestBad")'
}

@test "go: duration_ms is a non-negative integer" {
  cat > math_test.go <<'GO'
package fixture
import "testing"
func TestOne(t *testing.T) {}
GO
  run bash "$RUN" --dir "$TMPROOT" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.duration_ms >= 0'
}
