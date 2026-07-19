#!/usr/bin/env bash
# mb-pipeline-validate.sh — structural validation for pipeline.yaml (spec §9).
#
# Usage:
#   mb-pipeline-validate.sh <path-to-pipeline.yaml>
#
# Exit codes:
#   0 — file passes schema check
#   1 — schema/structural violation (errors printed to stderr)
#   2 — usage error / file not found

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat >&2 <<'USAGE'
Usage: mb-pipeline-validate.sh <path-to-pipeline.yaml>
       mb-pipeline-validate.sh --stages <csv> [--input none|topic|spec|plan|diff]

In --stages mode, validates a composed /mb work stage list:
  - every stage ∈ {discuss,sdd,plan,implement,verify,review,judge,fix,done}
  - judge requires review (fail-fast)
  - sdd/plan require an upstream input (errors when --input none)

In file mode, validates the file against the spec §9 schema:
  - required top-level keys (version, roles, stage_pipeline, budget,
    protected_paths, sprint_context_guard, review_rubric, sdd)
  - version == 1 (string "1" is also accepted for YAML-schema compatibility)
  - roles entries have an 'agent' field
  - stage_pipeline references only declared roles ('auto' permitted for implement/fix dispatch)
  - optional workflow/workflows local override profiles are structurally valid
  - review severity_gate keys ⊆ {blocker, major, minor}, values int >= 0
  - max_cycles >= 1, on_max_cycles ∈ {stop_for_human, continue_with_warning, judge_decides}
  - sprint_context_guard.hard_stop_tokens > soft_warn_tokens, both > 0
  - budget.warn_at_percent / stop_at_percent ∈ [0, 100]
  - review_rubric: 5 sections, each non-empty list of strings
  - sdd.covers_requirements_policy ∈ {warn, block, off}
USAGE
}

STAGES=""
INPUT_KIND=""
PATH_ARG=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --stages) STAGES="${2:-}"; shift 2 ;;
    --stages=*) STAGES="${1#--stages=}"; shift ;;
    --input) INPUT_KIND="${2:-}"; shift 2 ;;
    --input=*) INPUT_KIND="${1#--input=}"; shift ;;
    -*) echo "[validate] unknown option '$1'" >&2; usage; exit 2 ;;
    *)
      if [ -n "$PATH_ARG" ]; then
        echo "[validate] unexpected argument '$1'" >&2
        exit 2
      fi
      PATH_ARG="$1"
      shift
      ;;
  esac
done

# ── composed stage-list validation mode (--stages) ──────────────────────────
if [ -n "$STAGES" ]; then
  STAGES_CSV="$STAGES" INPUT_KIND="$INPUT_KIND" python3 - <<'PY'
import os
import sys

CANONICAL = ["discuss", "sdd", "plan", "implement", "verify", "review", "judge", "fix", "done"]
VALID_INPUT = {"", "none", "topic", "spec", "plan", "diff"}

stages = [s.strip() for s in os.environ["STAGES_CSV"].split(",") if s.strip()]
input_kind = (os.environ.get("INPUT_KIND", "") or "").strip()
errors = []

if not stages:
    errors.append("--stages: empty stage list")

unknown = [s for s in stages if s not in CANONICAL]
if unknown:
    errors.append(
        f"--stages: unknown stage(s) {sorted(set(unknown))}; allowed {CANONICAL}"
    )

if input_kind not in VALID_INPUT:
    errors.append(f"--input: '{input_kind}' not in {sorted(VALID_INPUT - {''})}")

# REQ-013: judge evaluates review output → judge requires review.
if "judge" in stages and "review" not in stages:
    errors.append("judge requires review — add review or drop judge")

# REQ-014: sdd/plan need an upstream topic/spec input.
needs_input = [s for s in ("sdd", "plan") if s in stages]
if needs_input and input_kind == "none":
    errors.append(
        f"{'/'.join(needs_input)} requires an upstream input "
        "(a topic or spec) but none is available"
    )

if errors:
    for e in errors:
        sys.stderr.write(f"[validate] {e}\n")
    sys.exit(1)
sys.exit(0)
PY
  exit $?
fi

if [ -z "$PATH_ARG" ]; then
  usage
  exit 2
fi

if [ ! -f "$PATH_ARG" ]; then
  echo "[validate] file not found: $PATH_ARG" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PYTHONPATH="$REPO_ROOT${PYTHONPATH:+:$PYTHONPATH}"
MB_PIPELINE_PATH="$PATH_ARG" python3 "$SCRIPT_DIR/mb_pipeline_validate_core.py"
