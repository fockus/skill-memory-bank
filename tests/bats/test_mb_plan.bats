#!/usr/bin/env bats

load 'lib/assert'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-plan.sh"
  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/plans"
  (cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t && echo init > README.md && git add README.md && git commit -q -m init)
  cd "$PROJECT"   # mb-plan.sh reads the baseline commit from the cwd's repo
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
}

# AGR-078: a stage is a dependency/layer/risk/parallel boundary, not a size
# unit, so the scaffold starts with exactly one stage that still declares
# `Files:` (parallel waves are computed from it).
@test "mb-plan: scaffold has exactly one stage marker with a Files line" {
  run bash "$SCRIPT" feature "One Stage" "$MB"
  [ "$status" -eq 0 ]
  body="$(cat "$output")"
  assert_substring "$body" '<!-- mb-stage:1 -->'
  refute_substring "$body" '<!-- mb-stage:2 -->'
  assert_substring "$body" '**Files:**'
  assert_substring "$body" 'dependency'
}

@test "mb-plan: one-stage scaffold flows through plan-sync and work-plan" {
  plan="$(bash "$SCRIPT" fix "Single Flow" "$MB")"
  sed -i.bak 's|^### Stage 1: .*|### Stage 1: do the whole fix|' "$plan" && rm -f "$plan.bak"
  printf '# Checklist\n' > "$MB/checklist.md"
  printf '# Roadmap\n' > "$MB/roadmap.md"

  run bash "$REPO_ROOT/scripts/mb-plan-sync.sh" "$plan" "$MB"
  [ "$status" -eq 0 ]
  checklist="$(cat "$MB/checklist.md")"
  assert_substring "$checklist" '— 0/1'
  assert_substring "$checklist" '- ⬜ Stage 1 — do the whole fix'
  refute_substring "$checklist" 'Stage 2'

  run bash "$REPO_ROOT/scripts/mb-work-plan.sh" --target "$plan" --mb "$MB" --dry-run
  [ "$status" -eq 0 ]
  assert_substring "$output" '"stage_no": 1'
  refute_substring "$output" '"stage_no": 2'
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
