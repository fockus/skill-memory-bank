#!/usr/bin/env bats
# Tests for scripts/mb-metrics.sh — language-agnostic metrics collector.
#
# Contract:
#   Default (read-only) mode — detects stack, prints structured key=value lines.
#   --run mode — additionally executes test_cmd and records pass/fail.
#   Honors .memory-bank/metrics.sh override when present.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-metrics.sh"
  FIXTURES="$REPO_ROOT/tests/fixtures"
  TMPDIR="$(mktemp -d)"

  [ -f "$SCRIPT" ] || skip "scripts/mb-metrics.sh not implemented yet (TDD red)"
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

# ═══ Detection ═══

@test "metrics: python fixture → stack=python, test_cmd contains pytest" {
  run bash "$SCRIPT" "$FIXTURES/python"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack=python"* ]]
  [[ "$output" == *"test_cmd=pytest"* ]]
}

@test "metrics: go fixture → stack=go, test_cmd=go test" {
  run bash "$SCRIPT" "$FIXTURES/go"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack=go"* ]]
  [[ "$output" == *"test_cmd=go test"* ]]
}

@test "metrics: rust fixture → stack=rust, test_cmd=cargo test" {
  run bash "$SCRIPT" "$FIXTURES/rust"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack=rust"* ]]
  [[ "$output" == *"test_cmd=cargo test"* ]]
}

@test "metrics: java fixture → stack=java, src_count >= 1" {
  run bash "$SCRIPT" "$FIXTURES/java"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack=java"* ]]
  src_line=$(echo "$output" | grep '^src_count=')
  count="${src_line#src_count=}"
  [ "$count" -ge 1 ]
}

@test "metrics: kotlin fixture → stack=kotlin, test_cmd=gradle test, src_count >= 1" {
  run bash "$SCRIPT" "$FIXTURES/kotlin"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack=kotlin"* ]]
  [[ "$output" == *"gradle test"* ]]
  src_line=$(echo "$output" | grep '^src_count=')
  count="${src_line#src_count=}"
  [ "$count" -ge 1 ]
}

@test "metrics: swift fixture → stack=swift, test_cmd=swift test, src_count >= 1" {
  run bash "$SCRIPT" "$FIXTURES/swift"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack=swift"* ]]
  [[ "$output" == *"swift test"* ]]
  src_line=$(echo "$output" | grep '^src_count=')
  count="${src_line#src_count=}"
  [ "$count" -ge 1 ]
}

@test "metrics: cpp fixture → stack=cpp, src_count >= 1" {
  run bash "$SCRIPT" "$FIXTURES/cpp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack=cpp"* ]]
  src_line=$(echo "$output" | grep '^src_count=')
  count="${src_line#src_count=}"
  [ "$count" -ge 1 ]
}

@test "metrics: ruby fixture → stack=ruby, src_count >= 1" {
  run bash "$SCRIPT" "$FIXTURES/ruby"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack=ruby"* ]]
  src_line=$(echo "$output" | grep '^src_count=')
  count="${src_line#src_count=}"
  [ "$count" -ge 1 ]
}

@test "metrics: php fixture → stack=php, test_cmd contains phpunit, src_count >= 1" {
  run bash "$SCRIPT" "$FIXTURES/php"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack=php"* ]]
  [[ "$output" == *phpunit* ]]
  src_line=$(echo "$output" | grep '^src_count=')
  count="${src_line#src_count=}"
  [ "$count" -ge 1 ]
}

@test "metrics: csharp fixture → stack=csharp, test_cmd=dotnet test, src_count >= 1" {
  run bash "$SCRIPT" "$FIXTURES/csharp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack=csharp"* ]]
  [[ "$output" == *"dotnet test"* ]]
  src_line=$(echo "$output" | grep '^src_count=')
  count="${src_line#src_count=}"
  [ "$count" -ge 1 ]
}

@test "metrics: elixir fixture → stack=elixir, test_cmd=mix test, src_count >= 1" {
  run bash "$SCRIPT" "$FIXTURES/elixir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack=elixir"* ]]
  [[ "$output" == *"mix test"* ]]
  src_line=$(echo "$output" | grep '^src_count=')
  count="${src_line#src_count=}"
  [ "$count" -ge 1 ]
}

@test "metrics: node fixture → stack=node, test_cmd contains test" {
  run bash "$SCRIPT" "$FIXTURES/node"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack=node"* ]]
  [[ "$output" == *"test_cmd="*test* ]]
}

# ═══ Graceful fallback ═══

@test "metrics: unknown fixture → exit 0, warning on stderr" {
  run bash "$SCRIPT" "$FIXTURES/unknown"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack=unknown"* ]]
  [[ "$stderr" == *"stack"* ]] || \
    [[ "$output" == *"warning"* ]]
}

@test "metrics: missing directory → exit 0, graceful" {
  run bash "$SCRIPT" "/nonexistent/path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack=unknown"* ]]
}

# ═══ Structured output ═══

@test "metrics: python fixture → src_count is numeric" {
  run bash "$SCRIPT" "$FIXTURES/python"
  [ "$status" -eq 0 ]
  src_line=$(echo "$output" | grep '^src_count=')
  [ -n "$src_line" ]
  count="${src_line#src_count=}"
  [[ "$count" =~ ^[0-9]+$ ]]
  [ "$count" -ge 1 ]
}

@test "metrics: go fixture → src_count >= 1 (main.go)" {
  run bash "$SCRIPT" "$FIXTURES/go"
  [ "$status" -eq 0 ]
  src_line=$(echo "$output" | grep '^src_count=')
  count="${src_line#src_count=}"
  [ "$count" -ge 1 ]
}

# ═══ Override ═══

@test "metrics: .memory-bank/metrics.sh override takes priority" {
  mkdir -p "$TMPDIR/.memory-bank"
  cat > "$TMPDIR/.memory-bank/metrics.sh" <<'EOF'
#!/usr/bin/env bash
echo "stack=custom-override"
echo "test_cmd=custom-test"
echo "src_count=999"
EOF
  chmod +x "$TMPDIR/.memory-bank/metrics.sh"

  cd "$TMPDIR"
  run bash "$SCRIPT" "$TMPDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack=custom-override"* ]]
  [[ "$output" == *"src_count=999"* ]]
}

# ═══ --run mode ═══

@test "metrics --run: unknown stack exits 0 without running" {
  run bash "$SCRIPT" --run "$FIXTURES/unknown"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack=unknown"* ]]
}
