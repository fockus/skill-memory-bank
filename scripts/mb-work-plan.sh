#!/usr/bin/env bash
# mb-work-plan.sh — emit per-stage execution plan as JSON Lines (spec §8).
#
# Usage:
#   mb-work-plan.sh [--target <ref>] [--range <expr>] [--dry-run] [--mb <path>]
#
# Output (per stage, one JSON object per line):
#   {"plan": "...", "stage_no": N, "heading": "...", "role": "...",
#    "agent": "...", "status": "pending|in-progress|done", "dod_lines": K}
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

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  sed -n '2,14p' "$0" >&2
}

TARGET=""
RANGE=""
DRY_RUN=0
MB_ARG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --target=*) TARGET="${1#--target=}"; shift ;;
    --range) RANGE="${2:-}"; shift 2 ;;
    --range=*) RANGE="${1#--range=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --mb) MB_ARG="${2:-}"; shift 2 ;;
    --mb=*) MB_ARG="${1#--mb=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[work-plan] unknown arg '$1'" >&2; usage; exit 2 ;;
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

# Apply range — get list of stage indices
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
python3 - <<'PY'
import json
import os
import re
import sys

plan_path = os.environ["PLAN_PATH"]
pipeline_path = os.environ["PIPELINE_YAML"]
stages_raw = os.environ.get("STAGES", "")
dry_run = os.environ.get("DRY_RUN") == "1"

text = open(plan_path, encoding="utf-8").read()
basename = os.path.basename(plan_path)

# Load pipeline.yaml to map role → agent
try:
    import yaml  # type: ignore
    cfg = yaml.safe_load(open(pipeline_path, encoding="utf-8")) or {}
    roles = cfg.get("roles") or {}
except Exception:
    roles = {}

ROLE_AGENT = {}
for rname, rspec in roles.items():
    if isinstance(rspec, dict) and rspec.get("agent"):
        ROLE_AGENT[rname] = rspec["agent"]

# Stage parser: split body by mb-stage markers, capture heading + content
pattern = re.compile(
    r"<!--\s*mb-stage:(\d+)\s*-->\s*\n(##\s+Stage\s+\d+[^\n]*)\n(.*?)(?=<!--\s*mb-stage:\d+\s*-->|\Z)",
    re.S,
)
stage_records = {}
for m in pattern.finditer(text):
    n = int(m.group(1))
    heading_full = m.group(2).strip()
    body = m.group(3)
    # Heading without "## Stage N: " prefix → pure heading text
    heading_clean = re.sub(r"^##\s+Stage\s+\d+:\s*", "", heading_full).strip()
    stage_records[n] = (heading_clean, body)

if not stage_records:
    sys.stderr.write(f"[work-plan] no stages in {plan_path}\n")
    sys.exit(1)

requested = [int(x) for x in stages_raw.strip().splitlines() if x.strip().isdigit()]
if not requested:
    requested = sorted(stage_records.keys())

# Role auto-detection heuristics, applied to combined heading + body lowercase.
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

def detect_status(body: str) -> str:
    bullets = re.findall(r"^\s*-\s+([⬜✅])", body, re.M)
    if not bullets:
        return "pending"
    if all(b == "✅" for b in bullets):
        return "done"
    if any(b == "✅" for b in bullets):
        return "in-progress"
    return "pending"

def count_dod(body: str) -> int:
    return len(re.findall(r"^\s*-\s+[⬜✅]", body, re.M))

if dry_run:
    print("## Execution Plan")
    print(f"plan: {basename}")
    print(f"stages: {','.join(str(s) for s in requested)}")
    print()

for n in requested:
    if n not in stage_records:
        sys.stderr.write(f"[work-plan] stage {n} missing in {basename}\n")
        sys.exit(1)
    heading, body = stage_records[n]
    role = detect_role(heading, body)
    agent = ROLE_AGENT.get(role) or ROLE_AGENT.get("developer") or f"mb-{role}"
    status = detect_status(body)
    obj = {
        "plan": basename,
        "stage_no": n,
        "heading": heading,
        "role": role,
        "agent": agent,
        "status": status,
        "dod_lines": count_dod(body),
    }
    print(json.dumps(obj, ensure_ascii=False))
PY
