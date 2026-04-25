#!/usr/bin/env bash
# mb-work-severity-gate.sh — apply pipeline.yaml severity_gate to review counts.
#
# Usage:
#   mb-work-severity-gate.sh --counts <json> [--mb <path>] [--gate <json>]
#   mb-work-severity-gate.sh --counts-stdin [--mb <path>] [--gate <json>]
#
# Reads severity_gate from the effective pipeline.yaml's
# stage_pipeline[step=review] section unless --gate overrides.
#
# Exit codes:
#   0  PASS  — all severities within their limits
#   1  FAIL  — at least one severity exceeds its limit
#   2  usage error / parse error

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE="$SCRIPT_DIR/mb-pipeline.sh"

COUNTS_JSON=""
COUNTS_FROM_STDIN=0
MB_ARG=""
GATE_JSON=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --counts) COUNTS_JSON="${2:-}"; shift 2 ;;
    --counts=*) COUNTS_JSON="${1#--counts=}"; shift ;;
    --counts-stdin) COUNTS_FROM_STDIN=1; shift ;;
    --gate) GATE_JSON="${2:-}"; shift 2 ;;
    --gate=*) GATE_JSON="${1#--gate=}"; shift ;;
    --mb) MB_ARG="${2:-}"; shift 2 ;;
    --mb=*) MB_ARG="${1#--mb=}"; shift ;;
    -h|--help) sed -n '2,16p' "$0" >&2; exit 0 ;;
    *) echo "[severity-gate] unknown arg '$1'" >&2; exit 2 ;;
  esac
done

if [ "$COUNTS_FROM_STDIN" -eq 1 ]; then
  COUNTS_JSON=$(cat -)
fi

if [ -z "$COUNTS_JSON" ]; then
  echo "[severity-gate] --counts <json> or --counts-stdin required" >&2
  exit 2
fi

PIPELINE_PATH=$(bash "$PIPELINE" path "$MB_ARG" 2>/dev/null || true)
if [ -z "$PIPELINE_PATH" ]; then
  PIPELINE_PATH="$SCRIPT_DIR/../references/pipeline.default.yaml"
fi

PIPELINE_YAML="$PIPELINE_PATH" \
COUNTS_JSON="$COUNTS_JSON" \
GATE_JSON_OVERRIDE="$GATE_JSON" \
python3 - <<'PY'
import json
import os
import sys

try:
    counts = json.loads(os.environ["COUNTS_JSON"])
    if not isinstance(counts, dict):
        raise ValueError("counts must be an object")
except (ValueError, json.JSONDecodeError) as exc:
    sys.stderr.write(f"[severity-gate] invalid counts JSON: {exc}\n")
    sys.exit(2)

gate_override = os.environ.get("GATE_JSON_OVERRIDE", "")
if gate_override:
    try:
        gate = json.loads(gate_override)
    except json.JSONDecodeError as exc:
        sys.stderr.write(f"[severity-gate] invalid --gate JSON: {exc}\n")
        sys.exit(2)
else:
    try:
        import yaml  # type: ignore
        cfg = yaml.safe_load(open(os.environ["PIPELINE_YAML"], encoding="utf-8")) or {}
    except Exception as exc:
        sys.stderr.write(f"[severity-gate] failed to load pipeline.yaml: {exc}\n")
        sys.exit(2)
    review_step = next(
        (s for s in (cfg.get("stage_pipeline") or []) if s.get("step") == "review"),
        None,
    )
    if not review_step:
        sys.stderr.write("[severity-gate] no 'review' step in stage_pipeline\n")
        sys.exit(2)
    gate = review_step.get("severity_gate") or {}

breaches = []
for sev in ("blocker", "major", "minor"):
    actual = counts.get(sev, 0)
    if not isinstance(actual, int) or isinstance(actual, bool):
        sys.stderr.write(f"[severity-gate] counts.{sev}: must be int (got {actual!r})\n")
        sys.exit(2)
    limit = gate.get(sev)
    if limit is None:
        # Severity not declared in gate — treat as 0 (strict)
        limit = 0
    if actual > limit:
        breaches.append((sev, actual, limit))

if breaches:
    for sev, actual, limit in breaches:
        sys.stderr.write(f"[severity-gate] FAIL: {sev}={actual} > gate={limit}\n")
    sys.exit(1)

print("[severity-gate] PASS")
sys.exit(0)
PY
