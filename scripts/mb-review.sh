#!/usr/bin/env bash
# mb-review.sh — deterministic review-payload orchestrator (reviewer-2.0,
# design.md §2 "Architecture overview" + §7 "Reviewer agent — simplified
# prompt contract"). This is the review ENTRY POINT: it owns deterministic
# concerns (touched-file discovery, sha hashing, test-cache resolution,
# payload assembly) so the reviewer agent (whichever model pipeline.yaml
# names — codex-cli, mb-reviewer, or an adversarial-verify ensemble branch)
# only has to judge a single pre-assembled markdown payload. It never
# dispatches a reviewer itself and never touches the network/an LLM.
#
# Usage:
#   mb-review.sh --emit-payload [--input <case-dir>] [--mb <path>]
#                [--plan <path>] [--item <N>] [--run-id <id>]
#                [--refresh-tests] [--ttl <seconds>]
#   mb-review.sh --help
#
# Only --emit-payload is implemented in this reviewer-2.0 stage (payload
# assembly + cache resolution + the calibration-examples loader, see
# scripts/mb-review-examples.sh). Reviewer dispatch/post-validation are
# wired by later reviewer-2.0 tasks on top of this same entry point.
#
# --input <case-dir>  Reads diff/touched-files/prior-test-evidence from a
#                      calibration case directory instead of git/
#                      <mb>/tmp/last-tests.json — case.json (optional,
#                      description-only), files-touched.txt, diff.patch,
#                      prior-tests.json. Used by tests/calibration/run.sh so
#                      the golden suite exercises the exact production code
#                      path (design.md §6).
#
# --plan <path> --item <N>   Real-path-only. Renders "## Plan context" from
#                      the plan/spec item body (via mb_work_items.py) instead
#                      of a placeholder. Both omitted -> a documented
#                      placeholder is rendered (never a crash).
#
# --run-id <id>        Real-path-only. When given (or MB_WORK_RUN_ID is set)
#                      and scripts/mb-work-diff.sh is present, touched-files/
#                      diff resolution delegates to it — the SAME
#                      run-scoped, single-ref `git diff <baseline_ref>` the
#                      /mb work loop already uses for verify/review (see
#                      commands/work.md step 5c/5d), so a co-running
#                      parallel run's edits never leak into this payload.
#                      Without a run-id, baseline resolution falls back to
#                      the active plan's `baseline_commit` frontmatter (or
#                      --plan's), then HEAD~1, then no baseline at all —
#                      always fail-safe, never a crash.
#
# --refresh-tests       Clears the test-evidence cache before checking it —
#                       forces a MISS this run (design.md §5 "Force-refresh").
#
# --ttl <seconds>       Overrides the test-cache TTL for this run (otherwise
#                       pipeline.yaml:test_cache_ttl_sec, default 600 — see
#                       scripts/mb-review-cache.sh).
#
# Payload — 5 markdown sections in this fixed order (design.md §7):
#   ## Plan context
#   ## Diff
#   ## Calibration examples (reference patterns — not part of current diff)
#   ## Prior evidence (from mb-test-runner)
#   ## Auto-generated findings (MUST INCLUDE)   -- only when tests_pass==false
#
# The calibration-examples section is rendered by the layered loader in
# scripts/mb-review-examples.sh (design.md §4) via render_examples_section().
#
# Exit codes:
#   0  success (payload printed to stdout)
#   2  usage error (unknown flag, or no --emit-payload/--help given)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

CACHE_SH="$SCRIPT_DIR/mb-review-cache.sh"
WORK_DIFF_SH="$SCRIPT_DIR/mb-work-diff.sh"
WORK_RESOLVE_SH="$SCRIPT_DIR/mb-work-resolve.sh"
PIPELINE_SH="$SCRIPT_DIR/mb-pipeline.sh"
EXAMPLES_SH="${MB_REVIEW_EXAMPLES_SH:-$SCRIPT_DIR/mb-review-examples.sh}"

usage_short() {
  echo "Usage: mb-review.sh --emit-payload [--input <case-dir>] [--mb <path>] [--plan <path>] [--item <N>] [--run-id <id>] [--refresh-tests] [--ttl <seconds>]" >&2
}

# ---- section renderers ------------------------------------------------------

# Real-path "## Plan context": renders the plan/spec item body via the
# existing mb_work_items.py parser (single source of truth for stage/task
# marker parsing — no second implementation here). Fail-safe: a missing
# plan/item degrades to a documented placeholder, never a crash.
render_real_plan_context() {
  local plan="$1" item="$2"
  if [ -z "$plan" ] || [ -z "$item" ]; then
    printf '## Plan context\n\n(no plan context provided -- pass --plan <path> --item <N>)\n'
    return 0
  fi
  SCRIPT_DIR="$SCRIPT_DIR" PLAN_PATH="$plan" ITEM_NO="$item" python3 - <<'PY'
import os
import pathlib
import sys

sys.path.insert(0, os.environ["SCRIPT_DIR"])

print("## Plan context")
print()

plan_path = pathlib.Path(os.environ["PLAN_PATH"])
item_no = os.environ["ITEM_NO"]

if not plan_path.is_file():
    print(f"(plan file not found: {plan_path})")
    raise SystemExit(0)

try:
    import mb_work_items
except Exception as exc:
    print(f"(failed to load plan-item parser: {exc})")
    raise SystemExit(0)

try:
    items = mb_work_items.parse_work_items(plan_path)
except Exception as exc:
    print(f"(failed to parse plan context: {exc})")
    raise SystemExit(0)

match = next((i for i in items if str(i.item_no) == str(item_no)), None)
if match is None:
    print(f"(item {item_no} not found in {plan_path})")
    raise SystemExit(0)

print(f"Plan: {plan_path}")
print(f"Item: {match.item_no} -- {match.heading}")
print()
print(match.body)
PY
}

# --input-path "## Plan context": derived from the calibration case's
# case.json (case_id + description) when present, else just the dir name.
render_input_plan_context() {
  local case_dir="$1"
  CASE_DIR="$case_dir" python3 - <<'PY'
import json
import os
import pathlib

case_dir = pathlib.Path(os.environ["CASE_DIR"])
case_json = case_dir / "case.json"

print("## Plan context")
print()

if not case_json.is_file():
    print(f"Case: {case_dir.name}")
    raise SystemExit(0)

try:
    data = json.loads(case_json.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"(failed to parse {case_json}: {exc})")
    raise SystemExit(0)

print(f"Case: {data.get('case_id', case_dir.name)}")
if data.get("description"):
    print(data["description"])
PY
}

render_diff_section() {
  local diff_text="$1"
  echo "## Diff"
  echo
  if [ -n "$diff_text" ]; then
    printf '%s\n' "$diff_text"
  else
    echo "(no diff available)"
  fi
}

# Delegates to the layered rubric-examples loader (design.md §4); $BANK/
# $RUN_ID come from the "gather sections" block below. Fail-safe like the
# other delegates here: a loader/python3 failure degrades to an empty section.
render_examples_section() {
  local out
  out=$(bash "$EXAMPLES_SH" render --mb "$BANK" --run-id "$RUN_ID" 2>/dev/null) || out=""
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
  else
    printf '## Calibration examples (reference patterns — not part of current diff)\n\n(examples loader unavailable)\n'
  fi
}

# Renders "## Prior evidence" (always) and, only when the resolved evidence
# says tests_pass == false, an immediately-following "## Auto-generated
# findings (MUST INCLUDE)" section (design.md §5 step 4). `reason` documents
# why there is no evidence when `json` is empty (real-mode cache MISS vs.
# --input mode missing prior-tests.json) so the rendered placeholder text
# stays accurate for both callers.
render_prior_and_findings() {
  local reason="$1" json="$2"
  PRIOR_REASON="$reason" PRIOR_JSON="$json" python3 - <<'PY'
import json
import os

reason = os.environ["PRIOR_REASON"]
raw = os.environ.get("PRIOR_JSON", "")

print("## Prior evidence (from mb-test-runner)")
print()

data = None
if raw:
    try:
        data = json.loads(raw)
    except Exception:
        data = None

if data is None:
    if reason == "input-missing":
        print("(no prior-tests.json in case dir)")
    else:
        print("(no cached test evidence -- cache MISS; dispatch mb-test-runner and re-run)")
    raise SystemExit(0)

print(f"run_id: {data.get('run_id', '')}")
print(f"stack_detected: {data.get('stack_detected', 'unknown')}")
tests_pass = data.get("tests_pass")
print(f"tests_pass: {tests_pass}")
counts = data.get("counts") or {}
print(
    "counts: passed={} failed={} skipped={}".format(
        counts.get("passed", 0), counts.get("failed", 0), counts.get("skipped", 0)
    )
)
coverage = data.get("coverage") or {}
if coverage:
    print(
        "coverage: overall={} touched={}".format(
            coverage.get("overall", "n/a"), coverage.get("touched", "n/a")
        )
    )
print(f"elapsed_sec: {data.get('elapsed_sec', 0)}")
failures = data.get("failures") or []
if failures:
    print("failures (top 5):")
    for item in failures[:5]:
        print(f"- {item}")

if tests_pass is False:
    finding = {
        "severity": "blocker",
        "category": "tests",
        "auto_generated": True,
        "message": "{} failing tests on touched files (see failures[])".format(
            counts.get("failed", 0)
        ),
        "details": failures[:5],
    }
    print()
    print("## Auto-generated findings (MUST INCLUDE)")
    print()
    print(json.dumps(finding, indent=2, ensure_ascii=False))
PY
}

# ---- input helpers (--input <case-dir> mode) --------------------------------
#
# Note: cases/<id>/files-touched.txt (design.md §6) is NOT read here. --input
# mode bypasses touched_sha/TTL cache resolution entirely (prior-tests.json is
# read verbatim, unconditionally — design.md §6 step 2), so there is no
# functional consumer for a touched-file list in this mode; a future task
# that needs it (e.g. a calibration match-metric) reads it directly.

read_input_diff() {
  local case_dir="$1"
  local f="$case_dir/diff.patch"
  [ -f "$f" ] && cat "$f" || true
}

read_input_prior() {
  local case_dir="$1"
  local f="$case_dir/prior-tests.json"
  [ -f "$f" ] && cat "$f" || true
}

# ---- real-path helpers (git + .memory-bank/tmp/last-tests.json) ------------

# Hook point (design.md "Actualization 2026-07-05" — last-verdict cache):
# only the path convention + tmp dir existence is established in this task;
# work-loop-v2 (Phase 2) is what actually writes trend data here.
last_verdict_cache_path() {
  local bank="$1" item="$2"
  printf '%s/tmp/last-verdict-%s.json\n' "$bank" "$(mb_sanitize_topic "$item")"
}

# Baseline resolution (design.md §5 step 1, §12 open question 1): the active
# plan's `baseline_commit` frontmatter (or --plan's, if given) when it
# resolves to a real commit, else HEAD~1 when that resolves, else no baseline
# at all. Always fail-safe -- never a non-zero exit, never raw git noise.
resolve_baseline_ref() {
  local bank="$1" plan_arg="$2" plan_path baseline

  plan_path="$plan_arg"
  if [ -z "$plan_path" ]; then
    plan_path=$(bash "$WORK_RESOLVE_SH" --mb "$bank" 2>/dev/null || true)
  fi

  baseline=""
  if [ -n "$plan_path" ] && [ -f "$plan_path" ]; then
    baseline=$(FRONTMATTER_PATH="$plan_path" python3 - <<'PY'
import os
import re

path = os.environ["FRONTMATTER_PATH"]
try:
    text = open(path, encoding="utf-8").read()
except Exception:
    raise SystemExit(0)

m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
if not m:
    raise SystemExit(0)

mm = re.search(r"^baseline_commit:\s*(\S+)\s*$", m.group(1), re.M)
if mm:
    print(mm.group(1))
PY
)
  fi

  if [ -n "$baseline" ] && git rev-parse --verify --quiet "${baseline}^{commit}" >/dev/null 2>&1; then
    printf '%s\n' "$baseline"
    return 0
  fi

  if git rev-parse --verify --quiet "HEAD~1^{commit}" >/dev/null 2>&1; then
    printf '%s\n' "HEAD~1"
    return 0
  fi

  printf ''
}

# Touched-file discovery for the real path. When a run-id is available and
# mb-work-diff.sh exists, delegate to it -- it is the single-ref
# `git diff <baseline_ref>` the rest of /mb work already relies on
# (commands/work.md 5c/5d), scoped to THIS run's own baseline so a co-running
# parallel run's edits never leak in. Otherwise fall back to a plain baseline
# diff against the working tree. Fail-safe throughout: no git / not a repo /
# unreachable baseline all degrade to empty output, never a crash.
resolve_touched_files() {
  local bank="$1" run_id="$2" baseline="$3"
  if [ -n "$run_id" ] && [ -f "$WORK_DIFF_SH" ]; then
    bash "$WORK_DIFF_SH" --run-id "$run_id" --name-only --mb "$bank" 2>/dev/null || true
    return 0
  fi
  if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi
  if [ -n "$baseline" ]; then
    git diff --name-only "$baseline" 2>/dev/null || true
  else
    git diff --name-only 2>/dev/null || true
  fi
}

# Same resolution as resolve_touched_files, but the full diff text (no
# --name-only) for the "## Diff" section.
resolve_diff_text() {
  local bank="$1" run_id="$2" baseline="$3"
  if [ -n "$run_id" ] && [ -f "$WORK_DIFF_SH" ]; then
    bash "$WORK_DIFF_SH" --run-id "$run_id" --mb "$bank" 2>/dev/null || true
    return 0
  fi
  if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi
  if [ -n "$baseline" ]; then
    git diff "$baseline" 2>/dev/null || true
  else
    git diff 2>/dev/null || true
  fi
}

# pipeline.yaml:test_cache_ttl_sec, defaulting to 600 when absent/unreadable
# (mirrors scripts/mb-work-budget.sh's resolve_pipeline_defaults pattern).
resolve_ttl_default() {
  local mb_arg="$1" pipeline_path
  pipeline_path=$(bash "$PIPELINE_SH" path "$mb_arg" 2>/dev/null || true)
  if [ -z "$pipeline_path" ]; then
    pipeline_path="$SCRIPT_DIR/../references/pipeline.default.yaml"
  fi
  PIPELINE_YAML="$pipeline_path" python3 - <<'PY'
import os
try:
    import yaml
    cfg = yaml.safe_load(open(os.environ["PIPELINE_YAML"], encoding="utf-8")) or {}
    print(int(cfg.get("test_cache_ttl_sec", 600)))
except Exception:
    print(600)
PY
}

# ---- argument parsing --------------------------------------------------------

EMIT_PAYLOAD=0
INPUT_DIR=""
MB_ARG=""
PLAN_ARG=""
ITEM_ARG=""
RUN_ID_ARG=""
REFRESH_TESTS=0
TTL_ARG=""

# Guards against the bash "shift count out of range" crash when a
# value-taking flag is the LAST arg with no following value: without this,
# `shift 2` with $#==1 aborts the whole script under `set -euo pipefail`
# with a silent exit 1 -- never the script's own documented "exit 2 =
# usage/validation error" contract. Loud usage message to stderr + exit 2.
require_value() {
  [ "$#" -ge 2 ] || { echo "[review] $1 requires a value" >&2; usage_short; exit 2; }
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --emit-payload) EMIT_PAYLOAD=1; shift ;;
    --input) require_value "$@"; INPUT_DIR="$2"; shift 2 ;;
    --input=*) INPUT_DIR="${1#--input=}"; shift ;;
    --mb) require_value "$@"; MB_ARG="$2"; shift 2 ;;
    --mb=*) MB_ARG="${1#--mb=}"; shift ;;
    --plan) require_value "$@"; PLAN_ARG="$2"; shift 2 ;;
    --plan=*) PLAN_ARG="${1#--plan=}"; shift ;;
    --item) require_value "$@"; ITEM_ARG="$2"; shift 2 ;;
    --item=*) ITEM_ARG="${1#--item=}"; shift ;;
    --run-id) require_value "$@"; RUN_ID_ARG="$2"; shift 2 ;;
    --run-id=*) RUN_ID_ARG="${1#--run-id=}"; shift ;;
    --refresh-tests) REFRESH_TESTS=1; shift ;;
    --ttl) require_value "$@"; TTL_ARG="$2"; shift 2 ;;
    --ttl=*) TTL_ARG="${1#--ttl=}"; shift ;;
    -h|--help) sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "[review] unknown argument '$1'" >&2; usage_short; exit 2 ;;
  esac
done

if [ "$EMIT_PAYLOAD" -ne 1 ]; then
  echo "[review] only --emit-payload is implemented in this reviewer-2.0 stage" >&2
  usage_short
  exit 2
fi

BANK=$(mb_resolve_path "$MB_ARG")
mkdir -p "$BANK/tmp"

RUN_ID="$RUN_ID_ARG"
[ -z "$RUN_ID" ] && RUN_ID="${MB_WORK_RUN_ID:-}"

# ---- gather sections ---------------------------------------------------

if [ -n "$INPUT_DIR" ]; then
  PLAN_CONTEXT=$(render_input_plan_context "$INPUT_DIR")
  DIFF_TEXT=$(read_input_diff "$INPUT_DIR")
  PRIOR_JSON=$(read_input_prior "$INPUT_DIR")
  PRIOR_REASON="input-missing"
else
  if [ -n "$ITEM_ARG" ]; then
    last_verdict_cache_path "$BANK" "$ITEM_ARG" >/dev/null
  fi
  BASELINE=$(resolve_baseline_ref "$BANK" "$PLAN_ARG")
  TOUCHED_FILES=$(resolve_touched_files "$BANK" "$RUN_ID" "$BASELINE")
  DIFF_TEXT=$(resolve_diff_text "$BANK" "$RUN_ID" "$BASELINE")
  PLAN_CONTEXT=$(render_real_plan_context "$PLAN_ARG" "$ITEM_ARG")

  if [ "$REFRESH_TESTS" -eq 1 ]; then
    bash "$CACHE_SH" clear --mb "$BANK"
  fi

  TTL="$TTL_ARG"
  [ -z "$TTL" ] && TTL=$(resolve_ttl_default "$MB_ARG")

  TOUCHED_SHA=$(printf '%s\n' "$TOUCHED_FILES" | bash "$CACHE_SH" sha)

  HIT_MISS=$(bash "$CACHE_SH" check --mb "$BANK" --sha "$TOUCHED_SHA" --ttl "$TTL" 2>/dev/null) || true
  if [ "$HIT_MISS" = "HIT" ]; then
    PRIOR_JSON=$(cat "$BANK/tmp/last-tests.json" 2>/dev/null || true)
    PRIOR_REASON="hit"
  else
    PRIOR_JSON=""
    PRIOR_REASON="miss"
  fi
fi

# ---- assemble + print (stdout only — no reviewer dispatch, no network) ------

{
  printf '%s\n' "$PLAN_CONTEXT"
  echo
  render_diff_section "$DIFF_TEXT"
  echo
  render_examples_section
  echo
  render_prior_and_findings "$PRIOR_REASON" "$PRIOR_JSON"
}
