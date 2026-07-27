#!/usr/bin/env bats
# judge_journal_*: — svp-spec-review-loop C2, the judge/override/status half of
# the spec-review journal (scripts/mb-sdd-review-result.sh + its writer module
# scripts/mb_sdd_judge_journal.py; REQ-002, REQ-003, REQ-006, REQ-015, REQ-016,
# AMEND-S9-1/2/4, AGR-034 [8]).
#
# Name convention (X-05): every @test starts with `judge_journal_`; the Eval
# red anchor `not ok [0-9]+ judge_journal_(record_go|record_no_go|items_required|
# override|same_model_triple|status_line|status_empty)` is carried by those seven.
#
# TWO RULES THIS FILE OBEYS ON PURPOSE:
#
# 1. Every journal fixture is written through the SANCTIONED S2 writer
#    (`record --topic ... --input -`), never by hand. A hand-assembled journal
#    proves things about the test's idea of the format, not about the file the
#    product actually produces — and this suite's whole subject is that file.
# 2. Nothing here observes a shared resource (I-155). The bank lives inside a
#    per-test `mktemp -d`, and it carries a SPACE in its path, so every case
#    doubles as the spaces-in-bank-path requirement rather than one token case.

bats_require_minimum_version 1.5.0
load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RESULT="$REPO_ROOT/scripts/mb-sdd-review-result.sh"
  JOURNAL_PY="$REPO_ROOT/scripts/mb_sdd_judge_journal.py"
  export LC_ALL=C
  TMP="$(mktemp -d)"
  BANK="$TMP/pro ject/.memory-bank"
  JSONL="$BANK/tmp/spec-review/demo.jsonl"
  mkdir -p "$BANK/specs/demo"
  _pipeline judge-x rev-x
  _frontmatter gen-x
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

# _pipeline <judge-model> <review-model> — the bank's own pipeline.yaml, i.e.
# the roster a recorded judge model must belong to (AGR-034 [8]).
_pipeline() {
  cat > "$BANK/pipeline.yaml" <<YAML
sdd:
  spec_review: {enabled: true, agent: mb-reviewer, model: $2, thinking: medium}
  spec_judge: {enabled: true, agent: mb-judge, model: $1, thinking: medium, max_cycles: 2}
YAML
}

# _frontmatter <model|-> — spec frontmatter; `-` writes the key-less form that
# makes the generator leg of the same-model triple unresolvable (REQ-016).
_frontmatter() {
  {
    printf -- '---\n'
    printf 'topic: demo\n'
    [ "$1" = "-" ] || printf 'generated_by: %s\n' "$1"
    printf -- '---\n\n# Requirements: demo\n'
  } > "$BANK/specs/demo/requirements.md"
}

_issues() {  # <0|2> — issue array of the given size
  case "$1" in
    0) printf '[]' ;;
    2) printf '%s%s' \
         '[{"severity":"major","category":"logic","req":"REQ-002","description":"d1"},' \
         '{"severity":"minor","category":"tests","req":null,"description":"d2"}]' ;;
  esac
}

# _record_review <APPROVED|CHANGES_REQUESTED|SKIP> <attempt> <issues-json>
_record_review() {
  local json
  if [ "$1" = "SKIP" ]; then
    json='{"status":"skipped","verdict":null,"reviewer":{"agent":"mb-reviewer","model":"rev-x","thinking":"medium"},"issues":[],"reason":"model unavailable"}'
  else
    json="$(printf '{"status":"reviewed","verdict":"%s","reviewer":{"agent":"mb-reviewer","model":"rev-x","thinking":"medium"},"issues":%s,"reason":null}' "$1" "$3")"
  fi
  # exit code varies by verdict (0/1/2) and is not the fixture's subject; that
  # the line LANDED is, so that is what is asserted.
  printf '%s' "$json" | bash "$RESULT" record --topic demo --attempt "$2" --input - \
    --mb "$BANK" --generator-model gen-x --reviewer-model rev-x \
    --reviewer-agent mb-reviewer --thinking medium >/dev/null 2>&1 || true
  [ -f "$JSONL" ] || { echo "fixture did not land: $JSONL"; return 1; }
}

_judge() {  # _judge <flags...> — record a judge decision for topic demo
  run --separate-stderr bash "$RESULT" record --kind judge --mb "$BANK" "$@" demo
}

# ── record --kind judge ──────────────────────────────────────────────────────

@test "judge_journal_record_go: GO is appended with ts/attempt/kind/decision and exits 0" {
  _record_review APPROVED 1 "$(_issues 0)"
  _judge --decision GO --judge-model judge-x
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  local last; last="$(tail -1 "$JSONL")"
  assert_substring "$last" '"kind":"judge"'
  assert_substring "$last" '"decision":"GO"'
  assert_substring "$last" '"attempt":1'
  assert_substring "$last" '"confirmed":{}'
  printf '%s\n' "$last" > "$TMP/last"
  assert_grep -Eq '"ts":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"' "$TMP/last"
}

@test "judge_journal_record_no_go: NO_GO is recorded and exits 1" {
  _record_review CHANGES_REQUESTED 1 "$(_issues 2)"
  _judge --decision NO_GO --confirmed R1-001=true,R1-002=true --judge-model judge-x
  [ "$status" -eq 1 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  local last; last="$(tail -1 "$JSONL")"
  assert_substring "$last" '"kind":"judge"'
  assert_substring "$last" '"decision":"NO_GO"'
}

@test "judge_journal_items_required: GO_WITH_BACKLOG over surviving findings without --items is refused and appends nothing" {
  _record_review CHANGES_REQUESTED 1 "$(_issues 2)"
  snapshot "$JSONL" "$TMP/before"
  _judge --decision GO_WITH_BACKLOG --confirmed R1-001=true,R1-002=false --judge-model judge-x
  [ "$status" -eq 1 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  assert_unchanged "$JSONL" "$TMP/before"
  # The refusal is conditional, not blanket: with the ids the same decision lands.
  _judge --decision GO_WITH_BACKLOG --items I-101,I-102 \
    --confirmed R1-001=true,R1-002=false --judge-model judge-x
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  local last; last="$(tail -1 "$JSONL")"
  assert_substring "$last" '"items":["I-101","I-102"]'
  # An id that is not a backlog id would satisfy "GO_WITH_BACKLOG has items"
  # while pointing at nothing — the accepted-with-a-backlog-that-does-not-exist
  # record this branch exists to prevent.
  snapshot "$JSONL" "$TMP/after-valid"
  _judge --decision GO_WITH_BACKLOG --items not-a-backlog-id \
    --confirmed R1-001=true,R1-002=false --judge-model judge-x
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_unchanged "$JSONL" "$TMP/after-valid"
  # …and an unknown decision is malformed, not a fourth verdict value.
  _judge --decision MAYBE --confirmed R1-001=true,R1-002=false --judge-model judge-x
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_unchanged "$JSONL" "$TMP/after-valid"
}

@test "judge_journal_override: an override is appended as its own kind, silently, and exits 0" {
  _record_review CHANGES_REQUESTED 1 "$(_issues 0)"
  run --separate-stderr bash "$RESULT" record --kind override --mb "$BANK" demo
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  # stdout stays empty: the C5 gate owns the stdout of the run that calls this,
  # and its contract includes "prints nothing" states.
  [ -z "$output" ]
  printf '%s\n' "$(tail -1 "$JSONL")" > "$TMP/last"
  assert_grep -Eq '^\{"ts":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z","kind":"override"\}$' "$TMP/last"
}

@test "judge_journal_same_model_triple: judge equal to reviewer or generator is refused; a missing generator warns and proceeds" {
  _record_review CHANGES_REQUESTED 1 "$(_issues 0)"
  snapshot "$JSONL" "$TMP/before"

  # (1) judge == the reviewer that produced the verdict under judgement
  _pipeline rev-x rev-x
  _judge --decision GO --judge-model rev-x
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$stderr" "same_model"
  assert_unchanged "$JSONL" "$TMP/before"

  # (2) judge == the model that generated the spec (frontmatter generated_by)
  _pipeline gen-x rev-x
  _judge --decision GO --judge-model gen-x
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$stderr" "same_model"
  assert_unchanged "$JSONL" "$TMP/before"

  # (3) no generated_by at all — a WARNING on stderr, not an error (REQ-016)
  _pipeline judge-x rev-x
  _frontmatter -
  _judge --decision GO --judge-model judge-x
  [ "$status" -eq 0 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$stderr" "generator_model_unknown"
}

@test "judge_journal_check_judge: check --judge refuses the same-model triple before dispatch and writes nothing" {
  _record_review CHANGES_REQUESTED 1 "$(_issues 0)"
  snapshot "$JSONL" "$TMP/before"
  run --separate-stderr bash "$RESULT" check --judge --judge-model rev-x --mb "$BANK" demo
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$stderr" "same_model"
  run --separate-stderr bash "$RESULT" check --judge --judge-model gen-x --mb "$BANK" demo
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$stderr" "same_model"
  # no --judge-model: the configured judge is resolved from the same roster
  run --separate-stderr bash "$RESULT" check --judge --mb "$BANK" demo
  [ "$status" -eq 0 ] || { echo "rc=$status err=$stderr"; false; }
  assert_unchanged "$JSONL" "$TMP/before"
}

@test "judge_journal_check_unresolvable: a check that cannot name both models refuses instead of passing" {
  # An independence check that silently skips a leg it could not resolve is a
  # check that reports "independent" about a comparison it never made.
  _pipeline inherit inherit
  run --separate-stderr bash "$RESULT" check --judge --mb "$BANK" demo
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$stderr" "judge_model_unknown"
  run --separate-stderr bash "$RESULT" check --judge --judge-model judge-x --mb "$BANK" demo
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$stderr" "reviewer_model_unknown"
}

@test "judge_journal_roster_nonstring: a roster value that is not a string names no model" {
  # `model: 123` is an int to every YAML loader, and the pipeline validator says
  # so when it runs — but nothing guarantees it ran. A record authorised by a
  # config value no dispatcher could use is authorised by nothing.
  _record_review CHANGES_REQUESTED 1 "$(_issues 0)"
  snapshot "$JSONL" "$TMP/before"
  _pipeline 123 rev-x
  _judge --decision GO --judge-model 123
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$stderr" "model_not_in_roster"
  assert_unchanged "$JSONL" "$TMP/before"
}

@test "judge_journal_missing_judge_model: record --kind judge without --judge-model is a usage error" {
  # The flag is mandatory so the roster gate has something to check; a defaulted
  # value would make the gate compare the roster with itself.
  _record_review CHANGES_REQUESTED 1 "$(_issues 0)"
  snapshot "$JSONL" "$TMP/before"
  run --separate-stderr bash "$RESULT" record --kind judge --decision GO --mb "$BANK" demo
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$stderr" "error=usage"
  assert_unchanged "$JSONL" "$TMP/before"
}

@test "judge_journal_roster: a judge model outside the pipeline roster is not recorded at all (AGR-034)" {
  _record_review CHANGES_REQUESTED 1 "$(_issues 0)"
  snapshot "$JSONL" "$TMP/before"
  _judge --decision GO --judge-model rogue-y
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$stderr" "model_not_in_roster"
  assert_unchanged "$JSONL" "$TMP/before"
  # A placeholder roster authorises nothing either: `inherit` names no model, so
  # it cannot back a provenance claim about which model judged. Asserted with
  # the judge model spelled `inherit` TOO — with any other spelling this case
  # would pass as a plain mismatch and prove nothing about the placeholder rule
  # (the mutant that accepted `inherit` as an identity survived exactly that).
  _pipeline inherit rev-x
  _judge --decision GO --judge-model inherit
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$stderr" "model_not_in_roster"
  assert_unchanged "$JSONL" "$TMP/before"
  _judge --decision GO --judge-model judge-x
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$stderr" "model_not_in_roster"
  assert_unchanged "$JSONL" "$TMP/before"
}

@test "judge_journal_confirmed: a decision missing a per-finding confirmation is malformed and unwritten (AMEND-S9-2)" {
  _record_review CHANGES_REQUESTED 1 "$(_issues 2)"
  snapshot "$JSONL" "$TMP/before"
  _judge --decision NO_GO --confirmed R1-001=true --judge-model judge-x
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$stderr" "malformed"
  assert_unchanged "$JSONL" "$TMP/before"
  _judge --decision NO_GO --judge-model judge-x
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_unchanged "$JSONL" "$TMP/before"
  _judge --decision NO_GO --confirmed R1-001=true,R9-999=false --judge-model judge-x
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_unchanged "$JSONL" "$TMP/before"
  _judge --decision NO_GO --confirmed R1-001=true,R1-002=false --judge-model judge-x
  [ "$status" -eq 1 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$(tail -1 "$JSONL")" '"confirmed":{"R1-001":true,"R1-002":false}'
}

@test "judge_journal_generator_check: a missing generated_by is journaled as skipped, a present one as performed (AMEND-S9-4)" {
  _record_review APPROVED 1 "$(_issues 0)"
  _frontmatter -
  _judge --decision GO --judge-model judge-x
  [ "$status" -eq 0 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$(tail -1 "$JSONL")" '"generator_check":"skipped"'
  _frontmatter gen-x
  _judge --decision GO --judge-model judge-x
  [ "$status" -eq 0 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$(tail -1 "$JSONL")" '"generator_check":"performed"'
}

@test "judge_journal_no_verdict: a judge record with no verdict to judge is refused and creates no journal" {
  _judge --decision GO --judge-model judge-x
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$stderr" "no_verdict_to_judge"
  refute_file "$JSONL"
}

# ── status ───────────────────────────────────────────────────────────────────

@test "judge_journal_status_line: a full journal yields exactly one line in the documented format" {
  _record_review CHANGES_REQUESTED 1 "$(_issues 0)"
  bash "$RESULT" record --kind judge --decision NO_GO --judge-model judge-x --mb "$BANK" demo >/dev/null 2>&1 || true
  _record_review APPROVED 2 "$(_issues 0)"
  bash "$RESULT" record --kind judge --decision GO --judge-model judge-x --mb "$BANK" demo >/dev/null 2>&1 || true
  bash "$RESULT" record --kind override --mb "$BANK" demo >/dev/null 2>&1 || true
  run --separate-stderr bash "$RESULT" status --mb "$BANK" demo
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  [ "${#lines[@]}" -eq 1 ]
  [ "$output" = "spec_review=APPROVED judge=GO override=yes" ]
}

@test "judge_journal_status_empty: an absent journal is none/none/no, exits 0 and creates nothing" {
  run --separate-stderr bash "$RESULT" status --mb "$BANK" demo
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  [ "$output" = "spec_review=none judge=none override=no" ]
  refute_file "$JSONL"
}

@test "judge_journal_status_skipped: a skipped review reports SKIPPED, not none" {
  _record_review SKIP 1 "$(_issues 0)"
  run --separate-stderr bash "$RESULT" status --mb "$BANK" demo
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  [ "$output" = "spec_review=SKIPPED judge=none override=no" ]
}

# ── the seam with the S2 half: the verdict line carries NO discriminator ─────

@test "judge_journal_seam_no_discriminator: the reader recognises a verdict line by shape, not by a kind key" {
  # The cross-spec hazard (S2 svp-sdd-core owns the verdict line, S9 owns the
  # reader): a reader matching `kind:"review"` would see NO verdict at all,
  # while both halves' own suites stayed green. The fixture below is written by
  # the REAL S2 writer, so this asserts the actual seam, not a shared belief
  # about it — and it asserts the absence of the key explicitly, so if S2 ever
  # starts emitting one, the change is announced HERE instead of silently
  # flipping which branch of the reader runs.
  _record_review CHANGES_REQUESTED 1 "$(_issues 0)"
  refute_grep -q '"kind"' "$JSONL"
  run --separate-stderr bash "$RESULT" status --mb "$BANK" demo
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  [ "$output" = "spec_review=CHANGES_REQUESTED judge=none override=no" ]
}

@test "judge_journal_seam_explicit_kind: a verdict line that DOES carry kind=review is read the same way" {
  # Forward compatibility, deliberately pinned: if S2 lands a discriminator on
  # the verdict line, this reader must keep working. Untested tolerance is
  # indistinguishable from accidental tolerance, and the next edit deletes it.
  _record_review APPROVED 1 "$(_issues 0)"
  python3 - "$JSONL" <<'PY'
import json, sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines()
obj = json.loads(lines[-1]); obj["kind"] = "review"
lines[-1] = json.dumps(obj, separators=(",", ":"))
open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
  assert_grep -q '"kind":"review"' "$JSONL"
  run --separate-stderr bash "$RESULT" status --mb "$BANK" demo
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  [ "$output" = "spec_review=APPROVED judge=none override=no" ]
}

@test "judge_journal_seam_decision_kind: a C7 decision is its own kind — it neither corrupts the journal nor answers for the verdict" {
  # Third writer on the same journal (svp-sdd-core C5 `decide`). Written here by
  # the sanctioned writer, not by hand, so this is the real cross-half seam:
  # "действующее состояние каждого рода — последняя валидная строка ЭТОГО рода;
  # строка чужого рода никогда не отвечает за состояние своего".
  _record_review CHANGES_REQUESTED 1 "$(_issues 0)"
  printf '%s' '{"kind":"decision","decision":"accept","basis":"dismissed_issues","rationale":"findings judged non-blocking","decided_by":"orchestrator"}' \
    | bash "$RESULT" decide --topic demo --attempt 1 --input - --mb "$BANK" > /dev/null 2>&1
  assert_grep -q '"kind":"decision"' "$JSONL"
  run --separate-stderr bash "$RESULT" status --mb "$BANK" demo
  [ "$status" -eq 0 ] || { echo "a decision line made the journal unreadable: rc=$status $stderr"; false; }
  [ "$output" = "spec_review=CHANGES_REQUESTED judge=none override=no" ]
  # …and the write path agrees: the judge still judges the VERDICT, even though
  # a decision line is the most recent record in the file.
  run --separate-stderr bash "$RESULT" record --kind judge --decision NO_GO --judge-model judge-x --mb "$BANK" demo
  [ "$status" -eq 1 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$(tail -1 "$JSONL")" '"attempt":1'
}

@test "judge_journal_seam_unknown_kind: a line with an UNKNOWN discriminator is corruption, not a verdict" {
  # The fail-closed half of the same seam. A future kind this reader has never
  # heard of must not be smuggled in through the shape check and answered as a
  # verdict — "I do not know what this line is" is exactly the state AMEND-S9-1
  # says must be loud.
  _record_review APPROVED 1 "$(_issues 0)"
  python3 - "$JSONL" <<'PY'
import json, sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines()
obj = json.loads(lines[-1]); obj["kind"] = "amendment"
lines[-1] = json.dumps(obj, separators=(",", ":"))
open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
  run --separate-stderr bash "$RESULT" status --mb "$BANK" demo
  [ "$status" -eq 5 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  assert_substring "$stderr" "status_unreadable"
  refute_substring "$output" "spec_review="
}

@test "judge_journal_status_only_corrupt: a journal whose whole content is unreadable is exit 5, never none" {
  # The sharpest form of AMEND-S9-1: here a lenient reader that skips lines it
  # cannot parse would answer exactly `spec_review=none … exit 0`, which is
  # indistinguishable from "no review has happened yet" and is the fail-open
  # D-05 forbids. Proven red against such a reader, not merely asserted.
  mkdir -p "$(dirname "$JSONL")"
  printf 'truncated{"status":"rev\n\x00\x01 garbage\n' > "$JSONL"
  run --separate-stderr bash "$RESULT" status --mb "$BANK" demo
  [ "$status" -eq 5 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  assert_substring "$stderr" "status_unreadable"
  refute_substring "$output" "none"
}

@test "judge_journal_status_unreadable: a corrupt journal exits 5 with status_unreadable, never none (AMEND-S9-1)" {
  _record_review APPROVED 1 "$(_issues 0)"
  printf 'not json at all\n' >> "$JSONL"
  snapshot "$JSONL" "$TMP/before"
  run --separate-stderr bash "$RESULT" status --mb "$BANK" demo
  [ "$status" -eq 5 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  assert_substring "$stderr" "status_unreadable"
  refute_substring "$output" "spec_review="
  # reading a corrupt journal must not "repair" it either
  assert_unchanged "$JSONL" "$TMP/before"
  # …and the WRITE path fails closed on the same journal: appending to a file
  # whose current state nobody can read would build history on top of damage.
  run --separate-stderr bash "$RESULT" record --kind judge --decision GO --judge-model judge-x --mb "$BANK" demo
  [ "$status" -eq 5 ] || { echo "rc=$status err=$stderr"; false; }
  assert_unchanged "$JSONL" "$TMP/before"
}

@test "judge_journal_status_corrupt_decision: a decision line with a broken shape is corruption, not state" {
  # Same rule as the override case below, for the third kind: a `kind` this
  # reader DOES know, carrying fields it cannot make sense of, must be loud
  # rather than counted — otherwise a damaged decision line quietly becomes
  # "no decision was made".
  _record_review APPROVED 1 "$(_issues 0)"
  printf '{"kind":"decision","decision":"maybe"}\n' >> "$JSONL"
  run --separate-stderr bash "$RESULT" status --mb "$BANK" demo
  [ "$status" -eq 5 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  assert_substring "$stderr" "status_unreadable"
}

@test "judge_journal_status_corrupt_kind: a line of a known kind with a broken shape is corruption, not an absence" {
  # `{"kind":"override"}` with no ts is the shape a truncated or hand-edited
  # append leaves behind. Classifying it loosely would let a damaged journal
  # answer questions about override state.
  _record_review APPROVED 1 "$(_issues 0)"
  printf '{"kind":"override"}\n' >> "$JSONL"
  run --separate-stderr bash "$RESULT" status --mb "$BANK" demo
  [ "$status" -eq 5 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  assert_substring "$stderr" "status_unreadable"
}

@test "judge_journal_status_stale_judge: a judge decision older than the effective verdict is not the effective decision" {
  # REQ-009 blocks work on a CHANGES_REQUESTED verdict "without a judge GO".
  # A GO recorded over the PREVIOUS attempt is not a GO over this one: after a
  # fix pass and a fresh independent review (ADR-S9-2) the new verdict has not
  # been judged at all, and reporting the old decision would hand the C5 gate a
  # pass for a verdict nobody judged.
  _record_review CHANGES_REQUESTED 1 "$(_issues 0)"
  bash "$RESULT" record --kind judge --decision GO --judge-model judge-x --mb "$BANK" demo >/dev/null 2>&1 || true
  run --separate-stderr bash "$RESULT" status --mb "$BANK" demo
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  # positive control: while it pertains to the current verdict, it IS reported
  [ "$output" = "spec_review=CHANGES_REQUESTED judge=GO override=no" ]
  # a fresh review of the fixed spec — attempt 2, not yet judged
  _record_review CHANGES_REQUESTED 2 "$(_issues 0)"
  run --separate-stderr bash "$RESULT" status --mb "$BANK" demo
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  [ "$output" = "spec_review=CHANGES_REQUESTED judge=none override=no" ]
}

# ── append-only (a security property, so it is proven twice) ─────────────────

@test "judge_journal_append_only: re-judging the same verdict appends and leaves earlier bytes byte-identical" {
  _record_review CHANGES_REQUESTED 1 "$(_issues 0)"
  bash "$RESULT" record --kind judge --decision NO_GO --judge-model judge-x --mb "$BANK" demo >/dev/null 2>&1 || true
  [ "$(wc -l < "$JSONL")" -eq 2 ]
  snapshot "$JSONL" "$TMP/first-two"
  # The same verdict judged a second time — the shape an in-place update would take.
  bash "$RESULT" record --kind judge --decision GO --judge-model judge-x --mb "$BANK" demo >/dev/null 2>&1 || true
  [ "$(wc -l < "$JSONL")" -eq 3 ]
  head -n 2 "$JSONL" > "$TMP/prefix-now"
  assert_unchanged "$TMP/prefix-now" "$TMP/first-two"
  assert_substring "$(head -1 "$JSONL")" '"verdict":"CHANGES_REQUESTED"'
  assert_substring "$(sed -n 2p "$JSONL")" '"decision":"NO_GO"'
}

@test "judge_journal_module_args: a journal subcommand without a bank is a usage error, not a write next to the caller" {
  # `--bank`/`--topic` stopped being argparse-required so that `check-roster`,
  # which answers a question about the config alone, need not be handed
  # arguments it must then ignore. That relaxation is only safe because the
  # journal subcommands re-check: with an empty bank, `journal_file("")` is a
  # RELATIVE path, so the reader/writer would quietly act on
  # `tmp/spec-review/<topic>.jsonl` inside whatever directory the caller
  # happened to be in. The shell wrapper always passes both, so nothing but this
  # test stands between that relaxation and a journal written outside any bank.
  cd "$TMP" || return 1
  run --separate-stderr python3 "$JOURNAL_PY" status --topic demo
  [ "$status" -eq 2 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  assert_substring "$stderr" "error=usage"
  refute_file "$TMP/tmp/spec-review/demo.jsonl"
  # …while the config-only subcommand legitimately needs neither.
  run --separate-stderr python3 "$JOURNAL_PY" check-roster \
    --pipeline "$BANK/pipeline.yaml" --block spec_review --model rev-x
  [ "$status" -eq 0 ] || { echo "rc=$status err=$stderr"; false; }
}

@test "judge_journal_append_only_writer: no writer of this journal has a non-append open mode" {
  # The behavioural proof above is conditional on the arguments it happened to
  # pass. This one is not: a truncating or updating mode anywhere in either
  # writer would make a rewrite REACHABLE, and append-only here is a security
  # property of an audit trail, not a habit of the happy path.
  assert_grep -Eq 'open\(real_target, "a"' "$JOURNAL_PY"
  refute_grep -nE 'open\([^)]*, *"(w|w\+|r\+|x|a\+)"' "$JOURNAL_PY"
  refute_grep -nE 'open\([^)]*, *"(w|w\+|r\+|x|a\+)"' "$RESULT"
}

@test "judge_journal_containment_ancestor: a symlinked ANCESTOR cannot divert the judge append outside the bank" {
  # The link is on `tmp/`, so neither the journal file nor its directory is a
  # symlink and both per-component checks pass. Only resolving the final write
  # path and comparing it with the one path inside the bank catches this, which
  # is why that comparison is not a duplicate of the two above it.
  _record_review CHANGES_REQUESTED 1 "$(_issues 0)"
  local victim="$TMP/victim"
  mv "$BANK/tmp" "$victim"
  ln -s "$victim" "$BANK/tmp"
  snapshot "$victim/spec-review/demo.jsonl" "$TMP/before"
  _judge --decision GO --judge-model judge-x
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$stderr" "path_escape"
  assert_unchanged "$victim/spec-review/demo.jsonl" "$TMP/before"
}

@test "judge_journal_containment_dangling: a DANGLING symlink in the write path is refused cleanly, not crashed through" {
  # `tmp/spec-review` pointing at something that no longer exists is what a
  # half-cleaned-up attack or a broken restore leaves behind. Without the
  # directory symlink check, `mkdir(exist_ok=True)` raises FileExistsError on a
  # dangling link — the run dies with a traceback and a Python exit code instead
  # of the documented `path_escape`/exit 2, and a caller keying on exit 2 reads
  # the crash as something else entirely.
  #
  # Asserted through `override` on purpose: it is the one subcommand that
  # reaches the append without first needing a readable journal, so the append's
  # own containment is what the exit code attributes to.
  mkdir -p "$BANK/tmp"
  ln -s "$TMP/does-not-exist" "$BANK/tmp/spec-review"
  run --separate-stderr bash "$RESULT" record --kind override --mb "$BANK" demo
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$stderr" "path_escape"
  refute_substring "$stderr" "Traceback"
  refute_file "$TMP/does-not-exist"
}

@test "judge_journal_containment: a symlinked journal cannot divert the judge append outside the bank" {
  _record_review CHANGES_REQUESTED 1 "$(_issues 0)"
  local victim="$TMP/victim"; mkdir -p "$victim"
  mv "$JSONL" "$victim/demo.jsonl"
  ln -s "$victim/demo.jsonl" "$JSONL"
  snapshot "$victim/demo.jsonl" "$TMP/before"
  _judge --decision GO --judge-model judge-x
  [ "$status" -eq 2 ] || { echo "rc=$status err=$stderr"; false; }
  assert_substring "$stderr" "path_escape"
  assert_unchanged "$victim/demo.jsonl" "$TMP/before"
}

# ── the S2 half must be exactly as it was ────────────────────────────────────

@test "judge_journal_legacy_untouched: the S2 subcommands keep their signatures and exit codes" {
  run --separate-stderr bash "$RESULT" check --generator-model a --reviewer-model a
  [ "$status" -eq 2 ]
  assert_substring "$stderr" "same_model"
  run --separate-stderr bash "$RESULT" check --generator-model a --reviewer-model b
  [ "$status" -eq 0 ]
  _record_review APPROVED 1 "$(_issues 0)"
  assert_grep -q '"reviewer_provenance":"claimed"' "$JSONL"
  # The new positional <topic> must not widen the S2 record: a stray positional
  # there is still a usage error, not a second way to name the topic.
  run --separate-stderr bash "$RESULT" record --topic demo --attempt 1 --input - --mb "$BANK" \
    --generator-model gen-x --reviewer-model rev-x --reviewer-agent mb-reviewer \
    --thinking medium stray < /dev/null
  [ "$status" -eq 2 ]
  assert_substring "$stderr" "error=usage"
  # `--kind review` is refused rather than accepted as a second spelling of the
  # S2 record — two spellings of one write path is how the two drift apart.
  run --separate-stderr bash "$RESULT" record --kind review --mb "$BANK" demo
  [ "$status" -eq 2 ]
}

@test "judge_journal_bank_spaces: the whole round trip works with a space in the bank path" {
  assert_substring "$BANK" " "
  _record_review CHANGES_REQUESTED 1 "$(_issues 0)"
  bash "$RESULT" record --kind judge --decision NO_GO --judge-model judge-x --mb "$BANK" demo >/dev/null 2>&1 || true
  run --separate-stderr bash "$RESULT" status --mb "$BANK" demo
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output err=$stderr"; false; }
  [ "$output" = "spec_review=CHANGES_REQUESTED judge=NO_GO override=no" ]
}

@test "judge_journal_shellcheck: mb-sdd-review-result.sh is shellcheck (style) clean" {
  if ! command -v shellcheck >/dev/null 2>&1; then skip "shellcheck not installed"; fi
  run shellcheck -S style "$RESULT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
