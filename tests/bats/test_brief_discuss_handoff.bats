#!/usr/bin/env bats
# brief_handoff: — svp-brief C3, the brief → discuss Phase 0 handoff (Task 3).
#
# Two halves: the normative clauses of commands/discuss.md through the S1-C9
# harness, and a deterministic check of the primitive those clauses cite —
# `scripts/mb-brief.sh context`. A clause that told Phase 0 to read a manifest
# the helper does not actually produce would otherwise pass on prose alone.
#
# Name convention (X-05, Eval red-anchor): every @test starts with `brief_handoff: `.

bats_require_minimum_version 1.5.0
load 'lib/assert'
load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  BRIEF="$REPO_ROOT/scripts/mb-brief.sh"
  DISCUSS="$REPO_ROOT/commands/discuss.md"
  BANK="$BATS_TEST_TMPDIR/bank"
  mkdir -p "$BANK"

  MB_DISCUSS_CLAUSES+=("discuss-phase0-brief-manifest|mb_section|Phase 0 — Research .before the first question.|scripts/mb-brief.sh. context[^;]*brief=present[^;]*first sources of the Research digest|mb-brief.sh. context|s/first sources of the Research digest/among the other sources of the Research digest/|REQ-006")
  MB_DISCUSS_CLAUSES+=("discuss-phase0-absent-parity|mb_section|Phase 0 — Research .before the first question.|brief=absent. Phase 0 proceeds unchanged|brief=absent|s/proceeds unchanged/proceeds with the brief step retried/|REQ-006")
}

@test "brief_handoff: phase0-reads-brief — REQ-006 manifest is the source" {
  run assert_clause "$DISCUSS" discuss-phase0-brief-manifest
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$DISCUSS" discuss-phase0-brief-manifest
  [ "$status" -eq 0 ]
}

@test "brief_handoff: legacy-parity — REQ-006 brief=absent changes nothing" {
  run assert_clause "$DISCUSS" discuss-phase0-absent-parity
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$DISCUSS" discuss-phase0-absent-parity
  [ "$status" -eq 0 ]
}

@test "brief_handoff: manifest-contract — the cited primitive really answers" {
  mkdir -p "$BANK/briefs/checkout-v2/inputs"
  printf 'the brief body\n' > "$BANK/briefs/checkout-v2/brief.md"
  printf 'a\n' > "$BANK/briefs/checkout-v2/inputs/b.md"
  printf 'b\n' > "$BANK/briefs/checkout-v2/inputs/a.md"

  run --separate-stderr "$BRIEF" context --mb "$BANK" --topic checkout-v2
  [ "$status" -eq 0 ]
  local expected
  expected="$(printf '%s\n%s\n%s\n%s' \
    'brief=present' \
    'brief_path=briefs/checkout-v2/brief.md' \
    'input_path=briefs/checkout-v2/inputs/a.md' \
    'input_path=briefs/checkout-v2/inputs/b.md')"
  [ "$output" = "$expected" ]
}

@test "brief_handoff: manifest-contract — brief_path precedes every input_path" {
  mkdir -p "$BANK/briefs/t/inputs"
  printf 'body\n' > "$BANK/briefs/t/brief.md"
  printf 'x\n' > "$BANK/briefs/t/inputs/z.md"
  run "$BRIEF" context --mb "$BANK" --topic t
  [ "$status" -eq 0 ]
  local first_input brief_line
  brief_line="$(printf '%s\n' "$output" | grep -n '^brief_path=' | cut -d: -f1)"
  first_input="$(printf '%s\n' "$output" | grep -n '^input_path=' | head -1 | cut -d: -f1)"
  [ "$brief_line" -lt "$first_input" ]
}

@test "brief_handoff: manifest-contract — no brief means Phase 0 gets brief=absent" {
  run --separate-stderr "$BRIEF" context --mb "$BANK" --topic never-briefed
  [ "$status" -eq 0 ]
  [ "$output" = "brief=absent" ]
  [ "$stderr" = "" ]
}
