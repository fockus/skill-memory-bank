#!/usr/bin/env bats
# mb-team Stage 6 (T-ENGINE, AGR-097): optional `medium` severity in the
# review parser, the severity gate and the lead-reviewer schema.
#
# A gate that declares `medium` enforces it; a gate without it is a
# three-level gate: medium findings count toward `minor` (what the external
# parser always did with them), so existing configs keep their verdicts.

load lib/assert

BASELINE=f050443e9d7c70eadf78cc8f1f5b72e6b01888f8

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PARSE="$REPO_ROOT/scripts/mb-work-review-parse.sh"
  GATE="$REPO_ROOT/scripts/mb-work-severity-gate.sh"
  export PATH="$REPO_ROOT/.venv/bin:${PATH}"
  MB="$BATS_TEST_TMPDIR/.memory-bank"
  mkdir -p "$MB"
  cp "$REPO_ROOT/references/pipeline.default.yaml" "$MB/pipeline.yaml"
  ONE_MEDIUM='{"verdict":"CHANGES_REQUESTED","counts":{"blocker":0,"major":0,"medium":1,"minor":0},"issues":[{"severity":"medium","category":"logic","file":"a.py","line":3,"message":"m"}]}'
}

# ── parser ────────────────────────────────────────────────────────────────

@test "parse: a medium issue is accepted and counted" {
  run bash "$PARSE" <<<"$ONE_MEDIUM"
  [ "$status" -eq 0 ]
  [ "$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d["counts"]["medium"], d["issues"][0]["severity"])' "$output")" = "1 medium" ]
}

@test "parse: external mode keeps medium instead of folding it into minor" {
  run bash "$PARSE" --external <<<'{"verdict":"CHANGES_REQUESTED","issues":[{"severity":"medium","description":"d","file":"a.py","line":1}]}'
  [ "$status" -eq 0 ]
  assert_substring "$output" '"medium": 1'
  assert_substring "$output" '"minor": 0'
}

@test "parse: a non-integer medium count exits 1" {
  run bash "$PARSE" <<<'{"verdict":"APPROVED","counts":{"blocker":0,"major":0,"minor":0,"medium":"x"},"issues":[]}'
  [ "$status" -eq 1 ]
  assert_substring "$output" "counts.medium"
}

@test "parse: reports without medium are byte-identical to the baseline parser" {
  git -C "$REPO_ROOT" cat-file -e "$BASELINE^{commit}" 2>/dev/null || skip "baseline commit unavailable"
  OLD="$BATS_TEST_TMPDIR/old-parse.sh"
  git -C "$REPO_ROOT" show "$BASELINE:scripts/mb-work-review-parse.sh" > "$OLD"
  for report in \
    '{"verdict":"APPROVED","counts":{"blocker":0,"major":0,"minor":0},"issues":[]}' \
    '{"verdict":"CHANGES_REQUESTED","counts":{"blocker":1,"major":0,"minor":2},"issues":[{"severity":"blocker","category":"tests","file":"t.py","line":1,"message":"m"}]}' \
    '{"verdict":"APPROVED","issues":[{"severity":"info","description":"d"}]}'; do
    for mode in "" "--external" "--require-tests-blocker"; do
      # shellcheck disable=SC2086
      new=$(bash "$PARSE" $mode <<<"$report" 2>&1; echo "rc=$?")
      # shellcheck disable=SC2086
      old=$(bash "$OLD" $mode <<<"$report" 2>&1; echo "rc=$?")
      [ "$new" = "$old" ] || { echo "differs: $mode $report"; echo "old: $old"; echo "new: $new"; false; }
    done
  done
}

# ── gate ──────────────────────────────────────────────────────────────────

@test "gate: one medium fails a gate {medium: 0}" {
  run bash "$GATE" --counts "$ONE_MEDIUM" --gate '{"medium":0}' --mb "$MB"
  [ "$status" -eq 1 ]
  assert_substring "$output" "medium=1 > gate=0"
}

@test "gate: one medium passes the default gate of an existing pipeline" {
  run bash "$GATE" --counts "$ONE_MEDIUM" --mb "$MB"
  [ "$status" -eq 0 ]
}

@test "gate: without a medium limit, medium counts toward minor" {
  run bash "$GATE" --counts '{"blocker":0,"major":0,"medium":2,"minor":2}' --gate '{"minor":3}' --mb "$MB"
  [ "$status" -eq 1 ]
  assert_substring "$output" "minor=4"
  assert_substring "$output" "medium"
}

@test "gate: an absent medium count is 0 under a gate that declares medium" {
  run bash "$GATE" --counts '{"blocker":0,"major":0,"minor":0}' --gate '{"blocker":0,"major":0,"medium":0,"minor":0}' --mb "$MB"
  [ "$status" -eq 0 ]
}

@test "gate: a medium limit in pipeline.yaml review.severity_gate is enforced" {
  python3 - "$MB/pipeline.yaml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("    minor: 3\n", "    medium: 0\n    minor: 3\n", 1)
open(p, "w").write(s)
PY
  run bash "$GATE" --counts "$ONE_MEDIUM" --mb "$MB"
  [ "$status" -eq 1 ]
  assert_substring "$output" "medium=1 > gate=0"
}

@test "gate: old configs and old counts keep the baseline verdict and output" {
  git -C "$REPO_ROOT" cat-file -e "$BASELINE^{commit}" 2>/dev/null || skip "baseline commit unavailable"
  OLD="$BATS_TEST_TMPDIR/scripts"
  mkdir -p "$OLD"
  cp -R "$REPO_ROOT/scripts/." "$OLD/"
  git -C "$REPO_ROOT" show "$BASELINE:scripts/mb-work-severity-gate.sh" > "$OLD/mb-work-severity-gate.sh"
  for counts in '{"blocker":0,"major":0,"minor":2}' '{"blocker":0,"major":1,"minor":0}' \
      '{"blocker":0,"major":0,"minor":4}' '{"verdict":"APPROVED","counts":{"blocker":0,"major":0,"minor":0}}'; do
    for gate in '' '{"blocker":0,"major":0,"minor":3}' '{"minor":1}'; do
      flags=()
      [ -z "$gate" ] || flags=(--gate "$gate")
      new=$(bash "$GATE" --counts "$counts" --mb "$MB" "${flags[@]}" 2>&1; echo "rc=$?")
      old=$(bash "$OLD/mb-work-severity-gate.sh" --counts "$counts" --mb "$MB" "${flags[@]}" 2>&1; echo "rc=$?")
      [ "$new" = "$old" ] || { echo "differs: $counts $gate"; echo "old: $old"; echo "new: $new"; false; }
    done
  done
}

@test "gate: a non-integer medium count exits 2" {
  run bash "$GATE" --counts '{"blocker":0,"major":0,"minor":0,"medium":"x"}' --mb "$MB"
  [ "$status" -eq 2 ]
}

# ── lead schema ───────────────────────────────────────────────────────────

@test "lead and lens reviewer schemas name medium as optional" {
  run grep -c 'medium' "$REPO_ROOT/agents/mb-reviewer-lead.md"
  [ "$output" -ge 2 ]
  for lens in logic tests quality security scalability; do
    # shellcheck disable=SC2016
    grep -q '`medium`' "$REPO_ROOT/agents/mb-reviewer-$lens.md" || { echo "no medium in $lens"; false; }
  done
}
