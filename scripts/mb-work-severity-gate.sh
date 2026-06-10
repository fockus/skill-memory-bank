#!/usr/bin/env bash
# mb-work-severity-gate.sh — apply /mb work reviewer approval + severity gate.
#
# Usage:
#   mb-work-severity-gate.sh --counts <json> [--mb <path>] [--workflow <name>] [--gate <json>]
#   mb-work-severity-gate.sh --counts-stdin [--mb <path>] [--workflow <name>] [--gate <json>]
#
# Input can be either raw counts:
#   {"blocker":0,"major":0,"minor":0}
# or normalized reviewer JSON from mb-work-review-parse.sh:
#   {"verdict":"APPROVED","counts":{"blocker":0,"major":0,"minor":0},"issues":[]}
#
# Resolves the severity gate from the opt-in `review:` block ▸ legacy
# stage_pipeline[step=review] ▸ active workflow loop.severity_gate. When no
# review is configured anywhere the gate is a PASS no-op (review is opt-in).
# --gate overrides severity limits only.
#
# Exit codes:
#   0  PASS  — no review configured, or approval policy and severity limits pass
#   1  FAIL  — reviewer did not approve or a severity exceeds its limit
#   2  usage error / parse error

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE="$SCRIPT_DIR/mb-pipeline.sh"

COUNTS_JSON=""
COUNTS_FROM_STDIN=0
MB_ARG=""
WORKFLOW_NAME=""
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
    --workflow) WORKFLOW_NAME="${2:-}"; shift 2 ;;
    --workflow=*) WORKFLOW_NAME="${1#--workflow=}"; shift ;;
    -h|--help) sed -n '2,19p' "$0" >&2; exit 0 ;;
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
WORKFLOW_NAME="$WORKFLOW_NAME" \
python3 - <<'PY'
import json
import os
import sys


def strip_comment(line: str) -> str:
    in_single = False
    in_double = False
    for idx, char in enumerate(line):
        if char == "'" and not in_double:
            in_single = not in_single
        elif char == '"' and not in_single:
            in_double = not in_double
        elif char == "#" and not in_single and not in_double:
            return line[:idx]
    return line


def parse_scalar(value: str):
    raw = value.strip().strip('"\'')
    if raw.lower() in {"true", "yes"}:
        return True
    if raw.lower() in {"false", "no"}:
        return False
    try:
        return int(raw)
    except ValueError:
        return raw


def _read_top_level_review_gate(path: str):
    """Parse the opt-in top-level `review:` block → severity_gate dict, or None."""
    in_review = False
    in_gate = False
    gate_indent = -1
    gate: dict[str, int] = {}
    found_gate = False
    for raw in open(path, encoding="utf-8"):
        line = strip_comment(raw).rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()
        if indent == 0:
            in_review = stripped == "review:"
            in_gate = False
            continue
        if not in_review:
            continue
        if not in_gate:
            if stripped == "severity_gate:":
                in_gate = True
                found_gate = True
                gate_indent = indent
            continue
        if indent <= gate_indent:
            in_gate = False
            continue
        key, sep, value = stripped.partition(":")
        if sep:
            parsed = parse_scalar(value)
            if isinstance(parsed, int) and not isinstance(parsed, bool):
                gate[key.strip()] = parsed
    return gate if found_gate else None


def _parse_stage_review_without_yaml(path: str) -> tuple[dict[str, int], bool, bool]:
    """Parse a legacy stage_pipeline `- step: review` → (gate, approval, found)."""
    gate: dict[str, int] = {}
    approval_required = False
    found = False
    in_stage_pipeline = False
    in_review = False
    in_gate = False
    gate_indent = 0
    for raw in open(path, encoding="utf-8"):
        line = strip_comment(raw).rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()
        if not in_stage_pipeline:
            if stripped == "stage_pipeline:":
                in_stage_pipeline = True
            continue
        if indent == 0 and not stripped.startswith("-"):
            break
        if indent == 2 and stripped.startswith("- "):
            in_review = stripped == "- step: review"
            if in_review:
                found = True
            in_gate = False
            continue
        if not in_review:
            continue
        if stripped == "severity_gate:":
            in_gate = True
            gate_indent = indent
            continue
        if in_gate:
            if indent <= gate_indent:
                in_gate = False
            else:
                key, sep, value = stripped.partition(":")
                if sep:
                    parsed = parse_scalar(value)
                    if isinstance(parsed, int) and not isinstance(parsed, bool):
                        gate[key.strip()] = parsed
                continue
        key, sep, value = stripped.partition(":")
        if sep and key.strip() == "approval_required":
            approval_required = bool(parse_scalar(value))
    return gate, approval_required, found


def parse_review_policy_without_yaml(path: str):
    """No-PyYAML fallback. Returns (gate, approval) or (None, False) when no
    review policy is configured anywhere (review: block ▸ stage_pipeline review)."""
    gate = _read_top_level_review_gate(path)
    if gate is not None:
        return gate, False
    stage_gate, approval_required, found = _parse_stage_review_without_yaml(path)
    if found:
        return stage_gate, approval_required
    return None, False


def load_review_policy(path: str):
    """Resolve the severity gate from review.severity_gate ▸ stage_pipeline[review]
    ▸ active workflow loop.severity_gate. Returns (None, False) when no review
    policy is configured anywhere (REQ-011 — caller treats it as a PASS no-op)."""
    try:
        import yaml  # type: ignore
    except ImportError:
        return parse_review_policy_without_yaml(path)
    try:
        cfg = yaml.safe_load(open(path, encoding="utf-8")) or {}
    except Exception as exc:
        sys.stderr.write(f"[severity-gate] failed to load pipeline.yaml: {exc}\n")
        sys.exit(2)

    gate = None
    approval_required = False

    # 1. Modern opt-in top-level review: block.
    review_block = cfg.get("review")
    if isinstance(review_block, dict) and isinstance(review_block.get("severity_gate"), dict):
        gate = review_block["severity_gate"]

    # 2. Legacy stage_pipeline review step.
    if gate is None:
        review_step = next(
            (s for s in (cfg.get("stage_pipeline") or [])
             if isinstance(s, dict) and s.get("step") == "review"),
            None,
        )
        if review_step is not None:
            gate = review_step.get("severity_gate") or {}
            approval_required = bool(review_step.get("approval_required", False))

    # 3. Active workflow loop severity_gate (governed workflows override).
    workflow_cfg = cfg.get("workflow") or {}
    if not isinstance(workflow_cfg, dict):
        workflow_cfg = {}
    aliases = workflow_cfg.get("aliases") or {}
    if not isinstance(aliases, dict):
        aliases = {}
    workflow_name = os.environ.get("WORKFLOW_NAME") or workflow_cfg.get("default") or ""
    workflow_name = aliases.get(workflow_name, workflow_name)

    workflows = cfg.get("workflows") or {}
    if workflow_name and isinstance(workflows, dict) and workflow_name in workflows:
        workflow_spec = workflows.get(workflow_name) or {}
        if isinstance(workflow_spec, dict):
            loop = workflow_spec.get("loop") or {}
            if isinstance(loop, dict):
                if isinstance(loop.get("severity_gate"), dict):
                    gate = loop["severity_gate"]
                if "approval_required" in loop:
                    approval_required = bool(loop.get("approval_required"))

    return gate, approval_required


try:
    payload = json.loads(os.environ["COUNTS_JSON"])
    if not isinstance(payload, dict):
        raise ValueError("input must be an object")
except (ValueError, json.JSONDecodeError) as exc:
    sys.stderr.write(f"[severity-gate] invalid JSON: {exc}\n")
    sys.exit(2)

verdict = payload.get("verdict")
if "counts" in payload:
    counts = payload.get("counts")
else:
    counts = payload

if not isinstance(counts, dict):
    sys.stderr.write("[severity-gate] counts must be an object\n")
    sys.exit(2)

gate, approval_required = load_review_policy(os.environ["PIPELINE_YAML"])
override = os.environ.get("GATE_JSON_OVERRIDE", "")
if override:
    try:
        gate = json.loads(override)
    except json.JSONDecodeError as exc:
        sys.stderr.write(f"[severity-gate] invalid --gate JSON: {exc}\n")
        sys.exit(2)
elif gate is None:
    # REQ-011: no review configured anywhere → the gate is a PASS no-op.
    print("[severity-gate] PASS (no review configured)")
    sys.exit(0)

if approval_required:
    if verdict != "APPROVED":
        shown = verdict if verdict is not None else "<missing>"
        sys.stderr.write(f"[severity-gate] FAIL: approval_required=true but verdict={shown}\n")
        sys.exit(1)
elif verdict is not None and verdict not in {"APPROVED", "CHANGES_REQUESTED"}:
    sys.stderr.write(f"[severity-gate] invalid verdict: {verdict!r}\n")
    sys.exit(2)

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
