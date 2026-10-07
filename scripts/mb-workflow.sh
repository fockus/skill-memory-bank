#!/usr/bin/env bash
# mb-workflow.sh — resolve and compose the /mb work stage pipeline.
#
# Usage:
#   mb-workflow.sh [--mb <path>] [--workflow <name>]
#                  [--review|--no-review] [--judge|--no-judge] [--fix|--no-fix]
#                  [--brainstorm|--no-brainstorm] [--sdd|--no-sdd] [--plan|--no-plan]
#                  [--stages <csv>] [--verify=stage|plan|run|off] [--tier <effort-tier>]
#                  [--host <id>] [--no-adapt]
#                  [--json|--steps|--loop|--max-cycles|--approval-required]
#
# Resolution (3-layer, precedence: launch flags > pipeline.yaml > built-in default):
#   1. Read effective pipeline.yaml via mb-pipeline.sh path.
#   2. Resolve the preset: --workflow ▸ --tier (effort_tiers map) ▸
#      hosts.<host>.preset ▸ workflow.default ▸ "execution" (aliases applied; workflows absent →
#      legacy stage_pipeline). `--tier trivial` exits 2: no /mb work needed.
#   3. Compose stages: preset steps, then pipeline.yaml `<stage>.enabled: true`
#      adds a composable stage, then launch flags add/remove (flags win), then
#      re-sort into canonical order. `--stages <csv>` overrides everything.
#   Canonical order: discuss → sdd → plan → implement → verify → review → judge → fix → done.
#   `--brainstorm` is an alias of `discuss`. `judge` and `fix` require `review`
#   (fail-fast). A flag-added `fix` on a preset with no loop block gets loop
#   defaults (returns_to: verify) so the cycle has a termination condition.
#   4. Verifier cadence (JSON `verify_cadence`): --verify ▸ hosts.<host>.verify ▸
#      workflows.<name>.verify.cadence ▸ "plan" (AGR-075); forced to "off" when the steps hold no verify.
#      JSON `self_verify` mirrors workflows.<name>.implement.self_verify.
#   Host: --host ▸ mb_detect_host (_lib.sh); JSON `host`.
#   5. ADaPT (JSON `adapt`, once per run): pipeline.yaml `adapt:` over defaults
#      {enabled: true, verify_fail_cycles: 3, item_token_budget: null, max_depth: 2};
#      --no-adapt forces enabled=false (references/adapt.md).
#
# Exit codes:
#   0 — resolved
#   1 — unknown workflow / invalid pipeline
#   2 — usage error / unknown stage / judge-or-fix-without-review

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE="$SCRIPT_DIR/mb-pipeline.sh"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

MB_ARG=""
WORKFLOW=""
OUTPUT="json"
FLAG_REVIEW=""
FLAG_JUDGE=""
FLAG_FIX=""
FLAG_DISCUSS=""
FLAG_SDD=""
FLAG_PLAN=""
STAGES_OVERRIDE=""
VERIFY_CADENCE=""
TIER=""
HOST=""
NO_ADAPT=""

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
    --fix) FLAG_FIX="on"; shift ;;
    --no-fix) FLAG_FIX="off"; shift ;;
    --brainstorm) FLAG_DISCUSS="on"; shift ;;
    --no-brainstorm) FLAG_DISCUSS="off"; shift ;;
    --sdd) FLAG_SDD="on"; shift ;;
    --no-sdd) FLAG_SDD="off"; shift ;;
    --plan) FLAG_PLAN="on"; shift ;;
    --no-plan) FLAG_PLAN="off"; shift ;;
    --stages) STAGES_OVERRIDE="${2:-}"; shift 2 ;;
    --stages=*) STAGES_OVERRIDE="${1#--stages=}"; shift ;;
    --verify) VERIFY_CADENCE="${2:-}"; shift 2 ;;
    --verify=*) VERIFY_CADENCE="${1#--verify=}"; shift ;;
    --tier) TIER="${2:-}"; shift 2 ;;
    --tier=*) TIER="${1#--tier=}"; shift ;;
    --host) HOST="${2:-}"; shift 2 ;;
    --host=*) HOST="${1#--host=}"; shift ;;
    --no-adapt) NO_ADAPT="1"; shift ;;
    --json) OUTPUT="json"; shift ;;
    --steps) OUTPUT="steps"; shift ;;
    --loop) OUTPUT="loop"; shift ;;
    --max-cycles) OUTPUT="max-cycles"; shift ;;
    --approval-required) OUTPUT="approval-required"; shift ;;
    -h|--help) sed -n '2,36p' "$0" >&2; exit 0 ;;
    *) echo "[workflow] unknown arg '$1'" >&2; exit 2 ;;
  esac
done

[ -n "$HOST" ] || HOST=$(mb_detect_host)

PIPELINE_PATH=$(bash "$PIPELINE" path "$MB_ARG" 2>/dev/null || true)
if [ -z "$PIPELINE_PATH" ]; then
  PIPELINE_PATH="$SCRIPT_DIR/../references/pipeline.default.yaml"
fi

PIPELINE_YAML="$PIPELINE_PATH" WORKFLOW_NAME="$WORKFLOW" OUTPUT="$OUTPUT" \
FLAG_REVIEW="$FLAG_REVIEW" FLAG_JUDGE="$FLAG_JUDGE" FLAG_FIX="$FLAG_FIX" FLAG_DISCUSS="$FLAG_DISCUSS" \
FLAG_SDD="$FLAG_SDD" FLAG_PLAN="$FLAG_PLAN" STAGES_OVERRIDE="$STAGES_OVERRIDE" \
VERIFY_CADENCE="$VERIFY_CADENCE" TIER="$TIER" HOST="$HOST" NO_ADAPT="$NO_ADAPT" MB_SD="$SCRIPT_DIR" \
python3 - <<'PY'
import json
import os
import sys

try:
    import yaml  # type: ignore
except ImportError:
    sys.stderr.write("[workflow] PyYAML is required to resolve named workflows\n")
    sys.exit(1)

# Canonical stage order. Every shipped preset's step list is already
# canonically ordered, so re-sorting the composed set is a no-op for
# un-modified presets.
CANONICAL = ["discuss", "sdd", "plan", "implement", "verify", "review", "judge", "fix", "done"]
# Stages that pipeline.yaml `<stage>.enabled` / launch flags may toggle. The
# core stages (implement/verify/done) are not.
COMPOSABLE = ["discuss", "sdd", "plan", "review", "judge", "fix"]
# Launch flag (env) → stage. `--brainstorm` is an alias of `discuss`.
FLAG_STAGE = {
    "FLAG_REVIEW": "review",
    "FLAG_JUDGE": "judge",
    "FLAG_FIX": "fix",
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

# A project pipeline scaffolded before the presets lacks them: take presets,
# aliases and effort_tiers from the bundled default; project keys win.
try:
    _default_path = os.path.join(os.environ["MB_SD"], "..", "references", "pipeline.default.yaml")
    default_cfg = yaml.safe_load(open(_default_path, encoding="utf-8")) or {}
except Exception:
    default_cfg = {}
if isinstance(cfg.get("workflows"), dict) and cfg["workflows"]:
    cfg["workflows"] = {**(default_cfg.get("workflows") or {}), **cfg["workflows"]}
    aliases = {**((default_cfg.get("workflow") or {}).get("aliases") or {}), **aliases}
    cfg["effort_tiers"] = {**(default_cfg.get("effort_tiers") or {}), **(cfg.get("effort_tiers") or {})}

CADENCES = ("stage", "plan", "run", "off")
cli_cadence = os.environ.get("VERIFY_CADENCE", "")
if cli_cadence and cli_cadence not in CADENCES:
    sys.stderr.write(f"[workflow] --verify '{cli_cadence}' not in {', '.join(CADENCES)}\n")
    sys.exit(2)

tier = os.environ.get("TIER", "")
if tier and not requested:
    if tier == "trivial":
        sys.stderr.write(
            "[workflow] tier 'trivial': no /mb work needed — make the change and "
            "check it with one command\n"
        )
        sys.exit(2)
    tiers = cfg.get("effort_tiers")
    if not isinstance(tiers, dict) or tier not in tiers:
        sys.stderr.write(f"[workflow] unknown effort tier '{tier}' (no effort_tiers.{tier} in pipeline.yaml)\n")
        sys.exit(2)
    requested = str(tiers[tier])

host = os.environ.get("HOST", "")
host_cfg = (cfg.get("hosts") or {}).get(host) if isinstance(cfg.get("hosts"), dict) else None
host_cfg = host_cfg if isinstance(host_cfg, dict) else {}
default_name = host_cfg.get("preset") or workflow_cfg.get("default") or "execution"
workflows = cfg.get("workflows") or {}
name = requested or default_name
if not (isinstance(workflows, dict) and name in workflows):
    name = aliases.get(name, name)

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
    verify_block = spec.get("verify") if isinstance(spec.get("verify"), dict) else {}
    implement_block = spec.get("implement") if isinstance(spec.get("implement"), dict) else {}
    yaml_cadence = verify_block.get("cadence")
    self_verify = implement_block.get("self_verify") is True
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
    yaml_cadence = None
    self_verify = False
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

# Same reason: a fix-cycle fixes review findings, so it needs a review to
# consume. Without one the loop has no input and no termination signal.
if "fix" in steps and "review" not in steps:
    sys.stderr.write(
        "[workflow] fix requires review — add --review or enable review "
        "in pipeline.yaml (or drop --fix)\n"
    )
    sys.exit(2)

# A fix stage composed onto a preset that carries no loop block (e.g.
# `execution`) needs loop semantics, or the orchestrator has no returns_to and
# no cycle ceiling. Presets that define their own loop keep it verbatim.
if "fix" in steps and not loop:
    review_cfg = cfg.get("review") if isinstance(cfg.get("review"), dict) else {}
    judged = "judge" in steps
    loop = {
        "after": "judge" if judged else "review",
        "until": "judge_go" if judged else "severity_gate_pass",
        "returns_to": "verify",
        "max_cycles": review_cfg.get("max_cycles", 3),
        "on_max_cycles": review_cfg.get("on_max_cycles", "stop_for_human"),
        "approval_required": bool(review_cfg.get("approval_required", False)),
    }

# Verifier cadence: launch flag > workflow block > once at plan end (AGR-075).
cadence = cli_cadence or host_cfg.get("verify") or yaml_cadence or "plan"
if cadence not in CADENCES:
    sys.stderr.write(f"[workflow] workflows.{name}.verify.cadence '{cadence}' not in {', '.join(CADENCES)}\n")
    sys.exit(1)
if "verify" not in steps:
    cadence = "off"

resolved = {
    "name": name,
    "source": source,
    "steps": steps,
    "entrypoint": entrypoint,
    "interactive": interactive,
    "loop": loop,
    "verify_cadence": cadence,
    "self_verify": self_verify,
    "host": host,
}
sys.path.insert(0, os.environ["MB_SD"])
import mb_work_adapt  # noqa: E402

resolved["adapt"] = mb_work_adapt.load_config(path, bool(os.environ.get("NO_ADAPT")))

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
