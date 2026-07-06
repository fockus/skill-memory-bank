#!/usr/bin/env bats
# Security: Bash write targets must go through protected-path guard.

setup() {
  HOOK="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/mb-protected-paths-guard.sh"
  SANDBOX="$(mktemp -d)"
  REPO="$SANDBOX/repo"
  mkdir -p "$REPO/.memory-bank"
  cat > "$REPO/.memory-bank/pipeline.yaml" <<'YAML'
protected_paths:
  - ".env*"
  - "ci/**"
  - "*.pem"
YAML
  export MB_PROJECT_ROOT="$REPO"
  command -v jq >/dev/null 2>&1 || skip "jq required"
}

teardown() {
  [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ] && rm -rf "$SANDBOX"
}

_guard() {
  ( cd "$REPO" && printf '%s' "$1" | bash "$HOOK" )
}

@test "bash_guard: blocks tee into env" {
  run _guard '{"tool_name":"Bash","tool_input":{"command":"tee .env <<<X"}}'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'permissionDecision'
}

@test "bash_guard: blocks sed inplace protected" {
  run _guard '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ ci/deploy.sh"}}'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'permissionDecision'
}

@test "bash_guard: blocks redirect into pem" {
  run _guard '{"tool_name":"Bash","tool_input":{"command":"echo k > secret.pem"}}'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'permissionDecision'
}

@test "bash_guard: allows plain read command" {
  run _guard '{"tool_name":"Bash","tool_input":{"command":"cat README.md"}}'
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ] || [ -z "$output" ]
}
