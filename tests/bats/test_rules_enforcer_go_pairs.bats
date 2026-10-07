#!/usr/bin/env bats

setup() {
  CHECK="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/scripts/mb-rules-check.sh"
  command -v jq >/dev/null || skip "jq required"
  TMPROOT="$(mktemp -d)"
  cd "$TMPROOT" || return 1
  mkdir -p src/internal/foo
  printf 'package foo\n' > src/internal/foo/servant.go
}

teardown() {
  rm -rf "$TMPROOT"
}

check_pair() {
  local files="src/internal/foo/servant.go${1:+,$1}"
  if [[ -n "$1" ]]; then
    mkdir -p "$(dirname "$1")"
    printf 'package foo\n' > "$1"
  fi
  run bash "$CHECK" --files "$files" --diff-files "$files" --out json
  [ "$status" -eq 0 ]
  echo "$output"
}

@test "Go feature test in the source directory covers its source" {
  check_pair src/internal/foo/servant_mtls_test.go
  echo "$output" | jq -e '.violations | length == 0'
}

@test "Go exact test naming still covers its source" {
  check_pair src/internal/foo/servant_test.go
  echo "$output" | jq -e '.violations | length == 0'
}

@test "Go missing, unrelated, wrong-prefix and wrong-directory tests leave CRITICAL" {
  local candidate
  for candidate in "" src/internal/foo/other_mtls_test.go src/internal/foo/servants_mtls_test.go src/internal/other/servant_mtls_test.go; do
    check_pair "$candidate"
    echo "$output" | jq -e '.violations | map(select(.rule == "tdd/delta" and .severity == "CRITICAL" and .file == "src/internal/foo/servant.go")) | length == 1'
  done
}

@test "ya.make registration is exempt but similarly named files and shell code are not" {
  local file expected
  for file in ya.make ya.make.sh setup.sh; do
    printf '#!/usr/bin/env bash\ntrue\n' > "src/internal/foo/$file"
    expected=1
    if [[ "$file" == ya.make ]]; then
      printf 'GO_TEST()\nEND()\n' > "src/internal/foo/$file"
      expected=0
    fi
    run bash "$CHECK" --files "src/internal/foo/$file" --diff-files "src/internal/foo/$file" --out json
    [ "$status" -eq 0 ]
    echo "$output"
    echo "$output" | jq -e --argjson expected "$expected" '.violations | map(select(.rule == "tdd/delta" and .severity == "CRITICAL")) | length == $expected'
  done
}

@test "Python feature-test wildcard is not broadened" {
  printf 'value = 1\n' > src/internal/foo/item.py
  printf 'assert True\n' > src/internal/foo/item_feature_test.py
  run bash "$CHECK" --files src/internal/foo/item.py --diff-files src/internal/foo/item.py,src/internal/foo/item_feature_test.py --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.violations | map(select(.rule == "tdd/delta" and .severity == "CRITICAL")) | length == 1'
}
