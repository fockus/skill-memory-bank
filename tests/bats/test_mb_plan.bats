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

@test "mb-plan: emits roadmap-sync frontmatter (status/type/topic) so the plan is not skipped" {
  run bash "$SCRIPT" fix "Roadmap Visible" "$MB"
  [ "$status" -eq 0 ]
  # First line must open a YAML frontmatter block.
  [ "$(head -1 "$output")" = "---" ]
  # Keys mb-roadmap-sync.sh reads.
  grep -Eq '^status: in_progress$' "$output"
  grep -Eq '^type: fix$' "$output"
  grep -Eq '^topic: roadmap-visible$' "$output"
  grep -Eq '^parallel_safe: false$' "$output"
  grep -Eq '^depends_on: \[\]$' "$output"
  # The `# Plan:` heading still present after the frontmatter.
  grep -q '^# Plan: fix — roadmap-visible$' "$output"
}

@test "mb-plan: roadmap-sync ingests the scaffolded plan (no skip warning; appears under Now)" {
  printf '# Roadmap\n' > "$MB/roadmap.md"
  plan="$(bash "$SCRIPT" fix "Sync Me" "$MB")"
  run bash "$REPO_ROOT/scripts/mb-roadmap-sync.sh" "$MB"
  [ "$status" -eq 0 ]
  [[ "$output" != *"skipping plan without frontmatter: $plan"* ]]
  grep -q 'sync-me' "$MB/roadmap.md"
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
