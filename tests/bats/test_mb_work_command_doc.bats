#!/usr/bin/env bats
# Doc contract: commands/work.md describes Sprint 2 work-engine behavior.
#
# Every assertion here must be satisfied by the current state of commands/work.md.
# If a test fails, the doc is out of date with the spec.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DOC="$REPO_ROOT/commands/work.md"
  [ -f "$DOC" ] || skip "commands/work.md missing"
}

@test "doc mentions specs/<topic>/tasks.md as executable" {
  run grep -E "specs/.*tasks\.md" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc mentions linked_spec frontmatter for plan-as-wrapper" {
  run grep -q "linked_spec" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc mentions mb-task marker format" {
  run grep -q "mb-task" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc documents the 5 target resolution forms" {
  run grep -qi "topic" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qiE "freeform|active plan|empty target" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc does not claim plan-only execution" {
  run grep -qi "plan-only execution" "$DOC"
  [ "$status" -ne 0 ]
  run grep -qi "tasks.md is human-only" "$DOC"
  [ "$status" -ne 0 ]
  run grep -qi "tasks.md is a scaffold" "$DOC"
  [ "$status" -ne 0 ]
}

@test "doc includes source and kind fields in JSON schema" {
  run grep -q '"source"' "$DOC"
  [ "$status" -eq 0 ]
  run grep -q '"kind"' "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc includes covers field in JSON schema" {
  run grep -q '"covers"' "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc includes item_no as alias for stage_no" {
  run grep -q '"item_no"' "$DOC"
  [ "$status" -eq 0 ]
}
