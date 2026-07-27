#!/usr/bin/env bats
# spec_review: — svp-sdd-core C5 spec-review config + executable verdict owner
# (references/pipeline.default.yaml sdd.spec_review, mb-pipeline-validate.sh,
# scripts/mb-sdd-review-result.sh; REQ-012, F-009).
#
# Name convention (X-05): every @test starts with `spec_review: `; the Eval
# red-anchor `not ok [0-9]+ .*(same_model|jsonl_append)` is carried by the
# same_model and jsonl_append cases.

bats_require_minimum_version 1.5.0

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  VALIDATE="$REPO_ROOT/scripts/mb-pipeline-validate.sh"
  RESULT="$REPO_ROOT/scripts/mb-sdd-review-result.sh"
  DEFAULT_CFG="$REPO_ROOT/references/pipeline.default.yaml"
  export LC_ALL=C
  TMP="$(mktemp -d)"
  BANK="$TMP/.memory-bank"
  mkdir -p "$BANK"
  # The bank's own roster: which review model this project sanctions. `record`
  # writes the reviewer identity into an append-only journal, so the model it
  # names has to be one the config actually authorises (AGR-034 [8]).
  _roster gpt-x
  # yaml stub that forces the PyYAML-optional fallback loader (import raises).
  STUB="$TMP/stub"; mkdir -p "$STUB"; printf 'raise ImportError("forced")\n' > "$STUB/yaml.py"
  # Mandatory identity flags for `record`, matching _review's reviewer block.
  ID="--generator-model gen --reviewer-model gpt-x --reviewer-agent mb-reviewer --thinking medium"
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

# _cfg_with <spec_review-inline-map>  → path to a config with that line.
_cfg_with() {
  local f="$TMP/pipeline.yaml"
  sed "s#^  spec_review:.*#  spec_review: $1#" "$DEFAULT_CFG" > "$f"
  printf '%s\n' "$f"
}

_review() { # <status> <verdict> <reason> — emit a valid reviewer JSON
  printf '{"status":"%s","verdict":%s,"reviewer":{"agent":"mb-reviewer","model":"gpt-x","thinking":"medium"},"issues":[],"reason":%s}' \
    "$1" "$2" "$3"
}

_roster() {  # <review-model> — the bank pipeline that sanctions it
  cat > "$BANK/pipeline.yaml" <<YAML
sdd:
  spec_review: {enabled: true, agent: mb-reviewer, model: $1, thinking: medium}
YAML
}

# ── the roster gate on the verdict writer (AGR-034 [8], judge B4) ────────────

@test "spec_review: a reviewer model outside the pipeline roster is not recorded at all" {
  # The other writer of this journal already refuses an unrostered model. Here
  # the identity was only ever checked against flags supplied by the SAME caller
  # and then stamped `reviewer_provenance: "claimed"` — so a verdict could name
  # a model the config never sanctioned, which is the fabricated-provenance
  # class AGR-034 [8] calls the worst of the three. Not flagged after the fact:
  # not written at all.
  run --separate-stderr bash -c "$(printf '%q ' "$RESULT") record --topic t --attempt 1 --input - --mb $(printf '%q' "$BANK") --generator-model gen --reviewer-model NOT-IN-ROSTER --reviewer-agent mb-reviewer --thinking medium <<'IN'
{\"status\":\"reviewed\",\"verdict\":\"APPROVED\",\"reviewer\":{\"agent\":\"mb-reviewer\",\"model\":\"NOT-IN-ROSTER\",\"thinking\":\"medium\"},\"issues\":[],\"reason\":null}
IN"
  [ "$status" -eq 2 ] || { echo "an unrostered reviewer model was recorded (rc=$status)"; false; }
  assert_substring "$stderr" "model_not_in_roster"
  refute_file "$BANK/tmp/spec-review/t.jsonl"
}

@test "spec_review: the sanctioned reviewer model still records — the gate is conditional" {
  # Positive control: without it, "always refuse" would satisfy the test above.
  run --separate-stderr bash -c "$(printf '%q ' "$RESULT") record --topic t --attempt 1 --input - --mb $(printf '%q' "$BANK") $ID <<'IN'
$(_review reviewed '"APPROVED"' null)
IN"
  [ "$status" -eq 0 ] || { echo "the rostered model was refused (rc=$status): $stderr"; false; }
  assert_grep -q '"model":"gpt-x"' "$BANK/tmp/spec-review/t.jsonl"
}

# ── config validation ────────────────────────────────────────────────────────

@test "spec_review: valid inline-map config is accepted" {
  local f; f="$(_cfg_with '{enabled: false, agent: mb-reviewer, model: inherit, thinking: medium}')"
  run bash "$VALIDATE" "$f"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "spec_review: a value containing a comma is rejected" {
  local f; f="$(_cfg_with '{enabled: false, agent: mb-reviewer, model: a,b, thinking: medium}')"
  run bash "$VALIDATE" "$f"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "spec_review"
}

@test "spec_review: enabled true without model is rejected" {
  local f; f="$(_cfg_with '{enabled: true, agent: mb-reviewer, thinking: medium}')"
  run bash "$VALIDATE" "$f"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "model"
}

@test "spec_review: thinking outside low|medium|high is rejected" {
  local f; f="$(_cfg_with '{enabled: false, agent: mb-reviewer, model: inherit, thinking: extreme}')"
  run bash "$VALIDATE" "$f"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "thinking"
}

@test "spec_review: loader parity — valid config accepted with PyYAML forced off" {
  local f; f="$(_cfg_with '{enabled: false, agent: mb-reviewer, model: inherit, thinking: medium}')"
  PYTHONPATH="$STUB" run bash "$VALIDATE" "$f"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "spec_review: loader parity — comma value rejected with PyYAML forced off" {
  local f; f="$(_cfg_with '{enabled: false, agent: mb-reviewer, model: a,b, thinking: medium}')"
  PYTHONPATH="$STUB" run bash "$VALIDATE" "$f"
  [ "$status" -ne 0 ]
}

@test "spec_review: quoted comma+colon scalar rejected by BOTH loaders (major #10)" {
  local f; f="$(_cfg_with '{enabled: false, agent: mb-reviewer, model: "gpt,foo:bar", thinking: medium}')"
  run bash "$VALIDATE" "$f"; [ "$status" -ne 0 ]
  PYTHONPATH="$STUB" run bash "$VALIDATE" "$f"; [ "$status" -ne 0 ]
}

@test "spec_review: enabled true without thinking is rejected (major #10)" {
  local f; f="$(_cfg_with '{enabled: true, agent: mb-reviewer, model: m}')"
  run bash "$VALIDATE" "$f"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi thinking
}

@test "spec_review: nested block form is rejected — inline map required (major #10)" {
  # replace the inline map with a nested block; must be rejected by both loaders.
  local f="$TMP/nested.yaml"
  awk '
    /^  spec_review:/ {
      print "  spec_review:"; print "    enabled: false"; print "    agent: mb-reviewer";
      print "    model: inherit"; print "    thinking: medium"; skip=1; next
    }
    skip && /^ {40,}#/ { next }
    { skip=0; print }
  ' "$DEFAULT_CFG" > "$f"
  run bash "$VALIDATE" "$f"; [ "$status" -ne 0 ]
  PYTHONPATH="$STUB" run bash "$VALIDATE" "$f"; [ "$status" -ne 0 ]
}

# ── check (same_model gate before dispatch) ──────────────────────────────────

@test "spec_review: same_model rejected before dispatch, zero records (same_model)" {
  run --separate-stderr "$RESULT" check --generator-model gpt-x --reviewer-model gpt-x
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"same_model"* ]]
  [ ! -e "$BANK/tmp/spec-review" ]     # nothing written on same_model
}

@test "spec_review: distinct generator/reviewer models pass check" {
  run --separate-stderr "$RESULT" check --generator-model gen --reviewer-model rev
  [ "$status" -eq 0 ]
}

# ── record (verdict ownership + status transitions) ──────────────────────────

@test "spec_review: transition disabled → ready (config enabled false, no dispatch)" {
  # disabled means the review gate is off — readiness rests on C8 alone.
  local f; f="$(_cfg_with '{enabled: false, agent: mb-reviewer, model: inherit, thinking: medium}')"
  run bash "$VALIDATE" "$f"
  [ "$status" -eq 0 ]
  python3 - "$f" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
assert cfg["sdd"]["spec_review"]["enabled"] is False
PY
}

@test "spec_review: transition APPROVED → ready (record exit 0)" {
  run --separate-stderr bash -c "$(printf '%q ' "$RESULT") record --topic t --attempt 1 --input - --mb $(printf '%q' "$BANK") $ID <<'IN'
$(_review reviewed '"APPROVED"' null)
IN"
  [ "$status" -eq 0 ]
  [ -f "$BANK/tmp/spec-review/t.jsonl" ]
}

@test "spec_review: transition CHANGES_REQUESTED → draft (record exit 1)" {
  run --separate-stderr bash -c "$(printf '%q ' "$RESULT") record --topic t --attempt 1 --input - --mb $(printf '%q' "$BANK") $ID <<'IN'
$(_review reviewed '"CHANGES_REQUESTED"' null)
IN"
  [ "$status" -eq 1 ]
}

@test "spec_review: transition SKIPPED-no-decision → draft (record exit 2, jsonl line + loud)" {
  run --separate-stderr bash -c "$(printf '%q ' "$RESULT") record --topic t --attempt 1 --input - --mb $(printf '%q' "$BANK") $ID <<'IN'
$(_review skipped null '"model unavailable"')
IN"
  [ "$status" -eq 2 ]
  [ -f "$BANK/tmp/spec-review/t.jsonl" ]
  [[ "$stderr" == *"SKIPPED"* ]]
}

@test "spec_review: malformed JSON is rejected with exit 2, no write" {
  run --separate-stderr bash -c "$(printf '%q ' "$RESULT") record --topic zz --attempt 1 --input - --mb $(printf '%q' "$BANK") $ID <<'IN'
not json
IN"
  [ "$status" -eq 2 ]
  [ ! -f "$BANK/tmp/spec-review/zz.jsonl" ]
}

@test "spec_review: record requires all identity flags → usage exit 2 (blocker #4)" {
  run --separate-stderr bash -c "$(printf '%q ' "$RESULT") record --topic t --attempt 1 --input - --mb $(printf '%q' "$BANK") <<'IN'
$(_review reviewed '"APPROVED"' null)
IN"
  [ "$status" -eq 2 ]
  [ ! -f "$BANK/tmp/spec-review/t.jsonl" ]
}

@test "spec_review: same_model rejected at record before any append → exit 2 (blocker #4)" {
  run --separate-stderr bash -c "$(printf '%q ' "$RESULT") record --topic t --attempt 1 --input - --mb $(printf '%q' "$BANK") --generator-model gpt-x --reviewer-model gpt-x --reviewer-agent mb-reviewer --thinking medium <<'IN'
$(_review reviewed '"APPROVED"' null)
IN"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"same_model"* ]]
  [ ! -f "$BANK/tmp/spec-review/t.jsonl" ]
}

@test "spec_review: reviewer JSON identity must match the dispatched IDs → exit 2 (blocker #4)" {
  # CLI claims agent=mb-reviewer/model=gpt-x, JSON carries a foreign identity.
  run --separate-stderr bash -c "$(printf '%q ' "$RESULT") record --topic t --attempt 1 --input - --mb $(printf '%q' "$BANK") $ID <<'IN'
{\"status\":\"reviewed\",\"verdict\":\"APPROVED\",\"reviewer\":{\"agent\":\"OTHER\",\"model\":\"OTHER\",\"thinking\":\"high\"},\"issues\":[],\"reason\":null}
IN"
  [ "$status" -eq 2 ]
  [ ! -f "$BANK/tmp/spec-review/t.jsonl" ]
}

@test "spec_review: topic path-traversal rejected → usage exit 2, no escaped write (blocker #9)" {
  run --separate-stderr bash -c "$(printf '%q ' "$RESULT") record --topic ../../../escaped-review --attempt 1 --input - --mb $(printf '%q' "$BANK") $ID <<'IN'
$(_review reviewed '"APPROVED"' null)
IN"
  [ "$status" -eq 2 ]
  [ ! -e "$TMP/escaped-review.jsonl" ]
}

@test "spec_review: two attempts append, history is not overwritten (jsonl_append)" {
  bash -c "$(printf '%q ' "$RESULT") record --topic t --attempt 1 --input - --mb $(printf '%q' "$BANK") $ID <<'IN'
$(_review reviewed '"CHANGES_REQUESTED"' null)
IN" || true
  bash -c "$(printf '%q ' "$RESULT") record --topic t --attempt 2 --input - --mb $(printf '%q' "$BANK") $ID <<'IN'
$(_review reviewed '"APPROVED"' null)
IN" || true
  local jsonl="$BANK/tmp/spec-review/t.jsonl"
  [ "$(wc -l < "$jsonl")" -eq 2 ]
  # last valid line is the current verdict (APPROVED, attempt 2).
  tail -1 "$jsonl" | grep -q '"verdict":"APPROVED"'
  tail -1 "$jsonl" | grep -q '"attempt":2'
  # attempt 1 (CHANGES_REQUESTED) is still present — not overwritten.
  head -1 "$jsonl" | grep -q '"verdict":"CHANGES_REQUESTED"'
}

# ── bank resolution, containment, provenance, secrets (S2 review [4][5][18][23]) ──

@test "spec_review: symlinked tmp/spec-review cannot redirect the JSONL outside the bank" {
  local victim="$TMP/victim"; mkdir -p "$victim"
  mkdir -p "$BANK/tmp"
  ln -s "$victim" "$BANK/tmp/spec-review"
  run --separate-stderr bash -c "$(printf '%q ' "$RESULT") record --topic t --attempt 1 --input - --mb $(printf '%q' "$BANK") $ID <<'IN'
$(_review reviewed '"APPROVED"' null)
IN"
  [ "$status" -eq 2 ]
  [ ! -e "$victim/t.jsonl" ]
}

@test "spec_review: record without --mb resolves the active bank instead of a hardcoded .memory-bank" {
  local proj="$TMP/proj"; mkdir -p "$proj"            # no local .memory-bank
  local gbank="$TMP/global-bank"; mkdir -p "$gbank"
  # The roster is read from the bank that actually resolves — which is the point
  # of this test, so the global bank carries the sanctioning pipeline. (A bank
  # with no pipeline inherits the bundled default, whose `model: inherit` names
  # no model and therefore sanctions none.)
  BANK="$gbank" _roster gpt-x
  cd "$proj" || return 1
  MB_PATH="$gbank" run --separate-stderr bash -c "$(printf '%q ' "$RESULT") record --topic t --attempt 1 --input - $ID <<'IN'
$(_review reviewed '"APPROVED"' null)
IN"
  [ "$status" -eq 0 ]
  [ -f "$gbank/tmp/spec-review/t.jsonl" ]
  [ ! -e "$proj/.memory-bank" ]
}

@test "spec_review: reviewer identity is recorded as caller-claimed, never as verified provenance" {
  run --separate-stderr bash -c "$(printf '%q ' "$RESULT") record --topic t --attempt 1 --input - --mb $(printf '%q' "$BANK") $ID <<'IN'
$(_review reviewed '"APPROVED"' null)
IN"
  [ "$status" -eq 0 ]
  local jsonl="$BANK/tmp/spec-review/t.jsonl"
  grep -q '"reviewer_provenance":"claimed"' "$jsonl"
}

@test "spec_review: a reviewer payload carrying a secret is refused, nothing durable is written" {
  run --separate-stderr bash -c "$(printf '%q ' "$RESULT") record --topic t --attempt 1 --input - --mb $(printf '%q' "$BANK") $ID <<'IN'
{\"status\":\"reviewed\",\"verdict\":\"CHANGES_REQUESTED\",\"reviewer\":{\"agent\":\"mb-reviewer\",\"model\":\"gpt-x\",\"thinking\":\"medium\"},\"issues\":[],\"reason\":\"leaked sk-live0123456789abcdef in config\"}
IN"
  [ "$status" -eq 2 ]
  [ ! -f "$BANK/tmp/spec-review/t.jsonl" ]
  [[ "$stderr" == *"secret"* ]]
}

@test "spec_review: a clean reviewer payload is unaffected by the secret gate" {
  run --separate-stderr bash -c "$(printf '%q ' "$RESULT") record --topic t --attempt 1 --input - --mb $(printf '%q' "$BANK") $ID <<'IN'
{\"status\":\"reviewed\",\"verdict\":\"CHANGES_REQUESTED\",\"reviewer\":{\"agent\":\"mb-reviewer\",\"model\":\"gpt-x\",\"thinking\":\"medium\"},\"issues\":[],\"reason\":\"missing error handling in the parser\"}
IN"
  [ "$status" -eq 1 ]
  [ -f "$BANK/tmp/spec-review/t.jsonl" ]
}

@test "spec_review: shellcheck (style) clean" {
  if ! command -v shellcheck >/dev/null 2>&1; then skip "shellcheck not installed"; fi
  run shellcheck -S style "$RESULT"
  [ "$status" -eq 0 ]
}

# ─── the payload is never spilled unscanned (r3 review [7]) ────────────────

@test "spec_review: a credential payload is blocked and never written to a temp file" {
  # The old code wrote RAW to mktemp, scanned, then rm'd. A crash in that window
  # left the credential readable in /tmp. Proven structurally (the writer must
  # not create an unscanned file) and behaviourally (still blocked).
  ! grep -Eq 'printf .*RAW.* > "\$SCAN_TMP"' "$REPO_ROOT/scripts/mb-sdd-review-result.sh" \
    || { echo "review-result still spills the payload before scanning"; false; }
  grep -Eq 'printf .%s. "\$RAW" \| bash "\$SECRET_SCAN" --policy transcript -' \
    "$REPO_ROOT/scripts/mb-sdd-review-result.sh" \
    || { echo "review-result does not stream to the scanner"; false; }
}

@test "spec_review: the secret gate still refuses a credential-bearing payload" {
  # Same documented call shape as the transition tests, with a credential in the
  # reviewer JSON: the streamed scan must still refuse it before any JSONL write.
  run --separate-stderr bash -c "$(printf '%q ' "$RESULT") record --topic t --attempt 1 --input - --mb $(printf '%q' "$BANK") $ID <<'IN'
$(_review reviewed '"APPROVED"' null | sed 's/}$/,"leak":"sk-ant-api03ABCDEFGHIJKLMNOP"}/')
IN"
  [ "$status" -eq 2 ] || { echo "credential payload was accepted (rc=$status): $stderr"; false; }
  echo "$stderr" | grep -q 'secret_blocked' \
    || { echo "not refused by the secret gate: $stderr"; false; }
  [ ! -f "$BANK/tmp/spec-review/t.jsonl" ] \
    || { echo "a credential-bearing record reached the durable JSONL"; false; }
}
