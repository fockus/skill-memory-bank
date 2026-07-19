#!/usr/bin/env bats
# scripts/mb-backlog-state.sh — backlog.md ID-uniqueness gate (review finding 8).
#
# Split out of test_mb_backlog_state.bats to keep both files under the 400-line
# project gate.
#
# Machine: NEW → NEEDS-INFO ⇄ TRIAGED → READY → IN-PROGRESS → DONE | WONTFIX
# CLI:
#   transition <I-NNN> <STATE> [--reason TEXT] [--mb PATH]
#   annotate  <I-NNN> --brief <TEXT> [--parent <I-NNN|none>] [--mb PATH]
#   list [--mb PATH]                (flat only in Task 2; --tree → exit 2)
#
# Red-anchor: every test name starts with `backlog_state: `.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  BS="$REPO_ROOT/scripts/mb-backlog-state.sh"

  TMPROOT="$(mktemp -d)"
  BANK="$TMPROOT/.memory-bank"
  mkdir -p "$BANK"

  cat > "$BANK/backlog.md" <<'EOF'
# Backlog

## Ideas

### I-001 — alpha idea [MED, NEW, 2026-04-01]

### I-002 — needs info item [MED, NEEDS-INFO, 2026-04-02]

**Parent:** I-001

### I-003 — triaged item [HIGH, TRIAGED, 2026-04-03]

### I-004 — ready item [MED, READY, 2026-04-04]

**Brief:** the system should reject invalid input when the token is missing

### I-005 — running item [MED, IN-PROGRESS, 2026-04-05]

### I-006 — done item [LOW, DONE 2026-05-01, 2026-04-06]

### I-008 — extra item [MED, IN-PROGRESS owner=bob, 2026-04-08]

### I-009 — café "q" тема [MED, NEW, 2026-04-09]

### I-010 — path brief item [MED, TRIAGED, 2026-04-10]

**Brief:** should update scripts/mb-x.sh handler

### I-011 — linenum brief item [MED, TRIAGED, 2026-04-11]

**Brief:** must handle the retry at :42 when it fails

## Out of scope

### I-050 — rejected precedent [LOW, WONTFIX, 2026-03-01]

**Reason:** telemetry by default

## ADR
EOF
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

state_of() {  # $1 = I-NNN → the state TOKEN (first word of the 2nd bracket field)
  grep -E "^### $1 — " "$BANK/backlog.md" | sed -E 's/.*\[[^,]+, ([^,]+),.*/\1/' | awk '{print $1}'
}

# ═══════════════════════════════════════════════════════════════
# Duplicate IDs are ambiguous, never silently first-wins (finding 8)
# ═══════════════════════════════════════════════════════════════

dup_bank() {  # append a SECOND I-003 so the file carries two entries with one id
  cat >> "$BANK/backlog.md" <<'DUP'

### I-003 — duplicate of an existing id [LOW, NEW, 2026-04-20]
DUP
}

@test "backlog_state: transition on a duplicated id is refused (exit 2, nothing mutated)" {
  dup_bank
  before="$(cat "$BANK/backlog.md")"
  run --separate-stderr bash "$BS" transition I-003 READY --mb "$BANK"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"code=duplicate_id"* ]]
  [[ "$stderr" == *"I-003"* ]]
  [ "$before" = "$(cat "$BANK/backlog.md")" ]
}

@test "backlog_state: annotate on a duplicated id is refused (exit 2, nothing mutated)" {
  dup_bank
  before="$(cat "$BANK/backlog.md")"
  run --separate-stderr bash "$BS" annotate I-003 --brief "the system should retry when the call fails" --mb "$BANK"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"code=duplicate_id"* ]]
  [ "$before" = "$(cat "$BANK/backlog.md")" ]
}

@test "backlog_state: list is refused on a duplicated id rather than emitting both" {
  dup_bank
  run --separate-stderr bash "$BS" list --mb "$BANK"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"code=duplicate_id"* ]]
}

@test "backlog_state: a duplicate elsewhere still blocks an unrelated id (db is inconsistent)" {
  dup_bank
  before="$(cat "$BANK/backlog.md")"
  run --separate-stderr bash "$BS" transition I-001 NEEDS-INFO --mb "$BANK"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"code=duplicate_id"* ]]
  [ "$before" = "$(cat "$BANK/backlog.md")" ]
}

@test "backlog_state: a clean backlog with unique ids is unaffected by the duplicate gate" {
  run bash "$BS" transition I-001 NEEDS-INFO --mb "$BANK"
  [ "$status" -eq 0 ]
  grep -qF 'I-001 — alpha idea [MED, NEEDS-INFO, 2026-04-01]' "$BANK/backlog.md"
}
