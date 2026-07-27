#!/usr/bin/env bats
# spec_review_r4: — svp-sdd-core round-4 review findings on the C5 verdict owner
# (scripts/mb-sdd-review-result.sh).
#
#   [3] BLOCKER — `decide accept` was accepted with NO review in the journal at
#       all. "Accept, because the review was skipped" is a statement about a
#       review that was attempted; with an empty journal it is a gate bypass
#       wearing an audit trail's clothes.
#   [4] MAJOR   — `decide` skipped the containment checks `record` performs, so
#       a symlinked `tmp/spec-review` (or a symlinked `<topic>.jsonl`) diverted
#       the decision line outside the bank.
#
# Name convention (X-05): every @test starts with `spec_review_r4: `.
#
# Absence assertions go through tests/bats/lib/assert.bash: `! cmd` is exempt
# from `set -e` unless it is the last command in the body (I-147).

bats_require_minimum_version 1.5.0

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RESULT="$REPO_ROOT/scripts/mb-sdd-review-result.sh"
  export LC_ALL=C
  TMP="$(mktemp -d)"
  BANK="$TMP/.memory-bank"
  mkdir -p "$BANK"
  JSONL="$BANK/tmp/spec-review/t.jsonl"
  ID="--generator-model gen --reviewer-model gpt-x --reviewer-agent mb-reviewer --thinking medium"
  # FIXTURE ONLY — no assertion of this contract is touched. `record` now
  # refuses a reviewer model outside `sdd.spec_review.model` (AGR-034 [8], judge
  # B4), and every `_record` below seeds a verdict through it, so the bank has
  # to name the model these tests review with. A bank with no pipeline inherits
  # the bundled default, whose `model: inherit` sanctions nothing.
  cat > "$BANK/pipeline.yaml" <<'YAML'
sdd:
  spec_review: {enabled: true, agent: mb-reviewer, model: gpt-x, thinking: medium}
YAML
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

# _review <status> <verdict> <reason> — a valid reviewer payload.
_review() {
  printf '{"status":"%s","verdict":%s,"reviewer":{"agent":"mb-reviewer","model":"gpt-x","thinking":"medium"},"issues":[],"reason":%s}' \
    "$1" "$2" "$3"
}

# _decision <decision> <basis> <rationale> — a valid decision payload.
#
# The payload key is `kind: "decision"`, NOT `status: "decided"`. This is the
# closed schema in svp-sdd-core design.md C5 (f886e21):
#
#   {kind: "decision", decision: "accept"|"reject", basis: "skipped"|
#    "dismissed_issues", rationale: <непустая строка>, decided_by: <непустая>}
#
# and it follows from the journal's one discrimination rule — absence of `kind`
# means a review record, every non-review record carries `kind`. The literal
# below was written before that rule landed; ONLY the literal changed here, no
# assertion of this contract was touched.
_decision() {
  printf '{"kind":"decision","decision":"%s","basis":"%s","rationale":"%s","decided_by":"orchestrator"}' \
    "$1" "$2" "$3"
}

# _record <attempt> <status> <verdict> <reason> — put a real review in the journal.
_record() {
  local a="$1"; shift
  # shellcheck disable=SC2086  # $ID is a deliberate multi-flag word list
  _review "$@" | "$RESULT" record --topic t --attempt "$a" --input - --mb "$BANK" $ID
}

# _decide <attempt> <decision> <basis> <rationale> — run the decide subcommand.
_decide() {
  local a="$1"; shift
  _decision "$@" | "$RESULT" decide --topic t --attempt "$a" --input - --mb "$BANK"
}

# ── [3] a decision needs a review to decide about ───────────────────────────

@test "spec_review_r4: [3] accept-on-skipped with an EMPTY journal is refused" {
  run --separate-stderr _decide 1 accept skipped 'reviewer unavailable; risk accepted'
  [ "$status" -eq 2 ] || { echo "accept without any review was recorded (rc=$status)"; false; }
  assert_substring "$stderr" "no_review" \
    || { echo "refusal does not name the cause: $stderr"; false; }
  refute_file "$JSONL" \
    || { echo "a decision line was written with no review in the journal"; false; }
}

@test "spec_review_r4: [3] reject with an EMPTY journal is refused too" {
  # A rejection is equally a statement about a review that happened.
  run --separate-stderr _decide 1 reject dismissed_issues 'findings stand'
  [ "$status" -eq 2 ] || { echo "reject without any review was recorded (rc=$status)"; false; }
  refute_file "$JSONL"
}

@test "spec_review_r4: [3] accept-on-skipped AFTER a recorded SKIPPED review is allowed" {
  _record 1 skipped null '"model unavailable"' || true   # record owns exit 2 for skipped
  run --separate-stderr _decide 1 accept skipped 'reviewer unavailable; risk accepted'
  [ "$status" -eq 0 ] || { echo "a legitimate decision was refused (rc=$status): $stderr"; false; }
  assert_grep -q 'decided' "$JSONL"
}

@test "spec_review_r4: [3] accept-on-dismissed-issues AFTER CHANGES_REQUESTED is allowed" {
  _record 1 reviewed '"CHANGES_REQUESTED"' null || true  # record owns exit 1 for CR
  run --separate-stderr _decide 1 accept dismissed_issues 'all findings judged non-blocking'
  [ "$status" -eq 0 ] || { echo "a legitimate decision was refused (rc=$status): $stderr"; false; }
  assert_grep -q 'dismissed_issues' "$JSONL"
}

@test "spec_review_r4: [3] the basis must match the review that actually happened" {
  # The review ran and asked for changes; claiming it was SKIPPED rewrites what
  # the journal says happened.
  _record 1 reviewed '"CHANGES_REQUESTED"' null || true
  run --separate-stderr _decide 1 accept skipped 'pretend nobody reviewed'
  [ "$status" -eq 2 ] || { echo "a basis contradicting the journal was accepted (rc=$status)"; false; }
  refute_grep -q 'decided' "$JSONL" \
    || { echo "the contradicting decision reached the journal"; false; }
}

@test "spec_review_r4: [3] dismissed_issues over an APPROVED review is refused" {
  # An APPROVED review has nothing to dismiss and needs no decision — accepting
  # one here would manufacture a paper trail for a choice nobody made.
  _record 1 reviewed '"APPROVED"' null
  run --separate-stderr _decide 1 accept dismissed_issues 'nothing to dismiss'
  [ "$status" -eq 2 ] || { echo "dismissed_issues accepted over APPROVED (rc=$status)"; false; }
  refute_grep -q 'decided' "$JSONL"
}

# ── [4] containment: a decision may not leave the bank ──────────────────────

@test "spec_review_r4: [4] a symlinked tmp/spec-review cannot divert the decision" {
  local victim="$TMP/victim"; mkdir -p "$victim"
  mkdir -p "$BANK/tmp"
  ln -s "$victim" "$BANK/tmp/spec-review"
  # a legitimate precondition, so the refusal is attributable to containment
  _record 1 skipped null '"model unavailable"' || true
  run --separate-stderr _decide 1 accept skipped 'reviewer unavailable'
  [ "$status" -eq 2 ] || { echo "decide followed a symlinked directory (rc=$status)"; false; }
  refute_file "$victim/t.jsonl" \
    || { echo "the decision line was written outside the bank"; false; }
}

@test "spec_review_r4: [4] a symlinked <topic>.jsonl is not followed" {
  local victim="$TMP/victim.jsonl"; : > "$victim"
  mkdir -p "$BANK/tmp/spec-review"
  # seed a real review first, then swap the journal file for a symlink
  _record 1 skipped null '"model unavailable"' || true
  cp "$JSONL" "$victim"
  rm -f "$JSONL"
  ln -s "$victim" "$JSONL"
  run --separate-stderr _decide 1 accept skipped 'reviewer unavailable'
  [ "$status" -eq 2 ] || { echo "decide followed a symlinked journal file (rc=$status)"; false; }
  refute_grep -q 'decided' "$victim" \
    || { echo "the decision line was appended through the symlink"; false; }
}
