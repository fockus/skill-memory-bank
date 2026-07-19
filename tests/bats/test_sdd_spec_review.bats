#!/usr/bin/env bats
# spec_review: — svp-sdd-core C5 spec-review config + executable verdict owner
# (references/pipeline.default.yaml sdd.spec_review, mb-pipeline-validate.sh,
# scripts/mb-sdd-review-result.sh; REQ-012, F-009).
#
# Name convention (X-05): every @test starts with `spec_review: `; the Eval
# red-anchor `not ok [0-9]+ .*(same_model|jsonl_append)` is carried by the
# same_model and jsonl_append cases.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  VALIDATE="$REPO_ROOT/scripts/mb-pipeline-validate.sh"
  RESULT="$REPO_ROOT/scripts/mb-sdd-review-result.sh"
  DEFAULT_CFG="$REPO_ROOT/references/pipeline.default.yaml"
  export LC_ALL=C
  TMP="$(mktemp -d)"
  BANK="$TMP/.memory-bank"
  mkdir -p "$BANK"
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

@test "spec_review: shellcheck (style) clean" {
  if ! command -v shellcheck >/dev/null 2>&1; then skip "shellcheck not installed"; fi
  run shellcheck -S style "$RESULT"
  [ "$status" -eq 0 ]
}
