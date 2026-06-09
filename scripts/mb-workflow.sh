#!/usr/bin/env bash
# mb-workflow.sh — resolve /mb work workflow mode from pipeline.yaml.
#
# Usage:
#   mb-workflow.sh [--mb <path>] [--workflow <name>] [--json|--steps|--loop|max-cycles|approval-required]
#
# Resolution:
#   1. Read effective pipeline.yaml via mb-pipeline.sh path.
#   2. If --workflow is omitted, use workflow.default, else "execution".
#   3. Apply workflow.aliases.<name> when present.
#   4. Resolve workflows.<name>. If workflows is absent, derive a legacy
#      workflow from stage_pipeline.
#
# Exit codes:
#   0 — resolved
#   1 — unknown workflow / invalid pipeline
#   2 — usage error

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE="$SCRIPT_DIR/mb-pipeline.sh"

MB_ARG=""
WORKFLOW=""
OUTPUT="json"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mb) MB_ARG="${2:-}"; shift 2 ;;
    --mb=*) MB_ARG="${1#--mb=}"; shift ;;
    --workflow) WORKFLOW="${2:-}"; shift 2 ;;
    --workflow=*) WORKFLOW="${1#--workflow=}"; shift ;;
    --json) OUTPUT="json"; shift ;;
    --steps) OUTPUT="steps"; shift ;;
    --loop) OUTPUT="loop"; shift ;;
    --max-cycles) OUTPUT="max-cycles"; shift ;;
    --approval-required) OUTPUT="approval-required"; shift ;;
    -h|--help) sed -n '2,18p' "$0" >&2; exit 0 ;;
    *) echo "[workflow] unknown arg '$1'" >&2; exit 2 ;;
  esac
done

PIPELINE_PATH=$(bash "$PIPELINE" path "$MB_ARG" 2>/dev/null || true)
if [ -z "$PIPELINE_PATH" ]; then
  PIPELINE_PATH="$SCRIPT_DIR/../references/pipeline.default.yaml"
fi

PIPELINE_YAML="$PIPELINE_PATH" WORKFLOW_NAME="$WORKFLOW" OUTPUT="$OUTPUT" python3 - <<'PY'
import json
import os
import sys

try:
    import yaml  # type: ignore
except ImportError:
    sys.stderr.write("[workflow] PyYAML is required to resolve named workflows\n")
    sys.exit(1)

path = os.environ["PIPELINE_YAML"]
requested = os.environ.get("WORKFLOW_NAME", "")
output = os.environ.get("OUTPUT", "json")

try:
    cfg = yaml.safe_load(open(path, encoding="utf-8")) or {}
except Exception as exc:
    sys.stderr.write(f"[workflow] failed to load pipeline.yaml: {exc}\n")
    sys.exit(1)

workflow_cfg = cfg.get("workflow") or {}
if not isinstance(workflow_cfg, dict):
    workflow_cfg = {}

aliases = workflow_cfg.get("aliases") or {}
if not isinstance(aliases, dict):
    aliases = {}

default_name = workflow_cfg.get("default") or "execution"
name = requested or default_name
name = aliases.get(name, name)

workflows = cfg.get("workflows") or {}
if workflows and not isinstance(workflows, dict):
    sys.stderr.write("[workflow] workflows must be a mapping\n")
    sys.exit(1)

source = "workflows"
if name in workflows:
    spec = workflows[name] or {}
    if not isinstance(spec, dict):
        sys.stderr.write(f"[workflow] workflows.{name} must be a mapping\n")
        sys.exit(1)
    steps = spec.get("steps") or []
    loop = spec.get("loop") or {}
    entrypoint = spec.get("entrypoint")
    interactive = bool(spec.get("interactive", False))
elif not workflows:
    # Backward compatibility: derive from stage_pipeline.
    source = "stage_pipeline"
    stage_pipeline = cfg.get("stage_pipeline") or []
    if not isinstance(stage_pipeline, list) or not stage_pipeline:
        sys.stderr.write("[workflow] no workflows or stage_pipeline found\n")
        sys.exit(1)
    steps = [s.get("step") for s in stage_pipeline if isinstance(s, dict) and s.get("step")]
    review = next((s for s in stage_pipeline if isinstance(s, dict) and s.get("step") == "review"), {})
    fix = next((s for s in stage_pipeline if isinstance(s, dict) and s.get("step") == "fix"), {})
    loop = {
        "after": "review",
        "until": "reviewer_approved" if review.get("approval_required") else "severity_gate_pass",
        "returns_to": fix.get("returns_to", "verify"),
        "max_cycles": review.get("max_cycles", 3),
        "on_max_cycles": review.get("on_max_cycles", "stop_for_human"),
        "approval_required": bool(review.get("approval_required", False)),
    }
    entrypoint = "plan_or_spec"
    interactive = False
else:
    available = ", ".join(sorted(workflows.keys()))
    sys.stderr.write(f"[workflow] unknown workflow '{name}'. Available: {available}\n")
    sys.exit(1)

if not isinstance(steps, list) or not all(isinstance(s, str) and s for s in steps):
    sys.stderr.write(f"[workflow] workflow '{name}' steps must be a list of non-empty strings\n")
    sys.exit(1)
if loop is None:
    loop = {}
if not isinstance(loop, dict):
    sys.stderr.write(f"[workflow] workflow '{name}' loop must be a mapping\n")
    sys.exit(1)

resolved = {
    "name": name,
    "source": source,
    "steps": steps,
    "entrypoint": entrypoint,
    "interactive": interactive,
    "loop": loop,
}

if output == "json":
    print(json.dumps(resolved, ensure_ascii=False))
elif output == "steps":
    for step in steps:
        print(step)
elif output == "loop":
    print(json.dumps(loop, ensure_ascii=False))
elif output == "max-cycles":
    print(loop.get("max_cycles", ""))
elif output == "approval-required":
    print("true" if loop.get("approval_required") else "false")
else:
    sys.stderr.write(f"[workflow] unknown output mode: {output}\n")
    sys.exit(2)
PY
