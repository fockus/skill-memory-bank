#!/usr/bin/env bash
# mb-work-plan.sh — emit per-stage execution plan as JSON Lines (spec §8).
#
# Usage:
#   mb-work-plan.sh [--target <ref>]... [--range <expr>] [--dry-run] [--mb <path>]
#                   [--workflow <name>] [--verify=stage|plan|run|off]
#                   [--cost premium|optimal|economy] [--host <id>] [--model <id>]
#
# Output (per stage, one JSON object per line):
#   {"plan": "...", "stage_no": N, "item_no": N, "heading": "...", "role": "...",
#    "agent": "...", "status": "pending|in-progress|done", "dod_lines": K,
#    "source": "plan|spec", "source_topic": "...", "source_path": "/abs/....md",
#    "kind": "stage|task", "covers": [...], "discipline": "strict|calm",
#    "model": "...", "model_source": "cli|role|profile|inherit", "cost": "...",
#    "host": "...", "step_models": {"verifier", "reviewer", "judge"},
#    "verify": bool, "final_verify": bool, "wave": N}
# Models: scripts/mb_work_models.py (cost tiers × host profiles, AGR-074);
# --model forces the item role only, --host overrides auto-detection.
# `verify`: run the verifier after this item; `final_verify`: the full-suite pass.
# Cadence (mb-workflow.sh): stage = every item, plan = last pending item, run =
# last pending item of the last --target (several = one run), off = none.
# `discipline` is `strict` when the resolved model matches discipline.strict_models.
# `source` is the category; source_topic/source_path locate the declaration file
# and MUST reach `mb-work-state.sh init` — the eval gate binds them (review [9]).
#
# Exit codes:
#   0  success
#   1  resolution / range / parse failure
#   2  usage error

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOLVE="$SCRIPT_DIR/mb-work-resolve.sh"
RANGE_SH="$SCRIPT_DIR/mb-work-range.sh"
PIPELINE="$SCRIPT_DIR/mb-pipeline.sh"
WORK_ITEMS="$SCRIPT_DIR/mb_work_items.py"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
	sed -n '2,30p' "$0" >&2
}

TARGETS=()
WORKFLOW=""
VERIFY=""
COST=""
HOST=""
MODEL=""
RANGE=""
DRY_RUN=0
MB_ARG=""
while [ "$#" -gt 0 ]; do
	case "$1" in
	--target) TARGETS+=("${2:-}"); shift 2 ;;
	--target=*) TARGETS+=("${1#--target=}"); shift ;;
	--workflow) WORKFLOW="${2:-}"; shift 2 ;;
	--workflow=*) WORKFLOW="${1#--workflow=}"; shift ;;
	--verify) VERIFY="${2:-}"; shift 2 ;;
	--verify=*) VERIFY="${1#--verify=}"; shift ;;
	--cost) COST="${2:-}"; shift 2 ;;
	--cost=*) COST="${1#--cost=}"; shift ;;
	--host) HOST="${2:-}"; shift 2 ;;
	--host=*) HOST="${1#--host=}"; shift ;;
	--model) MODEL="${2:-}"; shift 2 ;;
	--model=*) MODEL="${1#--model=}"; shift ;;
	--range) RANGE="${2:-}"; shift 2 ;;
	--range=*) RANGE="${1#--range=}"; shift ;;
	--dry-run) DRY_RUN=1; shift ;;
	--mb) MB_ARG="${2:-}"; shift 2 ;;
	--mb=*) MB_ARG="${1#--mb=}"; shift ;;
	-h | --help) usage; exit 0 ;;
	*) echo "[work-plan] unknown arg '$1'" >&2; usage; exit 2 ;;
	esac
done

case "$VERIFY" in
"" | stage | plan | run | off) ;;
*) echo "[work-plan] --verify '$VERIFY' not in stage, plan, run, off" >&2; exit 2 ;;
esac
case "$COST" in
"" | premium | optimal | economy) ;;
*) echo "[work-plan] --cost '$COST' not in premium, optimal, economy" >&2; exit 2 ;;
esac
[ -n "$HOST" ] || HOST=$(mb_detect_host)

# Cadence: mb-workflow.sh (flag > workflow block > plan); unresolvable config
# falls back to the flag or `plan` (AGR-075), so emission never depends on it.
CADENCE=$(bash "$SCRIPT_DIR/mb-workflow.sh" --mb "$MB_ARG" ${WORKFLOW:+--workflow "$WORKFLOW"} \
	${VERIFY:+--verify "$VERIFY"} ${HOST:+--host "$HOST"} --json 2>/dev/null |
	python3 -c 'import json,sys; print(json.load(sys.stdin)["verify_cadence"])' 2>/dev/null) || CADENCE=""
[ -n "$CADENCE" ] || CADENCE="${VERIFY:-plan}"

# Several targets = one run; under `run` only the last plan carries the verify.
if [ "${#TARGETS[@]}" -gt 1 ]; then
	[ -z "$RANGE" ] || { echo "[work-plan] --range needs a single --target" >&2; exit 2; }
	LAST=$((${#TARGETS[@]} - 1))
	DRY_FLAG=""
	[ "$DRY_RUN" -eq 0 ] || DRY_FLAG="--dry-run"
	for i in "${!TARGETS[@]}"; do
		SUB="$CADENCE"
		[ "$CADENCE" != run ] || { [ "$i" -eq "$LAST" ] && SUB=plan || SUB=off; }
		bash "$0" --target "${TARGETS[$i]}" --mb "$MB_ARG" --verify "$SUB" ${COST:+--cost "$COST"} \
			${HOST:+--host "$HOST"} ${MODEL:+--model "$MODEL"} $DRY_FLAG || exit $?
	done
	exit 0
fi
TARGET="${TARGETS[0]:-}"

if [ -n "$TARGET" ]; then
	PLAN=$(bash "$RESOLVE" "$TARGET" --mb "$MB_ARG") || exit $?
else
	PLAN=$(bash "$RESOLVE" --mb "$MB_ARG") || exit $?
fi

if [ ! -f "$PLAN" ]; then
	echo "[work-plan] resolved path is not a file: $PLAN" >&2
	exit 1
fi

# Detect plan-as-wrapper: parse linked_spec and tasks from frontmatter.
# If present, redirect PLAN to the spec's tasks.md and override RANGE.
WRAPPER_BASENAME=""
WRAPPER_INFO=$(
python3 "$SCRIPT_DIR/mb_work_plan_wrapper.py" "$PLAN" "$MB_ARG"
) || exit $?

if [ "$WRAPPER_INFO" != "none" ]; then
	SPEC_TASKS=$(printf '%s' "$WRAPPER_INFO" | cut -f2)
	WRAPPER_BASENAME=$(printf '%s' "$WRAPPER_INFO" | cut -f3)
	WRAPPER_RANGE=$(printf '%s' "$WRAPPER_INFO" | cut -f4)
	# Redirect to spec; override range only when wrapper specifies it
	PLAN="$SPEC_TASKS"
	if [ -n "$WRAPPER_RANGE" ]; then
		RANGE="$WRAPPER_RANGE"
	fi
fi

# Get filtered item indices via mb-work-range.sh
if [ -n "$RANGE" ]; then
	RANGE_REQUESTED=1
	STAGES_RAW=$(bash "$RANGE_SH" "$PLAN" --range "$RANGE") || exit $?
else
	RANGE_REQUESTED=0
	STAGES_RAW=$(bash "$RANGE_SH" "$PLAN") || exit $?
fi

# Get effective pipeline.yaml path (for role→agent mapping)
PIPELINE_PATH=$(bash "$PIPELINE" path "$MB_ARG" 2>/dev/null || true)
if [ -z "$PIPELINE_PATH" ]; then
	PIPELINE_PATH="$SCRIPT_DIR/../references/pipeline.default.yaml"
fi

PLAN_PATH="$PLAN" \
	PIPELINE_YAML="$PIPELINE_PATH" \
	STAGES="$STAGES_RAW" \
	RANGE_REQUESTED="$RANGE_REQUESTED" \
	DRY_RUN="$DRY_RUN" \
	PLAN_BASENAME="$(basename "$PLAN")" \
	WRAPPER_BASENAME="$WRAPPER_BASENAME" \
	WORK_ITEMS="$WORK_ITEMS" \
	CADENCE="$CADENCE" COST="$COST" HOST="$HOST" MODEL="$MODEL" SCRIPT_DIR="$SCRIPT_DIR" \
	python3 - <<'PY'
import json
import os
import re
import subprocess
import sys

plan_path = os.environ["PLAN_PATH"]
pipeline_path = os.environ["PIPELINE_YAML"]
stages_raw = os.environ.get("STAGES", "")
dry_run = os.environ.get("DRY_RUN") == "1"
plan_basename = os.environ["PLAN_BASENAME"]
wrapper_basename = os.environ.get("WRAPPER_BASENAME", "")
work_items_py = os.environ["WORK_ITEMS"]

output_plan = wrapper_basename if wrapper_basename else plan_basename  # label

# Load pipeline.yaml to map role → agent
try:
    import yaml  # type: ignore
    cfg = yaml.safe_load(open(pipeline_path, encoding="utf-8")) or {}
    roles = cfg.get("roles") or {}
except Exception:
    cfg, roles = {}, {}

sys.path.insert(0, os.environ["SCRIPT_DIR"])
import mb_work_models as models  # noqa: E402
import mb_work_waves  # noqa: E402

DEFAULT_CFG = models.load_default()
STRICT_MODELS = models.strict_models(cfg, DEFAULT_CFG)
HOST = os.environ.get("HOST", "")
COST = models.resolve_cost(cfg, DEFAULT_CFG, HOST, os.environ.get("COST", ""))


def model_for(role, cli_model="", legacy_developer=False):
    return models.resolve_model(role, cfg, DEFAULT_CFG, HOST, COST, cli_model, legacy_developer)


STEP_MODELS = {r: model_for(r)[0] for r in models.STEP_ROLES}
ROLE_AGENT: dict[str, str] = {}
ROLE_THINKING: dict[str, str] = {}
for rname, rspec in roles.items():
    if isinstance(rspec, dict) and rspec.get("agent"):
        ROLE_AGENT[rname] = rspec["agent"]
        if rspec.get("thinking"):
            ROLE_THINKING[rname] = rspec["thinking"]

# Role auto-detection over heading+body (lowercased); first match wins.
ROLE_RULES = [
    ("ios",       [r"\bios\b", r"\bswift\b", r"\bswiftui\b", r"\bcombine\b", r"\bxcode\b"]),
    ("android",   [r"\bandroid\b", r"\bkotlin\b", r"\bjetpack\b", r"\bcompose\b"]),
    ("frontend",  [r"\breact\b", r"\bvue\b", r"\bui component\b", r"\btailwind\b", r"\bcss\b", r"\b ui\b"]),
    ("backend",   [r"\bapi\b", r"\bfastapi\b", r"\bdjango\b", r"\bpydantic\b", r"\bsqlalchemy\b", r"\bendpoint\b"]),
    ("devops",    [r"\bdocker\b", r"\bdockerfile\b", r"\bk8s\b", r"\bkubernetes\b", r"\bci\b", r"\bcd\b", r"\binfrastructure\b", r"\bterraform\b"]),
    ("debugger",  [r"\bbugs?\b", r"\bdebug(ging)?\b", r"\bflaky\b", r"\bcrash(es|ing)?\b", r"\bfix(es)? (a |the )?regression\b", r"\bfix(es)? failing\b", r"\broot cause\b"]),
    ("qa",        [r"\bred tests\b", r"\bpytest\b", r"\bbats\b", r"\btest cases\b", r"\bcoverage\b", r"\bedge case\b"]),
    ("architect", [r"\barchitecture\b", r"\badr\b", r"\bdesign doc\b", r"\bdomain model\b", r"\binterfaces\b"]),
    ("researcher", [r"\bresearch\b", r"\binvestigate\b", r"\bsource extraction\b", r"\bbenchmark\b", r"\bcomparison\b", r"\btrade[- ]off\b", r"\boption matrix\b"]),
    ("analyst",   [r"\bmetric\b", r"\bsql\b", r"\banalytics\b", r"\bdata pipeline\b", r"\bdashboard\b"]),
]


def detect_role(heading: str, body: str) -> str:
    blob = (heading + "\n" + body).lower()
    for role, patterns in ROLE_RULES:
        for pat in patterns:
            if re.search(pat, blob):
                return role
    return "developer"


def _plan_checkbox_states(body: str) -> list[str]:
    """Return checkbox states from plan bodies.

    Active plans historically used both emoji bullets (``- ⬜`` / ``- ✅``)
    and Markdown task-list bullets (``- [ ]`` / ``- [x]``). Treat both as
    executable DoD markers so ``/mb work`` does not drop stage acceptance
    criteria when plans are authored with standard Markdown checkboxes.
    """
    states: list[str] = []
    for match in re.finditer(r"^\s*-\s+(?:([⬜✅])|\[([ xX])\])", body, re.M):
        emoji_state, markdown_state = match.groups()
        if emoji_state is not None:
            states.append("done" if emoji_state == "✅" else "pending")
        else:
            states.append("done" if markdown_state.lower() == "x" else "pending")
    return states


def detect_status_plan(body: str) -> str:
    """Status detection for plan files using emoji or Markdown checkboxes."""
    states = _plan_checkbox_states(body)
    if not states:
        return "pending"
    if all(state == "done" for state in states):
        return "done"
    if any(state == "done" for state in states):
        return "in-progress"
    return "pending"


def count_dod_plan(body: str) -> int:
    """Count emoji and Markdown DoD bullets in plan-style body."""
    return len(_plan_checkbox_states(body))


result = subprocess.run(
    ["python3", work_items_py, plan_path],
    capture_output=True,
    text=True,
)
if result.returncode != 0:
    sys.stderr.write(result.stderr)
    sys.exit(result.returncode)

# Parse JSON Lines from mb_work_items.py
raw_items: list[dict] = []
for line in result.stdout.strip().splitlines():
    line = line.strip()
    if line.startswith("{"):
        raw_items.append(json.loads(line))

if not raw_items:
    sys.stderr.write(f"[work-plan] no stages in {plan_path}\n")
    sys.exit(1)

# Build index: item_no → item
items_by_no: dict[int, dict] = {item["item_no"]: item for item in raw_items}

range_requested = os.environ.get("RANGE_REQUESTED") == "1"
requested = [int(x) for x in stages_raw.strip().splitlines() if x.strip().isdigit()]
if not requested:
    if range_requested:
        sys.stderr.write("[work-plan] range produced no stages\n")
        sys.exit(1)
    requested = sorted(items_by_no.keys())

if dry_run:
    print("## Execution Plan")
    print(f"plan: {output_plan}")
    print(f"stages: {','.join(str(s) for s in requested)}")
    print()

cadence = os.environ.get("CADENCE", "plan")
emitted = []

for n in requested:
    if n not in items_by_no:
        sys.stderr.write(f"[work-plan] stage {n} missing in {plan_basename}\n")
        sys.exit(1)
    item = items_by_no[n]
    source = item["source"]
    heading = item["heading"]
    body = item["body"]
    covers = item["covers"]

    # Role selection: an explicit **Role:** line (flagged by mb_work_items.py)
    # always wins, so `**Role:** developer` is not re-routed to QA just because
    # the Testing section mentions pytest. Spec tasks trust the parser fully;
    # plan stages without an explicit role keep the richer work-plan heuristic.
    parsed_role = item.get("role", "developer")
    if source == "spec" or item.get("role_explicit"):
        role = parsed_role
    else:
        detected_role = detect_role(heading, body)
        role = parsed_role if parsed_role != "developer" else detected_role

    agent = ROLE_AGENT.get(role) or ROLE_AGENT.get("developer") or f"mb-{role}"
    model, model_source = model_for(role, os.environ.get("MODEL", ""), legacy_developer=True)
    thinking = ROLE_THINKING.get(role) or ROLE_THINKING.get("developer", "")

    # dod_lines and status: source-dependent
    if source == "plan":
        dod_count = count_dod_plan(body)
        status = detect_status_plan(body)
    else:
        # spec: mb_work_items.py uses - [ ] / - [x] style
        dod_count = len(item.get("dod_lines") or [])
        status = item.get("status", "pending")

    obj = {
        "plan": output_plan,
        "stage_no": n,
        "item_no": n,
        "heading": heading,
        "role": role,
        "agent": agent,
        "model": model,
        "thinking": thinking,
        "status": status,
        "dod_lines": dod_count,
        "source": source,
        # Locators; passing the bare category to `init` made every eval lookup
        # target `<bank>/specs/spec/tasks.md` and ungated it (review [9]).
        "source_topic": item.get("topic", ""),
        "source_path": os.path.realpath(plan_path),
        "kind": item["kind"],
        "covers": covers,
        "discipline": models.discipline_for(model, STRICT_MODELS),
        "model_source": model_source,
        "cost": COST,
        "host": HOST,
        "step_models": STEP_MODELS,
    }
    emitted.append(obj)

# The verify pass goes after the last item still to run; a resumed plan whose
# final stage is already done would otherwise never get verified.
pending = [i for i, o in enumerate(emitted) if o["status"] != "done"]
last = pending[-1] if pending else len(emitted) - 1
waves = mb_work_waves.assign_waves([items_by_no[o["item_no"]] for o in emitted])
for i, obj in enumerate(emitted):
    obj["verify"] = cadence == "stage" or (cadence in ("plan", "run") and i == last)
    obj["final_verify"] = cadence != "off" and i == last
    obj["wave"] = waves[i]  # parallel wave (mb_work_waves.py, AGR-073)
    print(json.dumps(obj, ensure_ascii=False))
PY
