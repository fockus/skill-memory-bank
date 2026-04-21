#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-plan.sh"
  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/plans"
  (cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t && echo init > README.md && git add README.md && git commit -q -m init)
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

@test "mb-plan: creates plan with baseline commit and stage markers" {
  run bash "$SCRIPT" refactor "Review Hardening" "$MB"
  [ "$status" -eq 0 ]
  [ -f "$output" ]
  grep -q '^# Plan: refactor — review-hardening$' "$output"
  grep -Eq '^\*\*Baseline commit:\*\* [0-9a-f]{40}$' "$output"
  grep -q '<!-- mb-stage:1 -->' "$output"
  grep -q '<!-- mb-stage:2 -->' "$output"
}

@test "mb-plan: rejects invalid plan type" {
  run bash "$SCRIPT" invalid "Topic" "$MB"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown type"* ]]
}

@test "mb-plan: rejects topic without ASCII slug" {
  run bash "$SCRIPT" feature "Привет" "$MB"
  [ "$status" -ne 0 ]
  [[ "$output" == *"contains only non-ASCII characters"* ]]
}
