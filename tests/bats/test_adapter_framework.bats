#!/usr/bin/env bats

# Direct tests for adapters/_framework.sh and adapters/_contract.sh.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  FRAMEWORK="$REPO_ROOT/adapters/_framework.sh"
  CONTRACT="$REPO_ROOT/adapters/_contract.sh"
  TMPDIR="$(mktemp -d)"
  MANIFEST="$TMPDIR/manifest.json"
  command -v jq >/dev/null || skip "jq required"
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

@test "framework: adapter_write_manifest writes schema_version and preserves file order" {
  # shellcheck source=/dev/null
  source "$FRAMEWORK"

  files_json='["/tmp/a","/tmp/b","/tmp/c"]'
  extra_json='{"hooks_events":["sessionEnd"],"agents_md_owned":true}'

  run adapter_write_manifest "$MANIFEST" "cursor" "1.2.3" "$files_json" "$extra_json"
  [ "$status" -eq 0 ]
  jq -e '.schema_version == 1' "$MANIFEST" >/dev/null
  jq -e '.adapter == "cursor"' "$MANIFEST" >/dev/null
  jq -e '.files == ["/tmp/a","/tmp/b","/tmp/c"]' "$MANIFEST" >/dev/null
  jq -e '.hooks_events == ["sessionEnd"]' "$MANIFEST" >/dev/null
}

@test "contract: missing required functions fails with clear message" {
  # shellcheck source=/dev/null
  source "$CONTRACT"

  run adapter_contract_require_functions install_missing uninstall_missing
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing required adapter function"* ]]
}

@test "contract: present required functions passes" {
  # shellcheck source=/dev/null
  source "$CONTRACT"

  install_ok() { :; }
  uninstall_ok() { :; }

  run adapter_contract_require_functions install_ok uninstall_ok
  [ "$status" -eq 0 ]
}
