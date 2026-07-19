#!/usr/bin/env bats
# Tests for scripts/mb-backlog-state.sh — S4 Task 2 (design.md C3).
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
# Valid transitions
# ═══════════════════════════════════════════════════════════════

@test "backlog_state: NEW -> NEEDS-INFO succeeds with machine stdout" {
  run bash "$BS" transition I-001 NEEDS-INFO --mb "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "item=I-001 old_state=NEW new_state=NEEDS-INFO" ]
  grep -qE '### I-001 — alpha idea \[MED, NEEDS-INFO, 2026-04-01\]' "$BANK/backlog.md"
}

@test "backlog_state: NEEDS-INFO -> TRIAGED succeeds" {
  run bash "$BS" transition I-002 TRIAGED --mb "$BANK"
  [ "$status" -eq 0 ]
  [ "$(state_of I-002)" = "TRIAGED" ]
}

@test "backlog_state: TRIAGED -> NEEDS-INFO succeeds (back edge)" {
  run bash "$BS" transition I-003 NEEDS-INFO --mb "$BANK"
  [ "$status" -eq 0 ]
  [ "$(state_of I-003)" = "NEEDS-INFO" ]
}

@test "backlog_state: READY -> IN-PROGRESS succeeds" {
  run bash "$BS" transition I-004 IN-PROGRESS --mb "$BANK"
  [ "$status" -eq 0 ]
  [ "$(state_of I-004)" = "IN-PROGRESS" ]
}

@test "backlog_state: IN-PROGRESS -> DONE succeeds and preserves extra detail" {
  run bash "$BS" transition I-008 DONE --mb "$BANK"
  [ "$status" -eq 0 ]
  # extra `owner=bob` after the state token survives byte-for-byte
  grep -qE '### I-008 — extra item \[MED, DONE owner=bob, 2026-04-08\]' "$BANK/backlog.md"
}

@test "backlog_state: IN-PROGRESS -> WONTFIX requires a reason" {
  run bash "$BS" transition I-005 WONTFIX --mb "$BANK"
  [ "$status" -eq 1 ]
  [ "$(state_of I-005)" = "IN-PROGRESS" ]   # unchanged
  run bash "$BS" transition I-005 WONTFIX --reason "duplicate of I-004" --mb "$BANK"
  [ "$status" -eq 0 ]
  [ "$(state_of I-005)" = "WONTFIX" ]
}

# ═══════════════════════════════════════════════════════════════
# Invalid transitions
# ═══════════════════════════════════════════════════════════════

@test "backlog_state: DONE -> NEW is rejected (terminal), exit 1 lists allowed" {
  run --separate-stderr bash "$BS" transition I-006 NEW --mb "$BANK"
  [ "$status" -eq 1 ]
  [ -z "$output" ]                      # diagnostics go to stderr, stdout empty
  [[ "$stderr" == *"I-006"* || "$stderr" == *"DONE"* ]]
  [ "$(state_of I-006)" = "DONE" ]      # unchanged
}

@test "backlog_state: NEW -> READY is rejected (not an edge)" {
  run bash "$BS" transition I-001 READY --mb "$BANK"
  [ "$status" -eq 1 ]
  [ "$(state_of I-001)" = "NEW" ]
}

@test "backlog_state: WONTFIX -> TRIAGED is rejected (terminal)" {
  run bash "$BS" transition I-050 TRIAGED --mb "$BANK"
  [ "$status" -eq 1 ]
}

@test "backlog_state: unknown id exits 2" {
  run bash "$BS" transition I-777 NEW --mb "$BANK"
  [ "$status" -eq 2 ]
}

@test "backlog_state: bad target state token exits 2" {
  run bash "$BS" transition I-001 BOGUS --mb "$BANK"
  [ "$status" -eq 2 ]
  [ "$(state_of I-001)" = "NEW" ]
}

# ═══════════════════════════════════════════════════════════════
# READY gate (REQ-007, blocking)
# ═══════════════════════════════════════════════════════════════

@test "backlog_state: TRIAGED -> READY without a brief is refused (missing brief)" {
  run --separate-stderr bash "$BS" transition I-003 READY --mb "$BANK"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"missing brief"* ]]
  [ "$(state_of I-003)" = "TRIAGED" ]
}

@test "backlog_state: TRIAGED -> READY refused when brief carries a file path" {
  # I-010 already carries a path-bearing brief — the READY-time gate must catch it.
  run --separate-stderr bash "$BS" transition I-010 READY --mb "$BANK"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"contains file path"* ]]
  [ "$(state_of I-010)" = "TRIAGED" ]
}

@test "backlog_state: TRIAGED -> READY refused when brief carries a line number" {
  run --separate-stderr bash "$BS" transition I-011 READY --mb "$BANK"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"contains line number"* ]]
  [ "$(state_of I-011)" = "TRIAGED" ]
}

@test "backlog_state: annotate then TRIAGED -> READY succeeds (reachability)" {
  run bash "$BS" annotate I-003 --brief "the parser must reject malformed input" --mb "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "item=I-003 annotated" ]
  run bash "$BS" transition I-003 READY --mb "$BANK"
  [ "$status" -eq 0 ]
  [ "$(state_of I-003)" = "READY" ]
}

# ═══════════════════════════════════════════════════════════════
# annotate — Brief / Parent writer
# ═══════════════════════════════════════════════════════════════

@test "backlog_state: annotate adds then replaces the Brief block" {
  bash "$BS" annotate I-001 --brief "the api should reject empty payloads" --mb "$BANK"
  grep -qF "**Brief:** the api should reject empty payloads" "$BANK/backlog.md"
  bash "$BS" annotate I-001 --brief "the api must reject oversized payloads" --mb "$BANK"
  grep -qF "**Brief:** the api must reject oversized payloads" "$BANK/backlog.md"
  # exactly one Brief line for I-001
  count=$(awk '/^### I-001 /{f=1;next} /^### /{f=0} f && /^\*\*Brief:\*\*/' "$BANK/backlog.md" | grep -c .)
  [ "$count" -eq 1 ]
}

@test "backlog_state: annotate --parent sets and --parent none clears" {
  bash "$BS" annotate I-001 --brief "must validate input" --parent I-003 --mb "$BANK"
  awk '/^### I-001 /{f=1;next} /^### /{f=0} f' "$BANK/backlog.md" | grep -qF "**Parent:** I-003"
  bash "$BS" annotate I-001 --brief "must validate input" --parent none --mb "$BANK"
  ! (awk '/^### I-001 /{f=1;next} /^### /{f=0} f' "$BANK/backlog.md" | grep -qF "**Parent:**")
}

@test "backlog_state: annotate --parent on a nonexistent id exits 1" {
  run bash "$BS" annotate I-001 --brief "must validate input" --parent I-777 --mb "$BANK"
  [ "$status" -eq 1 ]
}

@test "backlog_state: annotate with a non-behavioral brief exits 1, body untouched" {
  before="$(md5_of I-001)"
  run bash "$BS" annotate I-001 --brief "just a note about stuff" --mb "$BANK"
  [ "$status" -eq 1 ]
  [ "$(md5_of I-001)" = "$before" ]
}

@test "backlog_state: annotate anti-cycle refuses with code=parent_cycle" {
  # I-002 already has **Parent:** I-001; making I-001's parent I-002 = cycle.
  b1="$(md5_of I-001)"; b2="$(md5_of I-002)"
  run --separate-stderr bash "$BS" annotate I-001 --brief "must do a thing" --parent I-002 --mb "$BANK"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"parent_cycle"* ]]
  [ -z "$output" ]
  [ "$(md5_of I-001)" = "$b1" ]
  [ "$(md5_of I-002)" = "$b2" ]
}

# helper: md5 of an I-NNN block (header + body up to next ###/##)
md5_of() {
  awk -v id="$1" '
    $0 ~ "^### " id " " {f=1; print; next}
    /^### /{f=0}
    /^## /{f=0}
    f {print}
  ' "$BANK/backlog.md" | md5 2>/dev/null || \
  awk -v id="$1" '
    $0 ~ "^### " id " " {f=1; print; next}
    /^### /{f=0}
    /^## /{f=0}
    f {print}
  ' "$BANK/backlog.md" | md5sum
}

# ═══════════════════════════════════════════════════════════════
# list (flat) + unknown option
# ═══════════════════════════════════════════════════════════════

@test "backlog_state: list is flat depth=0 ordered by numeric id" {
  run bash "$BS" list --mb "$BANK"
  [ "$status" -eq 0 ]
  # every printed line is depth=0
  ! [[ "$output" == *"depth=1"* ]]
  [[ "$output" == *"item=I-001 state=NEW parent=I-003 depth=0"* ]] || \
    [[ "$output" == *"item=I-001 state=NEW parent=none depth=0"* ]]
  # ## Out of scope entries are NOT listed
  ! [[ "$output" == *"I-050"* ]]
  # numeric order: I-001 line precedes I-009 line
  first=$(printf '%s\n' "$output" | grep -n 'item=I-001 ' | head -1 | cut -d: -f1)
  last=$(printf '%s\n' "$output" | grep -n 'item=I-009 ' | head -1 | cut -d: -f1)
  [ "$first" -lt "$last" ]
}

@test "backlog_state: list encodes titles as compact JSON (quotes+unicode)" {
  run bash "$BS" list --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *'title="café \"q\" тема"'* ]]
}

@test "backlog_state: unknown option --tree exits 2 without mutating the file" {
  before="$(cat "$BANK/backlog.md")"
  run bash "$BS" list --tree --mb "$BANK"
  [ "$status" -eq 2 ]
  [ "$before" = "$(cat "$BANK/backlog.md")" ]
}

# ═══════════════════════════════════════════════════════════════
# Option-value validation — a dangling flag is a usage error (exit 2)
# ═══════════════════════════════════════════════════════════════
# A flag given with no value must fail the usage contract loudly (exit 2 +
# stderr diagnostic), not blow up on a `shift 2` out-of-range under set -e
# (which leaked an empty exit 1).

@test "backlog_state: list --mb without a value is a usage error (exit 2)" {
  before="$(cat "$BANK/backlog.md")"
  run --separate-stderr bash "$BS" list --mb
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--mb"* ]]
  [ "$before" = "$(cat "$BANK/backlog.md")" ]
}

@test "backlog_state: annotate --brief without a value is a usage error (exit 2)" {
  before="$(cat "$BANK/backlog.md")"
  run --separate-stderr bash "$BS" annotate I-001 --brief
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--brief"* ]]
  [ "$before" = "$(cat "$BANK/backlog.md")" ]
}

@test "backlog_state: annotate --parent without a value is a usage error (exit 2)" {
  before="$(cat "$BANK/backlog.md")"
  run --separate-stderr bash "$BS" annotate I-001 --brief "must validate input" --parent
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--parent"* ]]
  [ "$before" = "$(cat "$BANK/backlog.md")" ]
}

@test "backlog_state: transition --reason without a value is a usage error (exit 2)" {
  before="$(cat "$BANK/backlog.md")"
  run --separate-stderr bash "$BS" transition I-005 WONTFIX --reason
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--reason"* ]]
  [ "$before" = "$(cat "$BANK/backlog.md")" ]
}

@test "backlog_state: transition --mb without a value is a usage error (exit 2)" {
  before="$(cat "$BANK/backlog.md")"
  run --separate-stderr bash "$BS" transition I-001 NEEDS-INFO --mb
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--mb"* ]]
  [ "$before" = "$(cat "$BANK/backlog.md")" ]
}

# A following option-token in the VALUE position is NOT a value — it must be a
# usage error (exit 2, before bank resolve / lock), never silently consumed. The
# `--mb "$BANK"` prefix keeps the temp bank targeted even under the buggy path.

@test "backlog_state: transition --reason swallowing a following flag mutates nothing (exit 2)" {
  # The reported defect: `--reason --mb` accepted `--mb` as the reason and
  # transitioned I-003, mutating the backlog. Must be a usage error instead.
  before="$(cat "$BANK/backlog.md")"
  run --separate-stderr bash "$BS" transition I-003 NEEDS-INFO --mb "$BANK" --reason --brief
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"requires a value"* ]]
  [ "$before" = "$(cat "$BANK/backlog.md")" ]
  [ "$(state_of I-003)" = "TRIAGED" ]      # I-003 unchanged
}

@test "backlog_state: annotate --brief swallowing a following flag is a usage error (exit 2)" {
  before="$(cat "$BANK/backlog.md")"
  run --separate-stderr bash "$BS" annotate I-001 --mb "$BANK" --brief --parent
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"requires a value"* ]]
  [ "$before" = "$(cat "$BANK/backlog.md")" ]
}

@test "backlog_state: annotate --parent swallowing a following flag is a usage error (exit 2)" {
  before="$(cat "$BANK/backlog.md")"
  run --separate-stderr bash "$BS" annotate I-001 --mb "$BANK" --brief "must validate input" --parent --reason
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"requires a value"* ]]
  [ "$before" = "$(cat "$BANK/backlog.md")" ]
}

@test "backlog_state: transition --mb swallowing a following flag is a usage error (exit 2)" {
  before="$(cat "$BANK/backlog.md")"
  run --separate-stderr bash "$BS" transition I-001 NEEDS-INFO --mb --reason
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"requires a value"* ]]
  [ "$before" = "$(cat "$BANK/backlog.md")" ]
}

# ═══════════════════════════════════════════════════════════════
# Portability
# ═══════════════════════════════════════════════════════════════

@test "backlog_state: works when the bank path contains spaces" {
  SPACED="$TMPROOT/with space/.memory-bank"
  mkdir -p "$SPACED"
  cp "$BANK/backlog.md" "$SPACED/backlog.md"
  run bash "$BS" transition I-001 NEEDS-INFO --mb "$SPACED"
  [ "$status" -eq 0 ]
}
