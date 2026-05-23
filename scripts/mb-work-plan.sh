#!/usr/bin/env bash
# mb-work-plan.sh — emit per-stage execution plan as JSON Lines (spec §8).
#
# Usage:
#   mb-work-plan.sh [--target <ref>] [--range <expr>] [--dry-run] [--mb <path>]
#
# Output (per stage, one JSON object per line):
#   {"plan": "...", "stage_no": N, "item_no": N, "heading": "...", "role": "...",
#    "agent": "...", "status": "pending|in-progress|done", "dod_lines": K,
#    "source": "plan|spec", "kind": "stage|task", "covers": [...]}
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
	sed -n '2,16p' "$0" >&2
}

TARGET=""
RANGE=""
DRY_RUN=0
MB_ARG=""
while [ "$#" -gt 0 ]; do
	case "$1" in
	--target)
		TARGET="${2:-}"
		shift 2
		;;
	--target=*)
		TARGET="${1#--target=}"
		shift
		;;
	--range)
		RANGE="${2:-}"
		shift 2
		;;
	--range=*)
		RANGE="${1#--range=}"
		shift
		;;
	--dry-run)
		DRY_RUN=1
		shift
		;;
	--mb)
		MB_ARG="${2:-}"
		shift 2
		;;
	--mb=*)
		MB_ARG="${1#--mb=}"
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "[work-plan] unknown arg '$1'" >&2
		usage
		exit 2
		;;
	esac
done

# Resolve target
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
	python3 - "$PLAN" "$MB_ARG" <<'PY'
import re, os, sys

plan_path = sys.argv[1]
mb_arg = sys.argv[2] if len(sys.argv) > 2 else ""

text = open(plan_path, encoding="utf-8").read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
if not m:
    # No frontmatter — plain plan, no wrapper
    print("none")
    sys.exit(0)

fm = m.group(1)
ls = re.search(r"^linked_spec:\s*(\S+)\s*$", fm, re.M)
tk = re.search(r"^tasks:\s*(\S+)\s*$", fm, re.M)
linked_spec = ls.group(1) if ls else None
tasks_range = tk.group(1) if tk else None

if linked_spec is None:
    print("none")
    sys.exit(0)

# Resolve spec tasks.md relative to memory-bank root
plan_dir = os.path.dirname(os.path.realpath(plan_path))
# Try mb_arg first, then go up from plan_dir (plans/ → .memory-bank/)
if mb_arg:
    mb_root = os.path.realpath(mb_arg)
else:
    mb_root = os.path.dirname(plan_dir)

spec_tasks = os.path.join(mb_root, linked_spec, "tasks.md")
if not os.path.isfile(spec_tasks):
    sys.stderr.write(
        f"[work-plan] linked_spec tasks not found: {spec_tasks}\n"
    )
    sys.exit(1)

wrapper_basename = os.path.basename(plan_path)
tasks_range_out = tasks_range if tasks_range is not None else ""
print(f"wrapper\t{spec_tasks}\t{wrapper_basename}\t{tasks_range_out}")
PY
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
STAGES_RAW=$(bash "$RANGE_SH" "$PLAN" --range "$RANGE")

# Get effective pipeline.yaml path (for role→agent mapping)
PIPELINE_PATH=$(bash "$PIPELINE" path --mb "$MB_ARG" 2>/dev/null || true)
if [ -z "$PIPELINE_PATH" ]; then
	PIPELINE_PATH="$SCRIPT_DIR/../references/pipeline.default.yaml"
fi

PLAN_PATH="$PLAN" \
	PIPELINE_YAML="$PIPELINE_PATH" \
	STAGES="$STAGES_RAW" \
	DRY_RUN="$DRY_RUN" \
	PLAN_BASENAME="$(basename "$PLAN")" \
	WRAPPER_BASENAME="$WRAPPER_BASENAME" \
	WORK_ITEMS="$WORK_ITEMS" \
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

# Determine the plan label for output
output_plan = wrapper_basename if wrapper_basename else plan_basename

# Load pipeline.yaml to map role → agent
try:
    import yaml  # type: ignore
    cfg = yaml.safe_load(open(pipeline_path, encoding="utf-8")) or {}
    roles = cfg.get("roles") or {}
except Exception:
    roles = {}

ROLE_AGENT: dict[str, str] = {}
for rname, rspec in roles.items():
    if isinstance(rspec, dict) and rspec.get("agent"):
        ROLE_AGENT[rname] = rspec["agent"]

# Role auto-detection heuristics (applied to heading + body, lowercase).
# Order matters — first match wins.
ROLE_RULES = [
    ("ios",       [r"\bios\b", r"\bswift\b", r"\bswiftui\b", r"\bcombine\b", r"\bxcode\b"]),
    ("android",   [r"\bandroid\b", r"\bkotlin\b", r"\bjetpack\b", r"\bcompose\b"]),
    ("frontend",  [r"\breact\b", r"\bvue\b", r"\bui component\b", r"\btailwind\b", r"\bcss\b", r"\b ui\b"]),
    ("backend",   [r"\bapi\b", r"\bfastapi\b", r"\bdjango\b", r"\bpydantic\b", r"\bsqlalchemy\b", r"\bendpoint\b"]),
    ("devops",    [r"\bdocker\b", r"\bdockerfile\b", r"\bk8s\b", r"\bkubernetes\b", r"\bci\b", r"\bcd\b", r"\binfrastructure\b", r"\bterraform\b"]),
    ("qa",        [r"\bred tests\b", r"\bpytest\b", r"\bbats\b", r"\btest cases\b", r"\bcoverage\b", r"\bedge case\b"]),
    ("architect", [r"\barchitecture\b", r"\badr\b", r"\bdesign doc\b", r"\bdomain model\b", r"\binterfaces\b"]),
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


# Call mb_work_items.py via CLI to get parsed items
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

# Parse requested indices from range output
requested = [int(x) for x in stages_raw.strip().splitlines() if x.strip().isdigit()]
if not requested:
    requested = sorted(items_by_no.keys())

if dry_run:
    print("## Execution Plan")
    print(f"plan: {output_plan}")
    print(f"stages: {','.join(str(s) for s in requested)}")
    print()

for n in requested:
    if n not in items_by_no:
        sys.stderr.write(f"[work-plan] stage {n} missing in {plan_basename}\n")
        sys.exit(1)
    item = items_by_no[n]
    source = item["source"]
    heading = item["heading"]
    body = item["body"]
    covers = item["covers"]

    # Role selection is source-dependent.
    # Spec tasks are parsed by mb_work_items.py, which already honors explicit
    # **Role:** lines before applying its own heuristic. Trust that result so
    # `**Role:** developer` is not re-routed to QA just because the task body
    # mentions pytest in its Testing section. Plain plan stages keep the richer
    # work-plan heuristic for backward compatibility.
    parsed_role = item.get("role", "developer")
    if source == "spec":
        role = parsed_role
    else:
        detected_role = detect_role(heading, body)
        role = parsed_role if parsed_role != "developer" else detected_role

    agent = ROLE_AGENT.get(role) or ROLE_AGENT.get("developer") or f"mb-{role}"

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
        "status": status,
        "dod_lines": dod_count,
        "source": source,
        "kind": item["kind"],
        "covers": covers,
    }
    print(json.dumps(obj, ensure_ascii=False))
PY
