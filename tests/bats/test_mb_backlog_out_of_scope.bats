#!/usr/bin/env bats
# Tests for WONTFIX → Out of scope, the similarity hook and the typed SPEC writer —
# S4 Task 8 (design.md C3, C4). Red-anchor: names start with `backlog_out_of_scope: `.

bats_require_minimum_version 1.5.0

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  BS="$REPO_ROOT/scripts/mb-backlog-state.sh"
  IDEA="$REPO_ROOT/scripts/mb-idea.sh"
  MIG="$REPO_ROOT/scripts/mb-backlog-migrate.sh"
  TMPROOT="$(mktemp -d)"
  BANK="$TMPROOT/my bank/.memory-bank"
  mkdir -p "$BANK"
  cat > "$BANK/backlog.md" <<'EOF2'
# Backlog

## Ideas

### I-001 — running work [MED, IN-PROGRESS, 2026-04-01]

**Problem:** keep this text.

### I-002 — other idea [MED, NEW, 2026-04-02]

## Out of scope

### I-030 — telemetry dashboard collection [LOW, WONTFIX, 2026-03-01]

**Reason:** not now

### I-020 — telemetry dashboard collection service [LOW, WONTFIX, 2026-03-02]

**Reason:** not now

### I-040 — a b c [LOW, WONTFIX, 2026-03-03]

**Reason:** tiny

## ADR
EOF2
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

@test "backlog_out_of_scope: WONTFIX without --reason exits 1 and changes nothing" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/snap"
  run --separate-stderr bash "$BS" transition I-001 WONTFIX --mb "$BANK"
  [ "$status" -eq 1 ]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/snap"
}

@test "backlog_out_of_scope: WONTFIX moves the block into Out of scope with the Reason" {
  run --separate-stderr bash "$BS" transition I-001 WONTFIX --reason "duplicate of I-002" --mb "$BANK"
  [ "$status" -eq 0 ]
  ideas=$(sed -n '/^## Ideas/,/^## Out of scope/p' "$BANK/backlog.md")
  refute_substring "$ideas" "I-001"
  oos=$(sed -n '/^## Out of scope/,/^## ADR/p' "$BANK/backlog.md")
  [[ "$oos" == *"### I-001 — running work [MED, WONTFIX, 2026-04-01]"* ]]
  [[ "$oos" == *"**Problem:** keep this text."* ]]
  [[ "$oos" == *"**Reason:** duplicate of I-002"* ]]
  [ "$(grep -c '^### I-001 — ' "$BANK/backlog.md")" -eq 1 ]
  grep -q '^## ADR$' "$BANK/backlog.md"
  grep -q '^### I-002 — other idea' "$BANK/backlog.md"
}

@test "backlog_out_of_scope: a moved entry no longer appears in list" {
  bash "$BS" transition I-001 WONTFIX --reason "no longer needed" --mb "$BANK"
  run --separate-stderr bash "$BS" list --mb "$BANK"
  refute_substring "$output" "I-001"
}

@test "backlog_out_of_scope: similar out-of-scope title blocks creation with stderr and exit 1" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/snap"
  run --separate-stderr bash "$IDEA" "Telemetry dashboard collection" MED "$BANK"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"similar_out_of_scope=I-020 score=1.00"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/snap"
}

@test "backlog_out_of_scope: several matches report the smallest numeric id" {
  run --separate-stderr bash "$IDEA" "dashboard collection telemetry" MED "$BANK"
  [[ "$stderr" == *"similar_out_of_scope=I-020 "* ]]
}

@test "backlog_out_of_scope: --force creates despite similarity" {
  run --separate-stderr bash "$IDEA" --force "Telemetry dashboard collection" MED "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "I-041" ]
}

@test "backlog_out_of_scope: empty token sets score 0 and do not block" {
  run --separate-stderr bash "$IDEA" "a b" MED "$BANK"
  [ "$status" -eq 0 ]
}

@test "backlog_out_of_scope: --force does not bypass title idempotency" {
  run --separate-stderr bash "$IDEA" "other idea" MED "$BANK"
  [ "$output" = "I-002" ]
  run --separate-stderr bash "$IDEA" --force "other idea" MED "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "I-002" ]
  [ "$(grep -c 'other idea' "$BANK/backlog.md")" -eq 1 ]
}

@test "backlog_out_of_scope: dissimilar title is created as a typed IDEA" {
  run --separate-stderr bash "$IDEA" "Brand new feature proposal" HIGH "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "I-041" ]
  sed -n '/^### I-041 — /,/^## /p' "$BANK/backlog.md" | grep -qxF '**Type:** IDEA'
}

@test "backlog_out_of_scope: [SPEC:g] topic writes a typed record at once with plain I-NNN stdout" {
  run --separate-stderr bash "$IDEA" "[SPEC:svp-x] telemetry-dashboard-collection" MED "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "I-041" ]
  grep -qE '^### I-041 — telemetry-dashboard-collection \[MED, NEW, [0-9-]{10}\]$' "$BANK/backlog.md"
  block=$(sed -n '/^### I-041 — /,/^## /p' "$BANK/backlog.md")
  [[ "$block" == *$'**Type:** SPEC\n**Group:** svp-x\n**Parent:** none\n**Spec:** telemetry-dashboard-collection'* ]]
}

@test "backlog_out_of_scope: SPEC writer is a migrator no-op" {
  bash "$IDEA" "[SPEC:svp-x] some-topic" MED "$BANK" >/dev/null
  run --separate-stderr bash "$MIG" --dry-run "$BANK"
  [[ "$output" == *"actions_pending=0"* ]]
}

@test "backlog_out_of_scope: malformed SPEC titles exit 2 without allocation or mutation" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/snap"
  for t in '[SPEC:]' '[SPEC:g]' '[SPEC:] topic' '[SPEC:g] a b' '[SPEC:G] topic' '[SPEC:g topic' '[SPEC:g] Topic'; do
    run --separate-stderr bash "$IDEA" "$t" MED "$BANK"
    [ "$status" -eq 2 ]
    [ -z "$output" ]
  done
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/snap"
}

@test "backlog_out_of_scope: similarity never blocks a SPEC registration" {
  run --separate-stderr bash "$IDEA" "[SPEC:svp-x] telemetry-dashboard-collection" MED "$BANK"
  [ "$status" -eq 0 ]
  refute_substring "$stderr" "similar_out_of_scope"
}
