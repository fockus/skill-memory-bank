#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-note.sh"
  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/notes"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

@test "mb-note: creates note file with sanitized topic" {
  run bash "$SCRIPT" "Fix Install Flow" "$MB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fix-install-flow.md" ]]
  [ -f "$output" ]
  grep -q '^# Fix Install Flow$' "$output"
  grep -q '^## What was done$' "$output"
}

@test "mb-note: second note with same timestamp gets collision suffix" {
  date_bin="$(command -v date)"
  fake_bin="$PROJECT/bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/date" <<EOF
#!/bin/sh
exec "$date_bin" '+%Y-%m-%d_%H-%M'
EOF
  chmod +x "$fake_bin/date"

  PATH="$fake_bin:$PATH" bash "$SCRIPT" "Repeated Topic" "$MB" >/dev/null
  run env PATH="$fake_bin:$PATH" bash "$SCRIPT" "Repeated Topic" "$MB"
  [ "$status" -eq 0 ]
  [[ "$output" == *_2.md ]]
  [ -f "$output" ]
}

@test "mb-note: rejects topic without ASCII slug" {
  run bash "$SCRIPT" "Привет" "$MB"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot build a filename"* ]]
}
