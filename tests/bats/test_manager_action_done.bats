#!/usr/bin/env bats
# Contract tests for the new `action: done` section in agents/mb-manager.md.
#
# Stage 6 of plans/2026-04-21_refactor_agents-quality.md requires:
#   1. A first-class `### action: done` section documenting a 6-step flow:
#      actualize → progress append → conditional STATUS/RESEARCH/lessons/
#      BACKLOG → mb-note → session-lock → index.json regen.
#   2. References to `.session-lock`, `mb-note.sh`, `mb-index-json.py` so
#      downstream orchestrators can trace what the subagent will actually
#      run.
#   3. An "Actualize conflict resolution" subsection with at least three
#      explicit conflict rules — source-of-truth must not be left to
#      interpretation.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PROMPT="$REPO_ROOT/agents/mb-manager.md"
  [ -f "$PROMPT" ]
}

@test "action-done: section '### action: done' exists" {
  grep -Eq '^### +`?action: done`?' "$PROMPT"
}

@test "action-done: references .session-lock" {
  grep -Fq '.session-lock' "$PROMPT"
}

@test "action-done: references mb-note.sh" {
  grep -Fq 'mb-note.sh' "$PROMPT"
}

@test "action-done: references mb-index-json.py" {
  grep -Fq 'mb-index-json.py' "$PROMPT"
}

@test "action-done: 6-step flow present (look for step markers)" {
  # The flow should enumerate 6 concrete steps — numbered or bulleted.
  # At minimum 6 lines starting with `1.`..`6.` inside the action block,
  # OR six ordered items in a list near the `action: done` heading.
  local from_line
  from_line=$(grep -nE '^### +`?action: done`?' "$PROMPT" | head -n1 | cut -d: -f1)
  [ -n "$from_line" ]
  # Scan the next 120 lines after the heading for enumeration.
  local numbered
  numbered=$(awk -v start="$from_line" 'NR>=start && NR<start+120' "$PROMPT" \
             | grep -cE '^[[:space:]]*[1-9]\. ')
  [ "$numbered" -ge 6 ]
}

@test "action-done: conflict-resolution subsection with ≥3 rules exists" {
  grep -Eiq 'conflict.resolution|resolv(e|ing) conflicts' "$PROMPT"
  # Specific rule markers to enforce the ≥3 requirement.
  # Rule 1: STATUS metrics vs mb-metrics.sh (trust the script).
  grep -Eiq 'mb-metrics.sh.*trust|trust.*script|prefer.*mb-metrics' "$PROMPT"
  # Rule 2: checklist vs plans/done (trust checklist).
  grep -Eq 'checklist.*plans/done|plans/done.*checklist' "$PROMPT"
  # Rule 3: progress.md append-only (never rewrite historic entries).
  grep -Fq 'APPEND' "$PROMPT"
}

@test "action-done: wording explicitly promotes from 'combined flow' to first-class" {
  # Somewhere the prompt should acknowledge that action: done is now
  # first-class — either by defining it explicitly or by stating it
  # replaces the old combined flow.
  grep -Eiq 'first-class|replaces.*combined|promoted|supersedes' "$PROMPT"
}
