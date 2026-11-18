#!/usr/bin/env bats
# Doc contract for the S4 backlog/roadmap slice — S4 Task 5.
# Checks that references/mb/idea.md, references/mb/idea-promote.md,
# references/templates.md and CLAUDE.md state what the implementation does.
# Red-anchor: names start with `roadmap_backlog_docs: `.

bats_require_minimum_version 1.5.0

load lib/assert

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  IDEA_DOC="$ROOT/references/mb/idea.md"
  PROMOTE_DOC="$ROOT/references/mb/idea-promote.md"
  TEMPLATES="$ROOT/references/templates.md"
  PROJECT_RULES="$ROOT/CLAUDE.md"
}

# Locate a shipped file by name so a doc test never depends on the code layout.
find_file() { find "$ROOT" -maxdepth 2 -name "$1" -not -path '*/node_modules/*' -not -path '*/.git/*' | head -1; }

# usage_lines <script-name> → the synopsis lines of its `# Usage:` comment block.
usage_lines() {
  awk '/^# Usage:/{f=1;next} f && /^#[[:space:]]*$/{exit} f && /^# {2,}mb-/{sub(/^# +/,""); print}' "$(find_file "$1")"
}

@test "roadmap_backlog_docs: every machine edge is documented in a transition table row" {
  edges=$(python3 -I - "$(dirname "$(find_file mb_backlog_state_engine.py)")" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from mb_backlog_state_engine import EDGES
for src, dsts in EDGES.items():
    print(src, ",".join(dsts))
PY
)
  [ -n "$edges" ]
  while read -r src dsts; do
    row=$(grep -E "^\| \`$src\` \|" "$IDEA_DOC" || true)
    if [ -z "$dsts" ]; then
      refute_substring "$row" "$src"   # terminal states have no row
      continue
    fi
    [ -n "$row" ]
    IFS=',' read -ra targets <<< "$dsts"
    for t in "${targets[@]}"; do
      [[ "$row" == *"\`$t\`"* ]]
    done
  done <<< "$edges"
  grep -qF 'NEW → NEEDS-INFO ⇄ TRIAGED → READY → IN-PROGRESS → DONE | WONTFIX' "$IDEA_DOC"
}

@test "roadmap_backlog_docs: READY brief gate and WONTFIX out-of-scope move are documented" {
  grep -q 'READY gate' "$IDEA_DOC"
  grep -qF '**Brief:**' "$IDEA_DOC"
  grep -q 'file path or line number' "$IDEA_DOC"
  grep -q 'WONTFIX' "$IDEA_DOC"
  grep -qF -- '--reason' "$IDEA_DOC"
  grep -qF '## Out of scope' "$IDEA_DOC"
  grep -qF '**Reason:**' "$IDEA_DOC"
}

@test "roadmap_backlog_docs: promote docs require READY, never write PLANNED and show the path to READY" {
  grep -q 'must be in `READY` status' "$PROMOTE_DOC"
  grep -qF 'READY → IN-PROGRESS' "$PROMOTE_DOC"
  grep -q 'PLANNED. token is never written' "$PROMOTE_DOC"
  grep -qF 'NEW → NEEDS-INFO → TRIAGED → READY' "$PROMOTE_DOC"
  grep -qF 'mb-backlog-migrate.sh' "$PROMOTE_DOC"
  grep -qF 'promote_partial' "$PROMOTE_DOC"
  refute_grep -qE 'flips idea status .NEW.\|TRIAGED' "$PROMOTE_DOC"
}

@test "roadmap_backlog_docs: documented CLI synopses match each script usage block" {
  for name in mb-backlog-state.sh mb-bank-lint.sh mb-backlog-migrate.sh mb-idea.sh; do
    lines=$(usage_lines "$name")
    [ -n "$lines" ]
    while IFS= read -r l; do
      grep -qF -- "$l" "$IDEA_DOC"
    done <<< "$lines"
  done
}

@test "roadmap_backlog_docs: the new scripts print their synopsis for --help" {
  for name in mb-backlog-state.sh mb-bank-lint.sh mb-backlog-migrate.sh; do
    help=$(bash "$(find_file "$name")" --help)
    lines=$(usage_lines "$name")
    while IFS= read -r l; do
      [[ "$help" == *"$l"* ]]
    done <<< "$lines"
  done
}

@test "roadmap_backlog_docs: templates document every roadmap frontmatter field" {
  section=$(awk '/^## Roadmap frontmatter/{f=1;next} /^## /{f=0} f' "$TEMPLATES")
  [ -n "$section" ]
  for field in topic group ice ice_confirmed pin status created blocked_by; do
    [[ "$section" == *"$field:"* ]]
  done
  [[ "$section" == *"impact"* && "$section" == *"confidence"* && "$section" == *"ease"* ]]
  [[ "$section" == *"1..10"* ]]
  [[ "$section" == *"never stored"* ]]
}

@test "roadmap_backlog_docs: project rules state the state machine and the single global allocator" {
  grep -qF 'NEW → NEEDS-INFO ⇄ TRIAGED → READY → IN-PROGRESS → DONE | WONTFIX' "$PROJECT_RULES"
  grep -qF 'mb_next_backlog_id' "$PROJECT_RULES"
  grep -q 'globally across the bank' "$PROJECT_RULES"
}
