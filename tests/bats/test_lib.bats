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

@test "mb_sanitize_topic: cyrillic stripped (current contract)" {
  run mb_sanitize_topic "тест"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
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
