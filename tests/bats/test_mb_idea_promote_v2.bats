#!/usr/bin/env bats
# Tests for scripts/mb-idea-promote.sh on the C3 machine — S4 Task 9 (design.md C7).
# Promote requires READY, applies READY -> IN-PROGRESS through the shared transition
# primitive and never writes the legacy PLANNED token.
# Red-anchor: names start with `idea_promote: `.

bats_require_minimum_version 1.5.0

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PROMOTE="$REPO_ROOT/scripts/mb-idea-promote.sh"
  TMPROOT="$(mktemp -d)"
  BANK="$TMPROOT/my bank/.memory-bank"
  mkdir -p "$BANK/plans/done"

  cat > "$BANK/backlog.md" <<'EOF2'
# Backlog

## Ideas

### I-001 — refactor logging layer [HIGH, READY, 2026-04-01]

**Brief:** the logger should emit structured records when a request is handled

### I-002 — fresh idea [MED, NEW, 2026-04-02]

### I-003 — info idea [MED, NEEDS-INFO, 2026-04-03]

### I-004 — triaged idea [MED, TRIAGED, 2026-04-04]

### I-005 — running idea [MED, IN-PROGRESS, 2026-04-05]

### I-006 — done idea [MED, DONE 2026-05-01, 2026-04-06]

### I-007 — legacy planned [MED, PLANNED, 2026-04-07]

### I-008 — legacy deferred [MED, DEFERRED, 2026-04-08]

### I-009 — weird state [MED, BOGUS, 2026-04-09]

### I-010 — second ready idea [MED, READY, 2026-04-10]

**Brief:** the exporter should retry when the upstream is unavailable

## Out of scope

### I-050 — rejected [LOW, WONTFIX, 2026-03-01]

**Reason:** no

## ADR
EOF2
  printf '# Checklist\n' > "$BANK/checklist.md"
  printf '# Plan\n\n## Active plans\n\n<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n' > "$BANK/roadmap.md"
  printf '# Status\n\n## Active plans\n\n<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n\n## Recently done (last 10)\n\n<!-- mb-recent-done -->\n<!-- /mb-recent-done -->\n' > "$BANK/status.md"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

plans_count() { find "$BANK/plans" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' '; }

@test "idea_promote: READY with valid brief creates the plan and moves to IN-PROGRESS" {
  run --separate-stderr bash "$PROMOTE" I-001 refactor "$BANK"
  [ "$status" -eq 0 ]
  [ "$(plans_count)" -eq 1 ]
  grep -qE '^### I-001 — refactor logging layer \[HIGH, IN-PROGRESS, 2026-04-01\]$' "$BANK/backlog.md"
  refute_grep -q 'I-001 — .*PLANNED' "$BANK/backlog.md"
  grep -qE '^\*\*Plan:\*\* \[plans/.*refactor.*logging.*\.md\]\(plans/' "$BANK/backlog.md"
}

@test "idea_promote: promoted plan appears in the active-plans block" {
  bash "$PROMOTE" I-001 refactor "$BANK"
  awk '/<!-- mb-active-plans -->/{f=1;next} /<!-- \/mb-active-plans -->/{f=0} f' "$BANK/roadmap.md" | grep -q 'refactor-logging-layer'
}

@test "idea_promote: NEW NEEDS-INFO TRIAGED are refused with exit 2 remediation and no side effects" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/snap"
  for id in I-002 I-003 I-004; do
    run --separate-stderr bash "$PROMOTE" "$id" feature "$BANK"
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"READY"* ]]
    [[ "$stderr" == *"mb-backlog-state.sh"* ]]
  done
  [ "$(plans_count)" -eq 0 ]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/snap"
}

@test "idea_promote: legacy PLANNED and DEFERRED tokens exit 2 pointing at the migrator" {
  for id in I-007 I-008; do
    run --separate-stderr bash "$PROMOTE" "$id" feature "$BANK"
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"mb-backlog-migrate.sh"* ]]
  done
  [ "$(plans_count)" -eq 0 ]
}

@test "idea_promote: IN-PROGRESS without a plan link and DONE exit 2" {
  run --separate-stderr bash "$PROMOTE" I-005 feature "$BANK"
  [ "$status" -eq 2 ]
  run --separate-stderr bash "$PROMOTE" I-006 feature "$BANK"
  [ "$status" -eq 2 ]
  [ "$(plans_count)" -eq 0 ]
}

@test "idea_promote: unknown status exits 1, unknown id exits 1, invalid type exits 3" {
  run --separate-stderr bash "$PROMOTE" I-009 feature "$BANK"
  [ "$status" -eq 1 ]
  run --separate-stderr bash "$PROMOTE" I-099 feature "$BANK"
  [ "$status" -eq 1 ]
  run --separate-stderr bash "$PROMOTE" I-001 bogus "$BANK"
  [ "$status" -eq 3 ]
  [ "$(plans_count)" -eq 0 ]
}

@test "idea_promote: no promote path ever writes the PLANNED token" {
  before=$(grep -c 'PLANNED' "$BANK/backlog.md")
  bash "$PROMOTE" I-001 refactor "$BANK"
  bash "$PROMOTE" I-002 feature "$BANK" 2>/dev/null || true
  bash "$PROMOTE" I-007 feature "$BANK" 2>/dev/null || true
  [ "$(grep -c 'PLANNED' "$BANK/backlog.md")" -eq "$before" ]
}

@test "idea_promote: partial failure after plan creation reports code=promote_partial backlog_updated=false" {
  MB_PROMOTE_FAULT=after_plan run --separate-stderr bash "$PROMOTE" I-001 refactor "$BANK"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"code=promote_partial plan="*"backlog_updated=false"* ]]
  [ "$(plans_count)" -eq 1 ]
  grep -qE '^### I-001 — .*\[HIGH, READY,' "$BANK/backlog.md"
}

@test "idea_promote: retry after after_plan failure reuses the plan and links it exactly once" {
  MB_PROMOTE_FAULT=after_plan bash "$PROMOTE" I-001 refactor "$BANK" 2>/dev/null || true
  run --separate-stderr bash "$PROMOTE" I-001 refactor "$BANK"
  [ "$status" -eq 0 ]
  [ "$(plans_count)" -eq 1 ]
  [ "$(grep -c '^\*\*Plan:\*\*' "$BANK/backlog.md")" -eq 1 ]
  grep -qE '^### I-001 — .*\[HIGH, IN-PROGRESS,' "$BANK/backlog.md"
}

@test "idea_promote: failure after the backlog rename reports backlog_updated=true and a retry heals sync" {
  MB_PROMOTE_FAULT=after_rename run --separate-stderr bash "$PROMOTE" I-001 refactor "$BANK"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"code=promote_partial plan="*"backlog_updated=true"* ]]
  grep -qE '^### I-001 — .*\[HIGH, IN-PROGRESS,' "$BANK/backlog.md"
  run --separate-stderr bash "$PROMOTE" I-001 refactor "$BANK"
  [ "$status" -eq 0 ]
  [ "$(plans_count)" -eq 1 ]
  [ "$(grep -c '^\*\*Plan:\*\*' "$BANK/backlog.md")" -eq 1 ]
  awk '/<!-- mb-active-plans -->/{f=1;next} /<!-- \/mb-active-plans -->/{f=0} f' "$BANK/roadmap.md" | grep -q 'refactor-logging-layer'
}

@test "idea_promote: a fully promoted idea re-promoted is refused with exit 2" {
  bash "$PROMOTE" I-001 refactor "$BANK"
  run --separate-stderr bash "$PROMOTE" I-001 refactor "$BANK"
  [ "$status" -eq 2 ]
  [ "$(plans_count)" -eq 1 ]
}

@test "idea_promote: promote holds the backlog lock — a live foreign holder times out with exit 1 and no plan" {
  mkdir -p "$BANK/.locks/backlog.lock/owner.$$-1"
  MB_BACKLOG_LOCK_TIMEOUT=1 run --separate-stderr bash "$PROMOTE" I-001 refactor "$BANK"
  [ "$status" -eq 1 ]
  [ "$(plans_count)" -eq 0 ]
}
