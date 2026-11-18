#!/usr/bin/env bats
# Tests for scripts/mb-backlog-migrate.sh — S4 Task 3 (design.md C4).
# Runs ONLY on a throw-away copy of a legacy backlog, never the live bank.
# Red-anchor: names start with `backlog_migrate: `.

bats_require_minimum_version 1.5.0

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  MIG="$REPO_ROOT/scripts/mb-backlog-migrate.sh"
  IDEA="$REPO_ROOT/scripts/mb-idea.sh"
  TMPROOT="$(mktemp -d)"
  BANK="$TMPROOT/my bank/.memory-bank"
  mkdir -p "$BANK"
  cat > "$BANK/backlog.md" <<'EOF2'
# Backlog

## Ideas

### I-001 — plain new [MED, NEW, 2026-04-01]

**Problem:** keep me.

### I-002 — open one [HIGH, OPEN, 2026-04-02]

### I-003 — proposed one [LOW, PROPOSED, 2026-04-03]

### I-004 — triaged one [MED, TRIAGED, 2026-04-04]

### I-005 — planned one [MED, PLANNED, 2026-04-05]

**Plan:** [plans/x.md](plans/x.md)

### I-006 — done dated [MED, DONE 2026-05-01, 2026-04-06]

### I-007 — resolved hash [MED, RESOLVED 2026-05-02 — abc1234, 2026-04-07]

### I-008 — resolved bare [MED, RESOLVED, 2026-04-08]

### I-009 — declined one [LOW, DECLINED, 2026-04-09]

**Note:** not wanted.

### I-010 — deferred one [MED, DEFERRED, 2026-04-10]

### I-011 — [SPEC:svp-brief] brief-topic [MED, NEW, 2026-04-11]

### I-012 — obsolete one [MED, OBSOLETE, 2026-04-12]

### I-013 — declined two [LOW, DECLINED, 2026-04-13]

### I-014 — resolved hash no date [HIGH, RESOLVED 2026-06-14 — 306835a]

### I-015 — resolved dated only [MED, RESOLVED 2026-07-04]

### I-016 — resolved with note [MED, RESOLVED 2026-11-18 — superseded by x]

### I-017 — done with trailing text [HIGH, DONE 2026-07-15, 2026-06-23] — Wave 1, commit 49f9ad5, plan plans/done/x

### I-018 — no state token [HIGH, 2026-07-19]

### I-019 — no bracket at all

### I-020 — unknown token no date [LOW, OBSOLETE 2026-11-18 — removed upstream]

### I-021 — resolved with trailing text [LOW, RESOLVED 2026-05-05, 2026-05-01] — closed by hash abc

## Out of scope

### I-050 — old precedent [LOW, WONTFIX, 2026-03-01]

**Reason:** earlier

## ADR
EOF2
  cp "$BANK/backlog.md" "$TMPROOT/original.md"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

header_of() { grep -E "^### $1 — " "$BANK/backlog.md"; }

@test "backlog_migrate: default mode is dry-run and mutates nothing" {
  run --separate-stderr bash "$MIG" "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode=dry-run"* ]]
  [[ "$output" == *"actions_pending="* ]]
  cmp "$BANK/backlog.md" "$TMPROOT/original.md"
  refute_file "$BANK/.pre-migrate"
}

@test "backlog_migrate: OPEN PROPOSED and DEFERRED map to TRIAGED" {
  bash "$MIG" --apply "$BANK" >/dev/null
  [ "$(header_of I-002)" = '### I-002 — open one [HIGH, TRIAGED, 2026-04-02]' ]
  [ "$(header_of I-003)" = '### I-003 — proposed one [LOW, TRIAGED, 2026-04-03]' ]
  [ "$(header_of I-010)" = '### I-010 — deferred one [MED, TRIAGED, 2026-04-10]' ]
}

@test "backlog_migrate: NEW TRIAGED and dated DONE are untouched" {
  bash "$MIG" --apply "$BANK" >/dev/null
  [ "$(header_of I-001)" = '### I-001 — plain new [MED, NEW, 2026-04-01]' ]
  [ "$(header_of I-004)" = '### I-004 — triaged one [MED, TRIAGED, 2026-04-04]' ]
  [ "$(header_of I-006)" = '### I-006 — done dated [MED, DONE 2026-05-01, 2026-04-06]' ]
}

@test "backlog_migrate: PLANNED maps to IN-PROGRESS and keeps the plan link" {
  bash "$MIG" --apply "$BANK" >/dev/null
  [ "$(header_of I-005)" = '### I-005 — planned one [MED, IN-PROGRESS, 2026-04-05]' ]
  grep -qF '**Plan:** [plans/x.md](plans/x.md)' "$BANK/backlog.md"
}

@test "backlog_migrate: RESOLVED maps to DONE preserving date and hash byte-for-byte" {
  bash "$MIG" --apply "$BANK" >/dev/null
  [ "$(header_of I-007)" = '### I-007 — resolved hash [MED, DONE 2026-05-02 — abc1234, 2026-04-07]' ]
  [ "$(header_of I-008)" = '### I-008 — resolved bare [MED, DONE, 2026-04-08]' ]
}

@test "backlog_migrate: DECLINED becomes WONTFIX, moves to Out of scope, gets no Reason" {
  bash "$MIG" --apply "$BANK" >/dev/null
  idx_oos=$(grep -n '^## Out of scope' "$BANK/backlog.md" | cut -d: -f1)
  idx_9=$(grep -n '^### I-009 — ' "$BANK/backlog.md" | cut -d: -f1)
  idx_13=$(grep -n '^### I-013 — ' "$BANK/backlog.md" | cut -d: -f1)
  [ "$idx_9" -gt "$idx_oos" ]
  [ "$idx_13" -gt "$idx_9" ]
  [ "$(header_of I-009)" = '### I-009 — declined one [LOW, WONTFIX, 2026-04-09]' ]
  grep -qF '**Note:** not wanted.' "$BANK/backlog.md"
  refute_grep -q '^\*\*Reason:\*\* ' <(sed -n "/^### I-009 — /,/^### I-013/p" "$BANK/backlog.md")
  # ## ADR section still follows, untouched
  grep -q '^## ADR$' "$BANK/backlog.md"
}

@test "backlog_migrate: [SPEC:group] prefix becomes four typed meta lines" {
  bash "$MIG" --apply "$BANK" >/dev/null
  [ "$(header_of I-011)" = '### I-011 — brief-topic [MED, NEW, 2026-04-11]' ]
  sed -n '/^### I-011 — /,/^### I-012/p' "$BANK/backlog.md" | grep -qxF '**Type:** SPEC'
  sed -n '/^### I-011 — /,/^### I-012/p' "$BANK/backlog.md" | grep -qxF '**Group:** svp-brief'
  sed -n '/^### I-011 — /,/^### I-012/p' "$BANK/backlog.md" | grep -qxF '**Parent:** none'
  sed -n '/^### I-011 — /,/^### I-012/p' "$BANK/backlog.md" | grep -qxF '**Spec:** brief-topic'
}

@test "backlog_migrate: no historical entry receives Type IDEA (grandfather survives)" {
  bash "$MIG" --apply "$BANK" >/dev/null
  refute_grep -q 'Type:\*\* IDEA' "$BANK/backlog.md"
}

@test "backlog_migrate: unknown legacy token only warns" {
  run --separate-stderr bash "$MIG" --apply "$BANK"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"unknown_legacy_state=OBSOLETE"* ]]
  [ "$(header_of I-012)" = '### I-012 — obsolete one [MED, OBSOLETE, 2026-04-12]' ]
}

@test "backlog_migrate: --apply backs up the original under .pre-migrate" {
  bash "$MIG" --apply "$BANK" >/dev/null
  [ "$(find "$BANK/.pre-migrate" -name backlog.md | wc -l | tr -d ' ')" -eq 1 ]
  cmp "$(find "$BANK/.pre-migrate" -name backlog.md)" "$TMPROOT/original.md"
}

@test "backlog_migrate: second --apply is a byte-identical no-op with no new backup" {
  bash "$MIG" --apply "$BANK" >/dev/null
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/snap"
  sleep 1
  run --separate-stderr bash "$MIG" --apply "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"actions_pending=0"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/snap"
  [ "$(find "$BANK/.pre-migrate" -name backlog.md | wc -l | tr -d ' ')" -eq 1 ]
}

@test "backlog_migrate: migrated file stays parseable by the state machine" {
  bash "$MIG" --apply "$BANK" >/dev/null
  run --separate-stderr bash "$REPO_ROOT/scripts/mb-backlog-state.sh" list --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *'item=I-011 state=NEW'* ]]
}

@test "backlog_migrate: unknown option exits 2 and mutates nothing" {
  run --separate-stderr bash "$MIG" --bogus "$BANK"
  [ "$status" -eq 2 ]
  cmp "$BANK/backlog.md" "$TMPROOT/original.md"
}

@test "backlog_migrate: --apply racing mb-idea.sh loses no entry and stays valid" {
  for n in 1 2 3 4; do
    bash "$IDEA" "Racing idea number $n" MED "$BANK" >/dev/null 2>&1 &
  done
  bash "$MIG" --apply "$BANK" >/dev/null 2>&1 &
  wait
  [ "$(grep -c 'Racing idea number' "$BANK/backlog.md")" -eq 4 ]
  [ "$(header_of I-009 | grep -c WONTFIX)" -eq 1 ]
  run --separate-stderr bash "$REPO_ROOT/scripts/mb-backlog-state.sh" list --mb "$BANK"
  [ "$status" -eq 0 ]
}

@test "backlog_migrate: typed SPEC entry from mb-idea.sh is a migrator no-op" {
  bash "$IDEA" "[SPEC:grp] some-topic" MED "$BANK" >/dev/null
  bash "$MIG" --apply "$BANK" >/dev/null
  run --separate-stderr bash "$MIG" --dry-run "$BANK"
  [[ "$output" == *"actions_pending=0"* ]]
}

@test "backlog_migrate: RESOLVED headings without a created date or with trailing text become DONE" {
  bash "$MIG" --apply "$BANK" >/dev/null
  [ "$(header_of I-014)" = '### I-014 — resolved hash no date [HIGH, DONE 2026-06-14 — 306835a]' ]
  [ "$(header_of I-015)" = '### I-015 — resolved dated only [MED, DONE 2026-07-04]' ]
  [ "$(header_of I-016)" = '### I-016 — resolved with note [MED, DONE 2026-11-18 — superseded by x]' ]
  [ "$(header_of I-021)" = '### I-021 — resolved with trailing text [LOW, DONE 2026-05-05, 2026-05-01] — closed by hash abc' ]
}

@test "backlog_migrate: DONE heading with trailing text is left byte-identical" {
  bash "$MIG" --apply "$BANK" >/dev/null
  [ "$(header_of I-017)" = '### I-017 — done with trailing text [HIGH, DONE 2026-07-15, 2026-06-23] — Wave 1, commit 49f9ad5, plan plans/done/x' ]
}

@test "backlog_migrate: unknown token on a heading without a created date warns" {
  run --separate-stderr bash "$MIG" --dry-run "$BANK"
  [[ "$stderr" == *"unknown_legacy_state=OBSOLETE item=I-020"* ]]
  [[ "$stderr" == *"unknown_legacy_state=OBSOLETE item=I-012"* ]]
}

@test "backlog_migrate: headings without a state token or without a bracket are listed, never guessed" {
  run --separate-stderr bash "$MIG" --apply "$BANK"
  [[ "$stderr" == *"missing_state ids=I-018"* ]]
  [[ "$stderr" == *"unparsed_heading ids=I-019"* ]]
  [ "$(header_of I-018)" = '### I-018 — no state token [HIGH, 2026-07-19]' ]
  [ "$(header_of I-019)" = '### I-019 — no bracket at all' ]
}

@test "backlog_migrate: dry-run and apply count the same actions on the extended fixture and re-apply is a no-op" {
  run --separate-stderr bash "$MIG" --dry-run "$BANK"
  pending=$(printf '%s\n' "$output" | grep '^actions_pending=')
  run --separate-stderr bash "$MIG" --apply "$BANK"
  [[ "$output" == *"$pending"* ]]
  run --separate-stderr bash "$MIG" --apply "$BANK"
  [[ "$output" == *"actions_pending=0"* ]]
}
