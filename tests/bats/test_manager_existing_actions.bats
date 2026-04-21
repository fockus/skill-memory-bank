#!/usr/bin/env bats
# Regression contract for agents/mb-manager.md after Stage 6 refactor.
#
# The refactor adds `action: done`, removes template duplication, and
# reorders Rules before Actions. Existing action sections (context, search,
# note, actualize, tasks) must still be present and greppable so current
# callers of `/mb context`, `/mb search`, `/mb note`, `/mb update`,
# `/mb tasks` keep working.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PROMPT="$REPO_ROOT/agents/mb-manager.md"
  [ -f "$PROMPT" ]
}

@test "regression: frontmatter (name: mb-manager, tools, color) still present" {
  head -n 20 "$PROMPT" | grep -q '^name: mb-manager$'
  head -n 20 "$PROMPT" | grep -q '^description: '
  head -n 20 "$PROMPT" | grep -q '^tools: '
  head -n 20 "$PROMPT" | grep -q '^color: '
}

@test "regression: action: context section still present" {
  grep -Eq '^### +`?action: context`?' "$PROMPT"
}

@test "regression: action: search section still present" {
  grep -Eq '^### +`?action: search' "$PROMPT"
}

@test "regression: action: note section still present" {
  grep -Eq '^### +`?action: note' "$PROMPT"
}

@test "regression: action: actualize section still present" {
  grep -Eq '^### +`?action: actualize`?' "$PROMPT"
}

@test "regression: action: tasks section still present" {
  grep -Eq '^### +`?action: tasks`?' "$PROMPT"
}

@test "regression: Memory Bank structure tree still documented" {
  grep -Fq 'STATUS.md' "$PROMPT"
  grep -Fq 'plan.md'   "$PROMPT"
  grep -Fq 'RESEARCH.md' "$PROMPT"
  grep -Fq 'experiments/' "$PROMPT"
  grep -Fq 'progress.md' "$PROMPT"
}

@test "regression: Rules block still lists append-only progress rule" {
  # The "progress.md is APPEND-ONLY" rule must survive the reorder.
  grep -Eq 'progress\.md.*APPEND|APPEND.*progress\.md' "$PROMPT"
}

@test "regression: Invocation slot exists so caller can append action+context" {
  grep -Eq '^## +Invocation|Invocation format' "$PROMPT"
}

@test "regression: Rules appear BEFORE first '### action:' section (Stage 6 reorder)" {
  local rules_line first_action
  rules_line=$(grep -nE '^## +Rules' "$PROMPT" | head -n1 | cut -d: -f1)
  first_action=$(grep -nE '^### +`?action: ' "$PROMPT" | head -n1 | cut -d: -f1)
  [ -n "$rules_line" ]
  [ -n "$first_action" ]
  [ "$rules_line" -lt "$first_action" ]
}
