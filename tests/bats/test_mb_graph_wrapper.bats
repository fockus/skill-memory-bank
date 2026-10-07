#!/usr/bin/env bats
# graph-semantic-adoption Stage 4 — scripts/mb-graph.sh: the short front door
# to the code graph. A thin wrapper: resolves the bank (walking up from a
# project subdirectory), then delegates to mb-graph-query.py /
# mb-semantic-search.py. The delegates are stubs here that record their argv,
# so every assertion is about WHAT the wrapper hands over, not about the graph.

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  T="$(mktemp -d)"
  T="$(cd "$T" && pwd -P)"
  SK="$T/skill/scripts"
  mkdir -p "$SK"
  cp "$REPO_ROOT/scripts/mb-graph.sh" "$REPO_ROOT/scripts/_lib.sh" "$SK/"
  ARGV_LOG="$T/argv.log"
  export ARGV_LOG
  local stub
  for stub in mb-graph-query.py mb-semantic-search.py; do
    cat > "$SK/$stub" <<'EOF'
import os, sys
with open(os.environ["ARGV_LOG"], "a") as fh:
    fh.write(os.path.basename(sys.argv[0]) + " " + " ".join(sys.argv[1:]) + "\n")
sys.exit(int(os.environ.get("STUB_RC", "0")))
EOF
  done
  PROJ="$T/proj"
  mkdir -p "$PROJ/.memory-bank/codebase" "$PROJ/src/deep"
  : > "$PROJ/.memory-bank/codebase/graph.json"
  G="$PROJ/.memory-bank/codebase/graph.json"
  W="$SK/mb-graph.sh"
  unset MB_PATH
}

teardown() { [ -n "${T:-}" ] && rm -rf "$T"; }

_argv() { cat "$ARGV_LOG" 2>/dev/null; }

@test "who-calls delegates to mb-graph-query.py neighbors with the bank graph" {
  cd "$PROJ"
  run bash "$W" who-calls WriteFile
  [ "$status" -eq 0 ]
  [ "$(_argv)" = "mb-graph-query.py neighbors --graph $G --symbol WriteFile --direction in" ]
}

@test "impact and tests pass the symbol through; status passes the project root" {
  cd "$PROJ"
  bash "$W" impact Foo
  bash "$W" tests Foo
  bash "$W" status
  [ "$(_argv)" = "mb-graph-query.py impact --graph $G --symbol Foo
mb-graph-query.py tests --graph $G --symbol Foo
mb-graph-query.py status --graph $G --src-root $PROJ" ]
}

@test "bank resolves from a project subdirectory" {
  cd "$PROJ/src/deep"
  run bash "$W" who-calls WriteFile
  [ "$status" -eq 0 ]
  [ "$(_argv)" = "mb-graph-query.py neighbors --graph $G --symbol WriteFile --direction in" ]
}

@test "unknown subcommand prints usage and fails without delegating" {
  cd "$PROJ"
  run bash "$W" frobnicate WriteFile
  [ "$status" -eq 2 ]
  assert_substring "$output" "usage: mb-graph.sh"
  [ -z "$(_argv)" ]
}

@test "a symbol subcommand without a symbol prints usage and fails" {
  cd "$PROJ"
  run bash "$W" who-calls
  [ "$status" -eq 2 ]
  assert_substring "$output" "usage: mb-graph.sh"
  [ -z "$(_argv)" ]
}

@test "search with an exact CamelCase name goes to bm25" {
  cd "$PROJ"
  run bash "$W" search WorkResolver
  [ "$status" -eq 0 ]
  [ "$(_argv)" = "mb-semantic-search.py WorkResolver --backend bm25 $PROJ/.memory-bank" ]
}

@test "search with a phrase goes to embeddings" {
  cd "$PROJ"
  run bash "$W" search "where is the cache invalidated"
  [ "$status" -eq 0 ]
  [ "$(_argv)" = "mb-semantic-search.py where is the cache invalidated --backend embeddings $PROJ/.memory-bank" ]
}

@test "no bank anywhere up the tree fails with a clear message" {
  mkdir -p "$T/nobank"
  cd "$T/nobank"
  run bash "$W" who-calls WriteFile
  # 4, not 1 (delegate no_match), 2 (usage) or 3 (missing graph): "no bank" must
  # be told apart from an empty answer.
  [ "$status" -eq 4 ]
  assert_substring "$output" "no Memory Bank"
  assert_substring "$output" "MB_PATH=<bank>"
  [ -z "$(_argv)" ]
}

@test "usage documents the no-bank exit code" {
  cd "$PROJ"
  run bash "$W"
  [ "$status" -eq 2 ]
  assert_substring "$output" "exit 4 = no Memory Bank"
}

@test "status with MB_PATH outside the project uses the bank's parent as src-root" {
  # From an unrelated cwd, --src-root=$PWD would hide commit drift and the graph
  # would look fresh.
  mkdir -p "$T/elsewhere"
  cd "$T/elsewhere"
  MB_PATH="$PROJ/.memory-bank" bash "$W" status
  [ "$(_argv)" = "mb-graph-query.py status --graph $G --src-root $PROJ" ]
}

@test "status with a global bank (outside the project) takes src-root from the git repo" {
  # A registry bank lives at ~/.claude/memory-bank/projects/<id>: its parent is
  # not the project, so --src-root must come from the repo the agent stands in.
  local GB="$T/global/projects/abc123"
  mkdir -p "$GB/codebase"
  : > "$GB/codebase/graph.json"
  git -C "$PROJ" init -q
  cd "$PROJ/src/deep"
  MB_PATH="$GB" bash "$W" status
  [ "$(_argv)" = "mb-graph-query.py status --graph $GB/codebase/graph.json --src-root $PROJ" ]
}

@test "the delegate's exit code reaches the caller unchanged (1 no match, 3 missing graph)" {
  cd "$PROJ"
  run env STUB_RC=1 bash "$W" who-calls Nope
  [ "$status" -eq 1 ]
  run env STUB_RC=3 bash "$W" search "some phrase"
  [ "$status" -eq 3 ]
}
