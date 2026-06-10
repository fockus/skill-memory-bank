#!/usr/bin/env bash
# mb-workflow.sh — resolve and compose the /mb work stage pipeline.
#
# Usage:
#   mb-workflow.sh [--mb <path>] [--workflow <name>]
#                  [--review|--no-review] [--judge|--no-judge]
#                  [--brainstorm|--no-brainstorm] [--sdd|--no-sdd] [--plan|--no-plan]
#                  [--stages <csv>] [--json|--steps|--loop|--max-cycles|--approval-required]
#
# Resolution (3-layer, precedence: launch flags > pipeline.yaml > built-in default):
#   1. Read effective pipeline.yaml via mb-pipeline.sh path.
#   2. Resolve the preset: --workflow ▸ workflow.default ▸ "execution"
#      (aliases applied; workflows absent → legacy stage_pipeline).
#   3. Compose stages: preset steps, then pipeline.yaml `<stage>.enabled: true`
#      adds a composable stage, then launch flags add/remove (flags win), then
#      re-sort into canonical order. `--stages <csv>` overrides everything.
#   Canonical order: discuss → sdd → plan → implement → verify → review → judge → fix → done.
#   `--brainstorm` is an alias of `discuss`. `judge` requires `review` (fail-fast).
#
# Exit codes:
#   0 — resolved
#   1 — unknown workflow / invalid pipeline
#   2 — usage error / unknown stage / judge-without-review

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE="$SCRIPT_DIR/mb-pipeline.sh"

MB_ARG=""
WORKFLOW=""
OUTPUT="json"
FLAG_REVIEW=""
FLAG_JUDGE=""
FLAG_DISCUSS=""
FLAG_SDD=""
FLAG_PLAN=""
STAGES_OVERRIDE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mb) MB_ARG="${2:-}"; shift 2 ;;
    --mb=*) MB_ARG="${1#--mb=}"; shift ;;
    --workflow) WORKFLOW="${2:-}"; shift 2 ;;
    --workflow=*) WORKFLOW="${1#--workflow=}"; shift ;;
    --review) FLAG_REVIEW="on"; shift ;;
    --no-review) FLAG_REVIEW="off"; shift ;;
    --judge) FLAG_JUDGE="on"; shift ;;
    --no-judge) FLAG_JUDGE="off"; shift ;;
    --brainstorm) FLAG_DISCUSS="on"; shift ;;
    --no-brainstorm) FLAG_DISCUSS="off"; shift ;;
    --sdd) FLAG_SDD="on"; shift ;;
    --no-sdd) FLAG_SDD="off"; shift ;;
    --plan) FLAG_PLAN="on"; shift ;;
    --no-plan) FLAG_PLAN="off"; shift ;;
    --stages) STAGES_OVERRIDE="${2:-}"; shift 2 ;;
    --stages=*) STAGES_OVERRIDE="${1#--stages=}"; shift ;;
    --json) OUTPUT="json"; shift ;;
    --steps) OUTPUT="steps"; shift ;;
    --loop) OUTPUT="loop"; shift ;;
    --max-cycles) OUTPUT="max-cycles"; shift ;;
    --approval-required) OUTPUT="approval-required"; shift ;;
    -h|--help) sed -n '2,27p' "$0" >&2; exit 0 ;;
    *) echo "[workflow] unknown arg '$1'" >&2; exit 2 ;;
  esac
done

PIPELINE_PATH=$(bash "$PIPELINE" path "$MB_ARG" 2>/dev/null || true)
if [ -z "$PIPELINE_PATH" ]; then
  PIPELINE_PATH="$SCRIPT_DIR/../references/pipeline.default.yaml"
fi

PIPELINE_YAML="$PIPELINE_PATH" WORKFLOW_NAME="$WORKFLOW" OUTPUT="$OUTPUT" \
FLAG_REVIEW="$FLAG_REVIEW" FLAG_JUDGE="$FLAG_JUDGE" FLAG_DISCUSS="$FLAG_DISCUSS" \
FLAG_SDD="$FLAG_SDD" FLAG_PLAN="$FLAG_PLAN" STAGES_OVERRIDE="$STAGES_OVERRIDE" \
python3 - <<'PY'
import json
import os
import sys

try:
    import yaml  # type: ignore
except ImportError:
    sys.stderr.write("[workflow] PyYAML is required to resolve named workflows\n")
    sys.exit(1)

# Canonical stage order; `fix` is an internal loop mechanic, not directly
# composable. Every shipped preset's step list is already canonically ordered,
# so re-sorting the composed set is a no-op for un-modified presets.
CANONICAL = ["discuss", "sdd", "plan", "implement", "verify", "review", "judge", "fix", "done"]
# Stages that pipeline.yaml `<stage>.enabled` / launch flags may toggle. The
# core stages (implement/verify/done) and the internal `fix` loop are not.
COMPOSABLE = ["discuss", "sdd", "plan", "review", "judge"]
# Launch flag (env) → stage. `--brainstorm` is an alias of `discuss`.
FLAG_STAGE = {
    "FLAG_REVIEW": "review",
    "FLAG_JUDGE": "judge",
    "FLAG_DISCUSS": "discuss",
    "FLAG_SDD": "sdd",
    "FLAG_PLAN": "plan",
}

path = os.environ["PIPELINE_YAML"]
requested = os.environ.get("WORKFLOW_NAME", "")
output = os.environ.get("OUTPUT", "json")
stages_override = (os.environ.get("STAGES_OVERRIDE", "") or "").strip()
flag_for_stage = {}
for env_key, stage in FLAG_STAGE.items():
    val = os.environ.get(env_key, "")
    if val in ("on", "off"):
        flag_for_stage[stage] = val

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


def _yaml_stage_enabled(stage):
    """True only when pipeline.yaml explicitly sets `<stage>.enabled: true`."""
    block = cfg.get(stage)
    if isinstance(block, dict) and block.get("enabled") is True:
        return True
    return False


# ── compose the stage list (3-layer merge) ─────────────────────────────────
if stages_override:
    # --stages is the escape hatch: exact ordered list, overrides everything.
    requested_stages = [s.strip() for s in stages_override.split(",") if s.strip()]
    unknown = [s for s in requested_stages if s not in CANONICAL]
    if unknown:
        sys.stderr.write(
            f"[workflow] unknown stage(s) in --stages: {', '.join(unknown)}; "
            f"allowed: {', '.join(CANONICAL)}\n"
        )
        sys.exit(2)
    steps = requested_stages
    source = "stages"
else:
    original = list(steps)
    active = set(steps)
    flagged = False
    yaml_added = False
    changed = False
    for stage in COMPOSABLE:
        flag = flag_for_stage.get(stage)
        if flag == "on":
            if stage not in active:
                changed = True
            active.add(stage)
            flagged = True
        elif flag == "off":
            if stage in active:
                changed = True
            active.discard(stage)
            flagged = True
        elif _yaml_stage_enabled(stage):
            # pipeline.yaml turns a stage ON; launch flags (above) win over it.
            if stage not in active:
                changed = True
            active.add(stage)
            yaml_added = True
    # Canonical re-sort only when composition actually changed the set; an
    # un-modified preset (or legacy stage_pipeline) keeps its own order verbatim
    # so adding no configuration preserves today's behaviour (NFR-001).
    if changed:
        steps = [s for s in CANONICAL if s in active]
    else:
        steps = original
    if flagged:
        source = "flags"
    elif yaml_added:
        source = "pipeline"

# Fail-fast: judge evaluates review output, so it requires review (REQ-013).
if "judge" in steps and "review" not in steps:
    sys.stderr.write(
        "[workflow] judge requires review — add --review or enable review "
        "in pipeline.yaml (or drop --judge)\n"
    )
    sys.exit(2)

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
