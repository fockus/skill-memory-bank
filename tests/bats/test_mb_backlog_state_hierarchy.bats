#!/usr/bin/env bats
# Tests for `mb-backlog-state.sh list [--tree]` — S4 Task 7 (design.md C3, REQ-006).
# Line grammar: item=<I-NNN> state=<STATE> parent=<I-NNN|none> depth=<int> title=<JSON>
# Red-anchor: names start with `backlog_hierarchy: `.

bats_require_minimum_version 1.5.0

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  BS="$REPO_ROOT/scripts/mb-backlog-state.sh"
  TMPROOT="$(mktemp -d)"
  BANK="$TMPROOT/my bank/.memory-bank"
  mkdir -p "$BANK"
  cat > "$BANK/backlog.md" <<'EOF2'
# Backlog

## Ideas

### I-001 — root one [MED, NEW, 2026-04-01]

### I-002 — child of three [MED, NEW, 2026-04-02]

**Parent:** I-003

### I-003 — root two [MED, TRIAGED, 2026-04-03]

### I-004 — grandchild [MED, NEW, 2026-04-04]

**Parent:** I-002

### I-005 — child of one [MED, NEW, 2026-04-05]

**Parent:** I-001

### I-006 — café "q" тема [MED, NEW, 2026-04-06]

**Parent:** none

### I-010 — second child of three [MED, NEW, 2026-04-07]

**Parent:** I-003

## Out of scope

### I-050 — rejected [LOW, WONTFIX, 2026-03-01]

**Reason:** no

## ADR
EOF2
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

@test "backlog_hierarchy: list --tree prints parents before children with depth" {
  run --separate-stderr bash "$BS" list --tree --mb "$BANK"
  [ "$status" -eq 0 ]
  expected='item=I-001 state=NEW parent=none depth=0 title="root one"
item=I-005 state=NEW parent=I-001 depth=1 title="child of one"
item=I-003 state=TRIAGED parent=none depth=0 title="root two"
item=I-002 state=NEW parent=I-003 depth=1 title="child of three"
item=I-004 state=NEW parent=I-002 depth=2 title="grandchild"
item=I-010 state=NEW parent=I-003 depth=1 title="second child of three"
item=I-006 state=NEW parent=none depth=0 title="café \"q\" тема"'
  [ "$output" = "$expected" ]
}

@test "backlog_hierarchy: siblings sort by numeric id not lexicographically" {
  run --separate-stderr bash "$BS" list --tree --mb "$BANK"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -n 'I-002\|I-010' | head -2 | awk -F: '{print $1}' > "$BATS_TEST_TMPDIR/ord"
  [ "$(sed -n 1p "$BATS_TEST_TMPDIR/ord")" -lt "$(sed -n 2p "$BATS_TEST_TMPDIR/ord")" ]
}

@test "backlog_hierarchy: flat list keeps depth=0 and numeric id order" {
  run --separate-stderr bash "$BS" list --mb "$BANK"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n 1p | cut -d' ' -f1)" = "item=I-001" ]
  [ "$(printf '%s\n' "$output" | grep -c 'depth=0')" -eq 7 ]
  [ "$(printf '%s\n' "$output" | awk '{print $1}' | tr -d 'item=I-' | sort -n | tr '\n' ' ')" = "$(printf '%s\n' "$output" | awk '{print $1}' | tr -d 'item=I-' | tr '\n' ' ')" ]
}

@test "backlog_hierarchy: title with quotes and unicode is a JSON literal" {
  run --separate-stderr bash "$BS" list --mb "$BANK"
  [[ "$output" == *'title="café \"q\" тема"'* ]]
}

@test "backlog_hierarchy: out of scope entries are not printed" {
  run --separate-stderr bash "$BS" list --tree --mb "$BANK"
  refute_substring "$output" "I-050"
}

@test "backlog_hierarchy: missing parent fails with empty stdout and code=missing_parent" {
  printf '\n### I-020 — orphan [MED, NEW, 2026-04-20]\n\n**Parent:** I-777\n' >> "$BANK/backlog.md"
  run --separate-stderr bash "$BS" list --tree --mb "$BANK"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"code=missing_parent item=I-020 parent=I-777"* ]]
}

@test "backlog_hierarchy: parent cycle fails with the full path and no partial tree" {
  python3 - "$BANK/backlog.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("### I-001 — root one [MED, NEW, 2026-04-01]\n", "### I-001 — root one [MED, NEW, 2026-04-01]\n\n**Parent:** I-005\n", 1)
open(p, "w", encoding="utf-8").write(s)
PY
  run --separate-stderr bash "$BS" list --tree --mb "$BANK"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"code=parent_cycle path=I-001->I-005->I-001"* ]]
}

@test "backlog_hierarchy: annotate --parent makes the child appear nested" {
  run bash "$BS" annotate I-006 --brief "the view should render when data exists" --parent I-001 --mb "$BANK"
  [ "$status" -eq 0 ]
  run --separate-stderr bash "$BS" list --tree --mb "$BANK"
  [[ "$output" == *'item=I-006 state=NEW parent=I-001 depth=1'* ]]
}

@test "backlog_hierarchy: bank path with spaces works and list is read-only" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/snap"
  run --separate-stderr bash "$BS" list --tree --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/snap"
}
