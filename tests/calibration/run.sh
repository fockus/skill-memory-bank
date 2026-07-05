#!/usr/bin/env bash
# tests/calibration/run.sh — golden calibration-suite runner (reviewer-2.0
# design.md §6 "Golden calibration suite", REQ-104/REQ-105). See
# tests/calibration/README.md for the full contract (schema, match metric,
# CI integration doc).
#
# Usage:
#   bash tests/calibration/run.sh                    # all cases, default mode
#   bash tests/calibration/run.sh --emit-payload      # payload-shape smoke test
#   bash tests/calibration/run.sh --stack=python      # filter by case.json:stack
#   bash tests/calibration/run.sh --case=PY-001       # filter by case id prefix
#   bash tests/calibration/run.sh --help
#
# --emit-payload (offline, load-bearing path -- exercised by
#   tests/bats/test_calibration_suite.bats): for each selected case, invokes
#   `scripts/mb-review.sh --emit-payload --input <case-dir> --mb <tmp-bank>`
#   to assemble the review payload the EXACT SAME deterministic way the real
#   /mb work review step does — NO reviewer dispatch, NO LLM, NO network —
#   then shape-checks the result: the 4 unconditional sections (## Plan
#   context / ## Diff / ## Calibration examples / ## Prior evidence) appear
#   in fixed order, the conditional ## Auto-generated findings (MUST
#   INCLUDE) section appears IFF the case's prior-tests.json has
#   tests_pass:false, and the Calibration examples section actually
#   resolved real examples (not the loader's empty/degraded placeholder). A
#   per-case temp bank carries a rules-profile.json pinning the case's own
#   `stack` so the layered examples loader (scripts/mb-review-examples.sh)
#   resolves that stack's baseline, not just `common`.
#
# Default mode (no --emit-payload): per design.md §6 this dispatches a live
#   reviewer and applies the full match metric (verdict + count bounds +
#   must_have/must_not_have categories + example-ref WARN). This runner
#   NEVER fakes an LLM call. When a case ships an optional, clearly-labelled
#   <case>/verdict.sample.json, default mode treats it as an OFFLINE
#   SELF-TEST sample (not a live verdict) and runs the real match-metric
#   logic against it end to end — useful to exercise the metric itself
#   without a reviewer. Cases without a sample are reported SKIP: "reviewer
#   dispatch is host-driven -- run under the scheduled workflow" (see
#   README.md's documented, not-yet-added, calibration.yml).
#
# Results: every run writes tests/calibration/results/<UTC-timestamp>_run.json
#   (gitignored). stdout carries only the deterministic PASS/WARN/FAIL/SKIP
#   table + summary — no timestamps — so `--emit-payload` output is
#   byte-identical across repeated runs.
#
# Exit codes:
#   0  every selected case PASSed (SKIP does not count as a failure)
#   1  >=1 WARN, no FAIL
#   2  >=1 FAIL, OR a usage error, OR no case matched the given filter(s)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CASES_DIR="$SCRIPT_DIR/cases"
RESULTS_DIR="$SCRIPT_DIR/results"
REVIEW_SH="$REPO_ROOT/scripts/mb-review.sh"

usage() {
  sed -n '2,48p' "$0" | sed 's/^# \{0,1\}//'
}

EMIT_PAYLOAD=0
STACK_FILTER=""
CASE_FILTER=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --emit-payload) EMIT_PAYLOAD=1; shift ;;
    --stack=*) STACK_FILTER="${1#--stack=}"; shift ;;
    --case=*) CASE_FILTER="${1#--case=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[calibration] unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done

if [ ! -d "$CASES_DIR" ]; then
  echo "[calibration] no cases directory at $CASES_DIR" >&2
  exit 2
fi

mkdir -p "$RESULTS_DIR"
SCRATCH_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/mb-calibration.XXXXXX")
trap 'rm -rf "$SCRATCH_ROOT"' EXIT
ROWS_FILE="$SCRATCH_ROOT/rows.jsonl"
: >"$ROWS_FILE"

# ---- case.json helpers (python3 -- consistent with the rest of the skill) --

case_field() {
  # $1 = case.json path  $2 = top-level string field name
  python3 -c '
import json, sys


def resolve():
    try:
        with open(sys.argv[1], encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        return ""
    val = data.get(sys.argv[2], "")
    return val if isinstance(val, str) else ""


print(resolve())
' "$1" "$2"
}

case_expected_json() {
  # $1 = case.json path -- dumps the whole document as one compact JSON line.
  python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    print(json.dumps(json.load(fh)))
' "$1"
}

prior_tests_pass() {
  # $1 = prior-tests.json path -> "0" (green/missing) or "1" (tests_pass:false)
  python3 -c '
import json, sys


def resolve():
    try:
        with open(sys.argv[1], encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        return "0"
    return "1" if data.get("tests_pass") is False else "0"


print(resolve())
' "$1"
}

list_cases() {
  local d id stack
  while IFS= read -r d; do
    [ -d "$d" ] || continue
    id="$(basename "$d")"
    if [ -n "$CASE_FILTER" ]; then
      case "$id" in
        "$CASE_FILTER"*) : ;;
        *) continue ;;
      esac
    fi
    if [ -n "$STACK_FILTER" ]; then
      stack="$(case_field "$d/case.json" stack)"
      [ "$stack" = "$STACK_FILTER" ] || continue
    fi
    printf '%s\n' "$d"
  done < <(find "$CASES_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
}

# ---- --emit-payload mode: shape-check (design.md §6 step 3, no LLM) --------

shape_check() {
  # $1 = payload file  $2 = expect-red (0/1)  $3 = expected_example_refs CSV
  PAYLOAD_FILE="$1" EXPECT_RED="$2" EXPECTED_REFS="$3" python3 -c '
import os

HEADERS = [
    "## Plan context",
    "## Diff",
    "## Calibration examples (reference patterns — not part of current diff)",
    "## Prior evidence (from mb-test-runner)",
]
AUTO_HEADER = "## Auto-generated findings (MUST INCLUDE)"


def find(lines, header):
    for i, line in enumerate(lines):
        if line == header:
            return i
    return None


def check():
    payload_file = os.environ["PAYLOAD_FILE"]
    expect_red = os.environ["EXPECT_RED"] == "1"
    refs_csv = os.environ.get("EXPECTED_REFS", "")
    expected_refs = [r for r in refs_csv.split(",") if r]
    lines = open(payload_file, encoding="utf-8").read().splitlines()

    positions = [find(lines, h) for h in HEADERS]
    if any(p is None for p in positions):
        return "FAIL\tmissing required section(s)"
    if positions != sorted(positions):
        return "FAIL\tsections out of fixed order"

    auto_pos = find(lines, AUTO_HEADER)
    has_auto = auto_pos is not None
    if has_auto and auto_pos < positions[-1]:
        return "FAIL\tauto-generated findings section precedes prior evidence"
    if expect_red and not has_auto:
        return "FAIL\ttests_pass:false but no Auto-generated findings section rendered"
    if not expect_red and has_auto:
        return "FAIL\tgreen-tests case unexpectedly rendered an Auto-generated findings section"

    examples_body = "\n".join(lines[positions[2] + 1 : positions[3]]).strip()
    degraded = ("(no calibration examples available)", "(examples loader unavailable)")
    if not examples_body or any(marker in examples_body for marker in degraded):
        return "FAIL\tcalibration examples did not load (empty/degraded placeholder)"

    missing = [r for r in expected_refs if f"### {r} (" not in examples_body]
    if missing:
        return f"WARN\texpected example ref(s) not present in rendered examples: {missing}"

    return "PASS\tall shape checks satisfied; examples loaded"


print(check())
'
}

run_case_emit_payload() {
  local case_dir="$1" id bank payload_file expect_red refs status reason
  id="$(basename "$case_dir")"
  bank="$SCRATCH_ROOT/bank-$id"
  mkdir -p "$bank"
  printf '{"stack": "%s"}\n' "$(case_field "$case_dir/case.json" stack)" >"$bank/rules-profile.json"

  payload_file="$SCRATCH_ROOT/payload-$id.md"
  if ! bash "$REVIEW_SH" --emit-payload --input "$case_dir" --mb "$bank" >"$payload_file" 2>"$SCRATCH_ROOT/err-$id.log"; then
    status="FAIL"; reason="mb-review.sh --emit-payload exited non-zero (see $SCRATCH_ROOT/err-$id.log)"
  else
    expect_red="$(prior_tests_pass "$case_dir/prior-tests.json")"
    refs="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(",".join(d.get("expected",{}).get("expected_example_refs",[])))' "$case_dir/case.json" 2>/dev/null || true)"
    IFS=$'\t' read -r status reason <<<"$(shape_check "$payload_file" "$expect_red" "$refs")"
  fi
  report_row "$id" "emit-payload" "$status" "$reason"
}

# ---- default mode: full match metric (design.md §6 "Match metric") --------

match_metric() {
  # $1 = case.json path  $2 = actual-verdict JSON path
  EXPECTED_JSON="$(case_expected_json "$1")" ACTUAL_FILE="$2" python3 -c '
import json, os


def evaluate():
    expected = json.loads(os.environ["EXPECTED_JSON"])["expected"]
    with open(os.environ["ACTUAL_FILE"], encoding="utf-8") as fh:
        actual = json.load(fh)

    verdict_ok = actual.get("verdict") == expected["verdict"]
    counts = actual.get("counts", {})
    blocker, major, minor = counts.get("blocker", 0), counts.get("major", 0), counts.get("minor", 0)
    counts_ok = (
        expected["counts"]["blocker_min"] <= blocker <= expected["counts"]["blocker_max"]
        and major <= expected["counts"]["major_max"]
        and minor <= expected["counts"]["minor_max"]
    )

    issues = actual.get("issues", [])
    actual_categories = {i.get("category") for i in issues}
    must_have = set(expected.get("must_have_categories", []))
    must_not_have = set(expected.get("must_not_have_categories", []))
    categories_ok = must_have <= actual_categories and not (must_not_have & actual_categories)

    if not (verdict_ok and counts_ok and categories_ok):
        actual_verdict = actual.get("verdict")
        expected_verdict = expected["verdict"]
        reasons = []
        if not verdict_ok:
            reasons.append(f"verdict {actual_verdict!r} != expected {expected_verdict!r}")
        if not counts_ok:
            reasons.append(f"counts out of bounds (blocker={blocker} major={major} minor={minor})")
        if not categories_ok:
            reasons.append(
                f"category mismatch: missing={sorted(must_have - actual_categories)} "
                f"forbidden={sorted(must_not_have & actual_categories)}"
            )
        return "FAIL\t" + "; ".join(reasons)

    expected_refs = set(expected.get("expected_example_refs", []))
    actual_refs = {i.get("referenced_example_id") for i in issues if i.get("referenced_example_id")}
    if expected_refs and not (expected_refs <= actual_refs):
        return f"WARN\texample refs not attributed: expected={sorted(expected_refs)} got={sorted(actual_refs)}"

    return "PASS\tverdict/counts/categories match; examples attributed"


print(evaluate())
'
}

run_case_default() {
  local case_dir="$1" id sample status reason
  id="$(basename "$case_dir")"
  sample="$case_dir/verdict.sample.json"
  if [ -f "$sample" ]; then
    IFS=$'\t' read -r status reason <<<"$(match_metric "$case_dir/case.json" "$sample")"
    reason="(self-test sample) $reason"
  else
    status="SKIP"
    reason="reviewer dispatch is host-driven; run under the scheduled workflow (see README.md)"
  fi
  report_row "$id" "default" "$status" "$reason"
}

# ---- reporting --------------------------------------------------------

PASS_N=0; WARN_N=0; FAIL_N=0; SKIP_N=0

report_row() {
  local id="$1" mode="$2" status="$3" reason="$4"
  case "$status" in
    PASS) PASS_N=$((PASS_N + 1)) ;;
    WARN) WARN_N=$((WARN_N + 1)) ;;
    FAIL) FAIL_N=$((FAIL_N + 1)) ;;
    *) SKIP_N=$((SKIP_N + 1)); status="SKIP" ;;
  esac
  printf '%-24s %-13s %-6s %s\n' "$id" "$mode" "$status" "$reason"
  ROWS_FILE="$ROWS_FILE" ID="$id" MODE="$mode" STATUS="$status" REASON="$reason" python3 -c '
import json, os
row = {"case_id": os.environ["ID"], "mode": os.environ["MODE"], "status": os.environ["STATUS"], "reason": os.environ["REASON"]}
with open(os.environ["ROWS_FILE"], "a", encoding="utf-8") as fh:
    fh.write(json.dumps(row) + "\n")
'
}

CASE_COUNT=0
printf '%-24s %-13s %-6s %s\n' "CASE" "MODE" "STATUS" "REASON"
while IFS= read -r case_dir; do
  CASE_COUNT=$((CASE_COUNT + 1))
  if [ "$EMIT_PAYLOAD" -eq 1 ]; then
    run_case_emit_payload "$case_dir"
  else
    run_case_default "$case_dir"
  fi
done < <(list_cases)

if [ "$CASE_COUNT" -eq 0 ]; then
  echo "[calibration] no case matched --stack=$STACK_FILTER --case=$CASE_FILTER" >&2
  exit 2
fi

printf '\n%d case(s): %d PASS, %d WARN, %d FAIL, %d SKIP\n' "$CASE_COUNT" "$PASS_N" "$WARN_N" "$FAIL_N" "$SKIP_N"

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
RESULTS_FILE="$RESULTS_DIR/${TIMESTAMP}_run.json"
MODE_LABEL="default"; [ "$EMIT_PAYLOAD" -eq 1 ] && MODE_LABEL="emit-payload"
ROWS_FILE="$ROWS_FILE" MODE_LABEL="$MODE_LABEL" TIMESTAMP="$TIMESTAMP" \
  PASS_N="$PASS_N" WARN_N="$WARN_N" FAIL_N="$FAIL_N" SKIP_N="$SKIP_N" \
  python3 -c '
import json, os

rows = []
with open(os.environ["ROWS_FILE"], encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if line:
            rows.append(json.loads(line))

result = {
    "generated_at": os.environ["TIMESTAMP"],
    "mode": os.environ["MODE_LABEL"],
    "summary": {
        "pass": int(os.environ["PASS_N"]),
        "warn": int(os.environ["WARN_N"]),
        "fail": int(os.environ["FAIL_N"]),
        "skip": int(os.environ["SKIP_N"]),
    },
    "cases": rows,
}
print(json.dumps(result, indent=2, ensure_ascii=False))
' >"$RESULTS_FILE"
echo "[calibration] results written to $RESULTS_FILE" >&2

if [ "$FAIL_N" -gt 0 ]; then
  exit 2
elif [ "$WARN_N" -gt 0 ]; then
  exit 1
fi
exit 0
