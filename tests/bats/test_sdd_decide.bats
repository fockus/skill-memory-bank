#!/usr/bin/env bats
# sdd_decide: — the C7 human/orchestrator decision writer
# (`scripts/mb-sdd-review-result.sh decide` + its shared journal module
# `scripts/mb_sdd_judge_journal.py`; svp-sdd-core design C5).
#
# Split out of test_sdd_spec_review.bats, which owns the CONFIG and the VERDICT
# writer. The boundary is the record kind, not a line count: `record` writes the
# review verdict, `decide` writes a different kind of record into the same
# journal under a different closed schema, and round 4 found that treating the
# two as one subject is what let `decide` skip the containment `record` had.
# The zone size contract (tests/pytest/test_s2_file_size_contract.py) names this
# file too — a split-out inherits the limit rather than escaping it.
#
# WHAT CHANGED WHEN THESE TESTS MOVED (round-4 [3], design.md C5):
# a decision is a statement ABOUT a review, so `decide` now refuses when the
# journal holds no verdict (`no_review`, exit 2, nothing written). Every case
# below therefore seeds a real verdict FIRST unless it is specifically testing
# the empty-journal refusal — without that, a test named "the decision enum is
# closed" would pass because of `no_review` and never touch the enum at all.
#
# Name convention (X-05): every @test starts with `sdd_decide: `.

bats_require_minimum_version 1.5.0

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RESULT="$REPO_ROOT/scripts/mb-sdd-review-result.sh"
  export LC_ALL=C
  TMP="$(mktemp -d)"
  BANK="$TMP/.memory-bank"
  JSONL="$BANK/tmp/spec-review/t.jsonl"
  mkdir -p "$BANK"
  ID="--generator-model gen --reviewer-model gpt-x --reviewer-agent mb-reviewer --thinking medium"
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

_review() { # <status> <verdict> <reason> — a valid reviewer payload
  printf '{"status":"%s","verdict":%s,"reviewer":{"agent":"mb-reviewer","model":"gpt-x","thinking":"medium"},"issues":[],"reason":%s}' \
    "$1" "$2" "$3"
}

# _decision <decision> <basis> <rationale> — a valid decision payload.
# `kind: "decision"`, never `status: "decided"`: the journal has ONE
# discrimination rule (design.md C5, f886e21) — a record with no `kind` is a
# review verdict, every non-review record carries `kind`.
_decision() {
  printf '{"kind":"decision","decision":"%s","basis":"%s","rationale":"%s","decided_by":"orchestrator"}' \
    "$1" "$2" "$3"
}

# _seed_review <attempt> <status> <verdict> <reason> — a real verdict, written by
# the sanctioned writer, for the decision to be about.
_seed_review() {
  local attempt="$1"; shift
  # shellcheck disable=SC2086  # $ID is a deliberate multi-flag word list
  _review "$@" | bash "$RESULT" record --topic t --attempt "$attempt" --input - \
    --mb "$BANK" $ID > /dev/null 2>&1 || true
  [ -f "$JSONL" ] || { echo "seed review did not land"; return 1; }
}

_decide() { # <attempt> <payload>
  run --separate-stderr bash -c \
    "printf '%s' $(printf '%q' "$2") | $(printf '%q ' "$RESULT") decide --topic t --attempt $1 --input - --mb $(printf '%q' "$BANK")"
}

# ── the accept/reject branches ───────────────────────────────────────────────

@test "sdd_decide: SKIPPED → explicit accept is recordable and exits 0" {
  _seed_review 1 skipped null '"model unavailable"'
  _decide 1 "$(_decision accept skipped 'reviewer unavailable; risk accepted by owner')"
  [ "$status" -eq 0 ] || { echo "explicit accept not recordable: $stderr"; false; }
  assert_grep -q '"kind":"decision"' "$JSONL"
  assert_grep -q '"basis":"skipped"' "$JSONL"
  refute_grep -q 'dismissed_issues' "$JSONL"
  # The actor is CLAIMED by the caller, never verified — the same honesty marker
  # `record` puts on the reviewer. Without it a reader could take "decided_by"
  # for established provenance.
  assert_grep -q '"decided_by_provenance":"claimed"' "$JSONL"
}

@test "sdd_decide: a payload naming another kind is refused, not silently relabelled" {
  # Right key set, wrong value. The writer hardcodes `kind: "decision"` on the
  # line it builds, so without this check a caller declaring `kind: "review"`
  # would have its declared intent quietly rewritten — the record would say
  # something the caller never said.
  _seed_review 1 skipped null '"model unavailable"'
  _decide 1 '{"kind":"review","decision":"accept","basis":"skipped","rationale":"why","decided_by":"orchestrator"}'
  [ "$status" -eq 2 ] || { echo "a foreign kind was relabelled as a decision (rc=$status)"; false; }
  assert_substring "$stderr" "malformed"
  refute_grep -q '"kind":"decision"' "$JSONL"
}

@test "sdd_decide: dismissed-issues → explicit accept is recordable and exits 0" {
  # dismissed_issues needs findings to dismiss, i.e. a CHANGES_REQUESTED verdict.
  _seed_review 2 reviewed '"CHANGES_REQUESTED"' null
  _decide 2 "$(_decision accept dismissed_issues 'all findings judged non-blocking')"
  [ "$status" -eq 0 ] || { echo "dismissed-issues accept not recordable: $stderr"; false; }
  assert_grep -q 'dismissed_issues' "$JSONL"
  assert_grep -q '"attempt":2' "$JSONL"
}

@test "sdd_decide: an explicit REJECT decision exits 1 and stays draft-side" {
  _seed_review 1 reviewed '"CHANGES_REQUESTED"' null
  _decide 1 "$(_decision reject dismissed_issues 'findings stand')"
  [ "$status" -eq 1 ] || { echo "reject did not own exit 1 (rc=$status): $stderr"; false; }
  assert_grep -q '"decision":"reject"' "$JSONL"
}

# ── the closed schema (round-4 [2]) ──────────────────────────────────────────

@test "sdd_decide: the decision and basis enums are CLOSED" {
  # Seeded on purpose: with an empty journal both cases would exit 2 through
  # `no_review` and this test would pass without ever reaching an enum.
  _seed_review 1 skipped null '"model unavailable"'
  _decide 1 "$(_decision maybe skipped 'hand-wave')"
  [ "$status" -eq 2 ] || { echo "decision enum accepted 'maybe' (rc=$status)"; false; }
  assert_substring "$stderr" "malformed"
  _decide 1 "$(_decision accept vibes 'hand-wave')"
  [ "$status" -eq 2 ] || { echo "basis enum accepted 'vibes' (rc=$status)"; false; }
  assert_substring "$stderr" "malformed"
  refute_grep -q '"kind":"decision"' "$JSONL"
}

@test "sdd_decide: a decision without a rationale is refused" {
  # An unexplained accept is exactly what the audit trail exists to prevent.
  _seed_review 1 skipped null '"model unavailable"'
  _decide 1 "$(_decision accept skipped '')"
  [ "$status" -eq 2 ] || { echo "an unexplained accept was recorded (rc=$status)"; false; }
  assert_substring "$stderr" "malformed"
  refute_grep -q '"kind":"decision"' "$JSONL"
}

@test "sdd_decide: an extra field is malformed — the schema is closed, not a floor" {
  _seed_review 1 skipped null '"model unavailable"'
  _decide 1 '{"kind":"decision","decision":"accept","basis":"skipped","rationale":"why","decided_by":"orchestrator","approved_by_ci":true}'
  [ "$status" -eq 2 ] || { echo "an extra field was accepted (rc=$status)"; false; }
  assert_substring "$stderr" "malformed"
  refute_grep -q '"kind":"decision"' "$JSONL"
}

@test "sdd_decide: the pre-discriminator payload shape is refused" {
  # `{"status":"decided",…}` was the shape before the journal got its one
  # discrimination rule. Accepting it now would put a record with NO `kind` and
  # no verdict fields into the journal — a line every reader must then classify
  # as a review by the absence of `kind`, which is exactly the ambiguity the
  # rule removes.
  _seed_review 1 skipped null '"model unavailable"'
  _decide 1 '{"status":"decided","decision":"accept","basis":"skipped","rationale":"why","decided_by":"orchestrator"}'
  [ "$status" -eq 2 ] || { echo "the legacy payload shape was accepted (rc=$status)"; false; }
  assert_substring "$stderr" "malformed"
  refute_grep -q 'decided' "$JSONL"
}

@test "sdd_decide: a decision carrying a secret is blocked before the JSONL write" {
  # Not seeded: the secret gate runs before the journal is consulted at all, and
  # the assertion names `secret_blocked`, so the cause is unambiguous either way.
  _decide 1 "$(_decision accept skipped 'token sk-ant-api03ABCDEFGHIJKLMNOP')"
  [ "$status" -eq 2 ]
  assert_substring "$stderr" "secret_blocked"
  refute_file "$JSONL"
}

@test "sdd_decide: the record action still refuses a decision payload" {
  # The two schemas stay separate: `record` must not quietly accept a decision.
  run --separate-stderr bash -c "$(printf '%q ' "$RESULT") record --topic t --attempt 1 --input - --mb $(printf '%q' "$BANK") $ID <<'IN'
$(_decision accept skipped 'why')
IN"
  [ "$status" -eq 2 ]
  refute_file "$JSONL"
}

@test "sdd_decide: sdd.md documents the decide writer and its discriminator" {
  # The C7 branch existed in prose with no executable writer; the prompt must
  # name the sanctioned one, and now also the payload key, so nobody
  # hand-appends, fakes an APPROVED, or writes the pre-discriminator shape.
  local md="$REPO_ROOT/commands/sdd.md"
  assert_grep -Eq 'mb-sdd-review-result\.sh decide --topic' "$md"
  assert_grep -q '"kind":"decision"' "$md"
  refute_grep -q '"status":"decided"' "$md"
  # One pattern, not two alternatives: `.` already covers every quoting style
  # the second alternative spelled out, and the redundant branch made this line
  # DEAD — inverting it left the other branch to carry the test, so the
  # assertion could not fail. (tools/prove_assertions.py caught it here.)
  assert_grep -q 'never fake an .APPROVED. review' "$md"
}
