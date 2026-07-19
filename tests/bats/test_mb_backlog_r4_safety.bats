#!/usr/bin/env bats
# scripts/mb-backlog-state.sh — R4 data-safety: what a SUCCESSFUL mutation is
# allowed to change, CRLF preservation, and the I-NNN CLI grammar.
#
# Split out of test_mb_backlog_state.bats for the 400-line project gate.
#
# Red-anchor: every test name starts with `backlog_state: `.

bats_require_minimum_version 1.5.0

load lib/assert

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

ends_with_newline() {
  run python3 -c 'import sys;print(open(sys.argv[1],newline="").read().endswith("\n"))' "$1"
  [ "$output" = "True" ]
}

# R4-013 (found by re-running the R3 mutations after the R4 assertion fix): the
# reject tests now prove "nothing changed", but NOTHING proved what a SUCCESSFUL
# mutation is allowed to change. Two mutations survived the whole suite because
# of it: a writer that strips the file's final newline, and a transition that
# truncates every entry after the target. Both only fire on the success path.

@test "backlog_state: a SUCCESSFUL transition rewrites the state token and NOTHING else" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run bash "$BS" transition I-001 NEEDS-INFO --mb "$BANK"
  [ "$status" -eq 0 ]
  # The expected file is the snapshot with ONLY that one token rewritten, so any
  # other byte the writer touches — a dropped trailing newline, a truncated
  # tail, a reflowed blank line — fails this comparison.
  sed 's/\[MED, NEW, 2026-04-01\]/[MED, NEEDS-INFO, 2026-04-01]/' \
    "$BATS_TEST_TMPDIR/before.snap" > "$BATS_TEST_TMPDIR/expected.md"
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/expected.md"
}

@test "backlog_state: a SUCCESSFUL transition keeps the file's final newline" {
  run bash "$BS" transition I-001 NEEDS-INFO --mb "$BANK"
  [ "$status" -eq 0 ]
  # `$(cat)` strips trailing newlines, so this has to be measured on the bytes.
  ends_with_newline "$BANK/backlog.md"
}

@test "backlog_state: a SUCCESSFUL annotate leaves every OTHER entry byte-identical" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run bash "$BS" annotate I-003 --brief "the parser must reject malformed input" --mb "$BANK"
  [ "$status" -eq 0 ]
  # Cut out the target entry's body from both sides; the remainder must match.
  awk '/^### I-003 /{s=1} /^### I-004 /{s=0} !s' "$BATS_TEST_TMPDIR/before.snap" > "$BATS_TEST_TMPDIR/rest_before.txt"
  awk '/^### I-003 /{s=1} /^### I-004 /{s=0} !s' "$BANK/backlog.md" > "$BATS_TEST_TMPDIR/rest_after.txt"
  assert_unchanged "$BATS_TEST_TMPDIR/rest_after.txt" "$BATS_TEST_TMPDIR/rest_before.txt"
  ends_with_newline "$BANK/backlog.md"
}


# ═══════════════════════════════════════════════════════════════
# R4-005 — a CRLF backlog keeps its CRLF
# ═══════════════════════════════════════════════════════════════

@test "backlog_state: a transition on a CRLF backlog rewrites the token and no line ending" {
  printf '# Backlog\r\n\r\n## Ideas\r\n\r\n### I-001 — alpha [MED, NEW, 2026-04-01]\r\n\r\n### I-002 — beta [MED, NEW, 2026-04-02]\r\n' > "$BANK/backlog.md"
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run bash "$BS" transition I-001 NEEDS-INFO --mb "$BANK"
  [ "$status" -eq 0 ]
  # Only the state token may differ; every CR must still be there. The old
  # universal-newline read rewrote all seven CRLFs into LF on a one-token edit.
  sed 's/\[MED, NEW, 2026-04-01\]/[MED, NEEDS-INFO, 2026-04-01]/' \
    "$BATS_TEST_TMPDIR/before.snap" > "$BATS_TEST_TMPDIR/expected.md"
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/expected.md"
  [ "$(grep -c $'\r' "$BANK/backlog.md")" -eq 7 ]
}

@test "backlog_state: annotate on a CRLF backlog writes CRLF metadata lines too" {
  printf '# Backlog\r\n\r\n## Ideas\r\n\r\n### I-003 — gamma [MED, TRIAGED, 2026-04-03]\r\n\r\n### I-004 — delta [MED, NEW, 2026-04-04]\r\n' > "$BANK/backlog.md"
  run bash "$BS" annotate I-003 --brief "the parser must reject malformed input" --mb "$BANK"
  [ "$status" -eq 0 ]
  # Not a single LF-only line may be introduced by the metadata writer.
  run awk '$0 !~ /\r$/ && length($0) > 0 {print "MIXED:" $0}' "$BANK/backlog.md"
  [ -z "$output" ]
}

# ═══════════════════════════════════════════════════════════════
# R4-006 — the CLI grammar is I-NNN, and a malformed id mutates nothing
# ═══════════════════════════════════════════════════════════════

@test "backlog_state: transition on an under-width id exits 2 and mutates nothing" {
  printf '# Backlog\n\n## Ideas\n\n### I-1 — bad width [MED, NEW, 2026-07-19]\n' > "$BANK/backlog.md"
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" transition I-1 NEEDS-INFO --mb "$BANK"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"invalid id"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
}

@test "backlog_state: annotate on an under-width id exits 2 and mutates nothing" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" annotate I-7 --brief "the parser must reject bad input" --mb "$BANK"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"invalid id"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
}

@test "backlog_state: a malformed --parent is refused before any write" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" annotate I-001 --brief "the parser must reject bad input" --parent I-2 --mb "$BANK"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"invalid id"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
}

@test "backlog_state: --parent none is still accepted (documented clear-token)" {
  run bash "$BS" annotate I-002 --brief "the parser must reject bad input" --parent none --mb "$BANK"
  [ "$status" -eq 0 ]
  run awk '/^### I-002 /{s=1;next} /^### /{s=0} s' "$BANK/backlog.md"
  refute_substring "$output" "**Parent:**"
}

# ═══════════════════════════════════════════════════════════════
# R4-002 — REQ-007 catches prose line numbers and extensionless paths
# ═══════════════════════════════════════════════════════════════

@test "backlog_state: a brief with a prose line number is refused at annotate AND at READY" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" annotate I-003 --brief "the parser must retry at line 42 when input fails" --mb "$BANK"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"contains line number"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  # and the READY gate refuses the same text when it is already in the file
  printf '# Backlog\n\n## Ideas\n\n### I-003 — gamma [HIGH, TRIAGED, 2026-04-03]\n\n**Brief:** the parser must retry at line 42 when input fails\n' > "$BANK/backlog.md"
  run --separate-stderr bash "$BS" transition I-003 READY --mb "$BANK"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"contains line number"* ]]
}

@test "backlog_state: a brief with an extensionless relative path is refused" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" annotate I-003 --brief "the agent must edit custom/runner" --mb "$BANK"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"contains file path"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
}

@test "backlog_state: a conceptual slash pair is still accepted end-to-end" {
  run bash "$BS" annotate I-003 --brief "the serializer must preserve input/output semantics" --mb "$BANK"
  [ "$status" -eq 0 ]
  run bash "$BS" transition I-003 READY --mb "$BANK"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Option-value validation — a dangling flag is a usage error (exit 2)
# (moved here from test_mb_backlog_state.bats for the 400-line gate; it is
#  CLI-grammar territory, same as the I-NNN cases above.)
# ═══════════════════════════════════════════════════════════════
# A flag given with no value must fail the usage contract loudly (exit 2 +
# stderr diagnostic), not blow up on a `shift 2` out-of-range under set -e
# (which leaked an empty exit 1).

@test "backlog_state: list --mb without a value is a usage error (exit 2)" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" list --mb
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--mb"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
}

@test "backlog_state: annotate --brief without a value is a usage error (exit 2)" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" annotate I-001 --brief
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--brief"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
}

@test "backlog_state: annotate --parent without a value is a usage error (exit 2)" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" annotate I-001 --brief "must validate input" --parent
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--parent"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
}

@test "backlog_state: transition --reason without a value is a usage error (exit 2)" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" transition I-005 WONTFIX --reason
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--reason"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
}

@test "backlog_state: transition --mb without a value is a usage error (exit 2)" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" transition I-001 NEEDS-INFO --mb
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--mb"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
}

# A following option-token in the VALUE position is NOT a value — it must be a
# usage error (exit 2, before bank resolve / lock), never silently consumed. The
# `--mb "$BANK"` prefix keeps the temp bank targeted even under the buggy path.

@test "backlog_state: transition --reason swallowing a following flag mutates nothing (exit 2)" {
  # The reported defect: `--reason --mb` accepted `--mb` as the reason and
  # transitioned I-003, mutating the backlog. Must be a usage error instead.
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" transition I-003 NEEDS-INFO --mb "$BANK" --reason --brief
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"requires a value"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  [ "$(state_of I-003)" = "TRIAGED" ]      # I-003 unchanged
}

@test "backlog_state: annotate --brief swallowing a following flag is a usage error (exit 2)" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" annotate I-001 --mb "$BANK" --brief --parent
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"requires a value"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
}

@test "backlog_state: annotate --parent swallowing a following flag is a usage error (exit 2)" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" annotate I-001 --mb "$BANK" --brief "must validate input" --parent --reason
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"requires a value"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
}

@test "backlog_state: transition --mb swallowing a following flag is a usage error (exit 2)" {
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" transition I-001 NEEDS-INFO --mb --reason
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"requires a value"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
}
