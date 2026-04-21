#!/usr/bin/env bats
# Contract tests for index.json auto-regeneration (Step 4.5) in
# agents/mb-doctor.md.
#
# Stage 5 requires Step 4.5:
#   - When doctor touches notes/, lessons.md, or plans/ in a fix, it must
#     run `python3 ~/.claude/skills/memory-bank/scripts/mb-index-json.py
#     .memory-bank` to keep index.json fresh.
#   - The final report carries `index_regenerated=true|false` so downstream
#     callers can observe whether the index was updated.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PROMPT="$REPO_ROOT/agents/mb-doctor.md"
  [ -f "$PROMPT" ]
}

@test "index-regen: Step 4.5 heading exists" {
  # Must have an explicit numbered Step 4.5 for the regen logic.
  grep -Eq 'Step 4\.5' "$PROMPT"
}

@test "index-regen: prompt references mb-index-json.py" {
  grep -Fq 'mb-index-json.py' "$PROMPT"
}

@test "index-regen: prompt names the trigger files (notes/, lessons.md, plans/)" {
  grep -Fq 'notes/'    "$PROMPT"
  grep -Fq 'lessons.md' "$PROMPT"
  grep -Fq 'plans/'    "$PROMPT"
}

@test "index-regen: report emits index_regenerated=true|false key" {
  grep -Eq 'index_regenerated=(true\|false|true/false)|index_regenerated' "$PROMPT"
}
