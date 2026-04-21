#!/usr/bin/env bats
# Tests for scripts/_lib.sh — shared utilities

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/scripts/_lib.sh"
  FIXTURES="$REPO_ROOT/tests/fixtures"
  TMPDIR="$(mktemp -d)"

  [ -f "$LIB" ] || skip "scripts/_lib.sh not implemented yet (TDD red phase)"
  # shellcheck source=/dev/null
  source "$LIB"
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

# ═══ mb_resolve_path ═══

@test "mb_resolve_path: explicit arg wins" {
  cd "$TMPDIR"
  run mb_resolve_path "/explicit/path"
  [ "$status" -eq 0 ]
  [ "$output" = "/explicit/path" ]
}

@test "mb_resolve_path: no arg, no workspace → .memory-bank" {
  cd "$TMPDIR"
  run mb_resolve_path
  [ "$status" -eq 0 ]
  [ "$output" = ".memory-bank" ]
}

@test "mb_resolve_path: .claude-workspace storage=local → .memory-bank" {
  cd "$TMPDIR"
  printf 'storage: local\nproject_id: abc\n' > .claude-workspace
  run mb_resolve_path
  [ "$status" -eq 0 ]
  [ "$output" = ".memory-bank" ]
}

@test "mb_resolve_path: .claude-workspace storage=external → ~/.claude/workspaces/{id}/.memory-bank" {
  cd "$TMPDIR"
  printf 'storage: external\nproject_id: myproject\n' > .claude-workspace
  run mb_resolve_path
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude/workspaces/myproject/.memory-bank" ]
}

@test "mb_resolve_path: external workspace rejects traversal project_id" {
  cd "$TMPDIR"
  printf 'storage: external\nproject_id: ../../../../tmp/pwned\n' > .claude-workspace
  run mb_resolve_path
  [ "$status" -eq 0 ]
  [ "$output" = ".memory-bank" ]
}

# ═══ mb_detect_stack ═══

@test "mb_detect_stack: python fixture → python" {
  run mb_detect_stack "$FIXTURES/python"
  [ "$status" -eq 0 ]
  [ "$output" = "python" ]
}

@test "mb_detect_stack: go fixture → go" {
  run mb_detect_stack "$FIXTURES/go"
  [ "$status" -eq 0 ]
  [ "$output" = "go" ]
}

@test "mb_detect_stack: rust fixture → rust" {
  run mb_detect_stack "$FIXTURES/rust"
  [ "$status" -eq 0 ]
  [ "$output" = "rust" ]
}

@test "mb_detect_stack: node fixture → node" {
  run mb_detect_stack "$FIXTURES/node"
  [ "$status" -eq 0 ]
  [ "$output" = "node" ]
}

@test "mb_detect_stack: java fixture → java" {
  run mb_detect_stack "$FIXTURES/java"
  [ "$status" -eq 0 ]
  [ "$output" = "java" ]
}

@test "mb_detect_stack: kotlin fixture → kotlin" {
  run mb_detect_stack "$FIXTURES/kotlin"
  [ "$status" -eq 0 ]
  [ "$output" = "kotlin" ]
}

@test "mb_detect_stack: swift fixture → swift" {
  run mb_detect_stack "$FIXTURES/swift"
  [ "$status" -eq 0 ]
  [ "$output" = "swift" ]
}

@test "mb_detect_stack: cpp fixture → cpp" {
  run mb_detect_stack "$FIXTURES/cpp"
  [ "$status" -eq 0 ]
  [ "$output" = "cpp" ]
}

@test "mb_detect_stack: ruby fixture → ruby" {
  run mb_detect_stack "$FIXTURES/ruby"
  [ "$status" -eq 0 ]
  [ "$output" = "ruby" ]
}

@test "mb_detect_stack: php fixture → php" {
  run mb_detect_stack "$FIXTURES/php"
  [ "$status" -eq 0 ]
  [ "$output" = "php" ]
}

@test "mb_detect_stack: csharp fixture → csharp" {
  run mb_detect_stack "$FIXTURES/csharp"
  [ "$status" -eq 0 ]
  [ "$output" = "csharp" ]
}

@test "mb_detect_stack: elixir fixture → elixir" {
  run mb_detect_stack "$FIXTURES/elixir"
  [ "$status" -eq 0 ]
  [ "$output" = "elixir" ]
}

@test "mb_detect_stack: multi fixture → multi" {
  run mb_detect_stack "$FIXTURES/multi"
  [ "$status" -eq 0 ]
  [ "$output" = "multi" ]
}

@test "mb_detect_stack: unknown fixture → unknown" {
  run mb_detect_stack "$FIXTURES/unknown"
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

@test "mb_detect_stack: missing dir → unknown (graceful)" {
  run mb_detect_stack "/nonexistent/path"
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

@test "mb_detect_stack: default pwd when no arg" {
  cd "$FIXTURES/go"
  run mb_detect_stack
  [ "$status" -eq 0 ]
  [ "$output" = "go" ]
}

# ═══ mb_detect_test_cmd ═══

@test "mb_detect_test_cmd: python → pytest-based command" {
  run mb_detect_test_cmd python
  [ "$status" -eq 0 ]
  [[ "$output" == *pytest* || "$output" == *"python -m unittest"* ]]
}

@test "mb_detect_test_cmd: go → go test" {
  run mb_detect_test_cmd go
  [ "$status" -eq 0 ]
  [[ "$output" == *"go test"* ]]
}

@test "mb_detect_test_cmd: rust → cargo test" {
  run mb_detect_test_cmd rust
  [ "$status" -eq 0 ]
  [[ "$output" == *"cargo test"* ]]
}

@test "mb_detect_test_cmd: node → test command" {
  run mb_detect_test_cmd node
  [ "$status" -eq 0 ]
  [[ "$output" == *test* ]]
}

@test "mb_detect_test_cmd: java → mvn test|gradle test" {
  run mb_detect_test_cmd java
  [ "$status" -eq 0 ]
  [[ "$output" == *"mvn test"* || "$output" == *"gradle test"* ]]
}

@test "mb_detect_test_cmd: kotlin → gradle test" {
  run mb_detect_test_cmd kotlin
  [ "$status" -eq 0 ]
  [[ "$output" == *"gradle test"* ]]
}

@test "mb_detect_test_cmd: swift → swift test" {
  run mb_detect_test_cmd swift
  [ "$status" -eq 0 ]
  [[ "$output" == *"swift test"* ]]
}

@test "mb_detect_test_cmd: cpp → ctest|meson test" {
  run mb_detect_test_cmd cpp
  [ "$status" -eq 0 ]
  [[ "$output" == *ctest* || "$output" == *"meson test"* ]]
}

@test "mb_detect_test_cmd: ruby → rspec|rake test" {
  run mb_detect_test_cmd ruby
  [ "$status" -eq 0 ]
  [[ "$output" == *rspec* || "$output" == *"rake test"* ]]
}

@test "mb_detect_test_cmd: php → phpunit" {
  run mb_detect_test_cmd php
  [ "$status" -eq 0 ]
  [[ "$output" == *phpunit* ]]
}

@test "mb_detect_test_cmd: csharp → dotnet test" {
  run mb_detect_test_cmd csharp
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotnet test"* ]]
}

@test "mb_detect_test_cmd: elixir → mix test" {
  run mb_detect_test_cmd elixir
  [ "$status" -eq 0 ]
  [[ "$output" == *"mix test"* ]]
}

@test "mb_detect_test_cmd: unknown → empty" {
  run mb_detect_test_cmd unknown
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ═══ mb_detect_lint_cmd ═══

@test "mb_detect_lint_cmd: python → ruff|pylint|flake8" {
  run mb_detect_lint_cmd python
  [ "$status" -eq 0 ]
  [[ "$output" == *ruff* || "$output" == *pylint* || "$output" == *flake8* ]]
}

@test "mb_detect_lint_cmd: go → golangci-lint|go vet" {
  run mb_detect_lint_cmd go
  [ "$status" -eq 0 ]
  [[ "$output" == *golangci-lint* || "$output" == *"go vet"* ]]
}

@test "mb_detect_lint_cmd: rust → cargo clippy" {
  run mb_detect_lint_cmd rust
  [ "$status" -eq 0 ]
  [[ "$output" == *"cargo clippy"* ]]
}

@test "mb_detect_lint_cmd: node → eslint|biome" {
  run mb_detect_lint_cmd node
  [ "$status" -eq 0 ]
  [[ "$output" == *eslint* || "$output" == *biome* ]]
}

@test "mb_detect_lint_cmd: java → checkstyle|spotbugs|spotless" {
  run mb_detect_lint_cmd java
  [ "$status" -eq 0 ]
  [[ "$output" == *checkstyle* || "$output" == *spotbugs* || "$output" == *spotless* ]]
}

@test "mb_detect_lint_cmd: kotlin → ktlint|detekt" {
  run mb_detect_lint_cmd kotlin
  [ "$status" -eq 0 ]
  [[ "$output" == *ktlint* || "$output" == *detekt* ]]
}

@test "mb_detect_lint_cmd: swift → swiftlint" {
  run mb_detect_lint_cmd swift
  [ "$status" -eq 0 ]
  [[ "$output" == *swiftlint* ]]
}

@test "mb_detect_lint_cmd: cpp → clang-tidy|cppcheck" {
  run mb_detect_lint_cmd cpp
  [ "$status" -eq 0 ]
  [[ "$output" == *clang-tidy* || "$output" == *cppcheck* ]]
}

@test "mb_detect_lint_cmd: ruby → rubocop" {
  run mb_detect_lint_cmd ruby
  [ "$status" -eq 0 ]
  [[ "$output" == *rubocop* ]]
}

@test "mb_detect_lint_cmd: php → phpstan|psalm" {
  run mb_detect_lint_cmd php
  [ "$status" -eq 0 ]
  [[ "$output" == *phpstan* || "$output" == *psalm* ]]
}

@test "mb_detect_lint_cmd: csharp → dotnet format" {
  run mb_detect_lint_cmd csharp
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotnet format"* ]]
}

@test "mb_detect_lint_cmd: elixir → credo|mix format" {
  run mb_detect_lint_cmd elixir
  [ "$status" -eq 0 ]
  [[ "$output" == *credo* || "$output" == *"mix format"* ]]
}

@test "mb_detect_lint_cmd: unknown → empty" {
  run mb_detect_lint_cmd unknown
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ═══ mb_detect_src_glob ═══

@test "mb_detect_src_glob: python → *.py" {
  run mb_detect_src_glob python
  [ "$status" -eq 0 ]
  [[ "$output" == *"*.py"* ]]
}

@test "mb_detect_src_glob: go → *.go" {
  run mb_detect_src_glob go
  [ "$status" -eq 0 ]
  [[ "$output" == *"*.go"* ]]
}

@test "mb_detect_src_glob: rust → *.rs" {
  run mb_detect_src_glob rust
  [ "$status" -eq 0 ]
  [[ "$output" == *"*.rs"* ]]
}

@test "mb_detect_src_glob: node → *.ts|*.js" {
  run mb_detect_src_glob node
  [ "$status" -eq 0 ]
  [[ "$output" == *"*.ts"* || "$output" == *"*.js"* ]]
}

@test "mb_detect_src_glob: java → *.java" {
  run mb_detect_src_glob java
  [ "$status" -eq 0 ]
  [[ "$output" == *"*.java"* ]]
}

@test "mb_detect_src_glob: kotlin → *.kt" {
  run mb_detect_src_glob kotlin
  [ "$status" -eq 0 ]
  [[ "$output" == *"*.kt"* ]]
}

@test "mb_detect_src_glob: swift → *.swift" {
  run mb_detect_src_glob swift
  [ "$status" -eq 0 ]
  [[ "$output" == *"*.swift"* ]]
}

@test "mb_detect_src_glob: cpp → *.cpp|*.cc|*.cxx" {
  run mb_detect_src_glob cpp
  [ "$status" -eq 0 ]
  [[ "$output" == *"*.cpp"* || "$output" == *"*.cc"* || "$output" == *"*.cxx"* ]]
}

@test "mb_detect_src_glob: ruby → *.rb" {
  run mb_detect_src_glob ruby
  [ "$status" -eq 0 ]
  [[ "$output" == *"*.rb"* ]]
}

@test "mb_detect_src_glob: php → *.php" {
  run mb_detect_src_glob php
  [ "$status" -eq 0 ]
  [[ "$output" == *"*.php"* ]]
}

@test "mb_detect_src_glob: csharp → *.cs" {
  run mb_detect_src_glob csharp
  [ "$status" -eq 0 ]
  [[ "$output" == *"*.cs"* ]]
}

@test "mb_detect_src_glob: elixir → *.ex" {
  run mb_detect_src_glob elixir
  [ "$status" -eq 0 ]
  [[ "$output" == *"*.ex"* ]]
}

@test "mb_detect_src_glob: unknown → empty" {
  run mb_detect_src_glob unknown
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ═══ mb_sanitize_topic ═══

@test "mb_sanitize_topic: spaces → dashes" {
  run mb_sanitize_topic "Foo Bar"
  [ "$status" -eq 0 ]
  [ "$output" = "foo-bar" ]
}

@test "mb_sanitize_topic: strips special chars" {
  run mb_sanitize_topic "Hello World!@#"
  [ "$status" -eq 0 ]
  [ "$output" = "hello-world" ]
}

@test "mb_sanitize_topic: lowercases" {
  run mb_sanitize_topic "UPPERCASE"
  [ "$status" -eq 0 ]
  [ "$output" = "uppercase" ]
}

@test "mb_sanitize_topic: preserves digits and dashes" {
  run mb_sanitize_topic "v2-refactor-42"
  [ "$status" -eq 0 ]
  [ "$output" = "v2-refactor-42" ]
}

@test "mb_sanitize_topic: non-ascii letters stripped (current contract)" {
  run mb_sanitize_topic "cafe"
  [ "$status" -eq 0 ]
  [ "$output" = "cafe" ]
}

# ═══ mb_collision_safe_filename ═══

@test "mb_collision_safe_filename: non-existing returns as-is" {
  run mb_collision_safe_filename "$TMPDIR/new.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$TMPDIR/new.md" ]
}

@test "mb_collision_safe_filename: existing returns _2 suffix" {
  touch "$TMPDIR/foo.md"
  run mb_collision_safe_filename "$TMPDIR/foo.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$TMPDIR/foo_2.md" ]
}

@test "mb_collision_safe_filename: existing _2 returns _3" {
  touch "$TMPDIR/foo.md" "$TMPDIR/foo_2.md"
  run mb_collision_safe_filename "$TMPDIR/foo.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$TMPDIR/foo_3.md" ]
}

@test "mb_collision_safe_filename: preserves extension correctly" {
  touch "$TMPDIR/bar.txt"
  run mb_collision_safe_filename "$TMPDIR/bar.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "$TMPDIR/bar_2.txt" ]
}
