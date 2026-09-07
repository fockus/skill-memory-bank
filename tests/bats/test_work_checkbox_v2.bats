#!/usr/bin/env bats
# Sprint 1 Stage 5 — mb-work-checkbox.sh mirrors a gated DoD flip onto the
# plan's checklist.md v2 block. The plan-file flip is the gate; the checklist
# mirror is fail-open (missing block → warn, exit 0).

load 'lib/assert'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  CHECKBOX="$REPO_ROOT/scripts/mb-work-checkbox.sh"
  TMPROOT="$(mktemp -d)"
  MB="$TMPROOT/.memory-bank"
  mkdir -p "$MB/plans"

  PLAN="$MB/plans/2026-09-01_feature_widgets.md"
  cat > "$PLAN" <<'EOF'
<!-- mb-stage:1 -->
## Stage 1: build the widget
**DoD**
- ⬜ widget builds

<!-- mb-stage:2 -->
## Stage 2: ship the widget
**DoD**
- ⬜ widget ships
EOF

  cat > "$MB/checklist.md" <<'EOF'
# Project — Checklist

<!-- mb-plan:2026-09-01_feature_widgets.md -->
## widget pipeline — 0/2
- ⬜ Stage 1 — build the widget
- ⬜ Stage 2 — ship the widget
EOF

  printf '{"phase":"done","item_no":1}\n' > "$MB/.work-state.json"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

@test "checkbox-v2: flip marks the stage line in the checklist block" {
  run bash "$CHECKBOX" flip "$PLAN" 1 --mb "$MB"
  [ "$status" -eq 0 ]

  assert_grep -q '^- ✅ widget builds$' "$PLAN"
  assert_grep -q '^- ✅ Stage 1 — build the widget$' "$MB/checklist.md"
  assert_grep -q '^- ⬜ Stage 2 — ship the widget$' "$MB/checklist.md"
  assert_grep -q '^## widget pipeline — 1/2$' "$MB/checklist.md"
}

@test "checkbox-v2: refused flip leaves the checklist block untouched" {
  before="$(shasum "$MB/checklist.md" | awk '{print $1}')"
  run bash "$CHECKBOX" flip "$PLAN" 2 --mb "$MB"
  [ "$status" -eq 1 ]
  [ "$(shasum "$MB/checklist.md" | awk '{print $1}')" = "$before" ]
}

@test "checkbox-v2: missing checklist block warns but never fails the loop" {
  printf '# Project — Checklist\n' > "$MB/checklist.md"
  run bash "$CHECKBOX" flip "$PLAN" 1 --mb "$MB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mirror skipped"* ]]
  assert_grep -q '^- ✅ widget builds$' "$PLAN"
}
