#!/usr/bin/env bash
# mb-reviewer-resolve.sh — pick the active reviewer agent name.
#
# Usage:
#   mb-reviewer-resolve.sh [--mb <path>]
#
# Resolution:
#   1. Read pipeline.yaml: project <bank>/pipeline.yaml → references/pipeline.default.yaml.
#   2. Default: print value of `roles.reviewer.agent`.
#   3. If `roles.reviewer.override_if_skill_present.{skill, agent}` is defined
#      AND the named skill directory exists at MB_SKILLS_ROOT (or the default
#      `~/.claude/skills`), print the override `agent` value instead.
#
# Used by `commands/work.md` to decide which agent to dispatch for the review
# step. Honours pipeline.yaml regardless of installer probe results.
#
# Exit codes:
#   0 — successful resolution (always for valid inputs).
#   1 — argument error.
#   2 — pipeline.yaml read/parse failure.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

MB_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mb) MB_ARG="${2:-}"; shift 2 ;;
    --help|-h)
      cat <<'USAGE'
Usage: mb-reviewer-resolve.sh [--mb <path>]

Resolves the reviewer agent name from pipeline.yaml. Honours
`roles.reviewer.override_if_skill_present` when the named skill directory
exists in MB_SKILLS_ROOT (default ~/.claude/skills).
USAGE
      exit 0 ;;
    --*)
      echo "[error] unknown flag: $1" >&2
      exit 1 ;;
    *) MB_ARG="$1"; shift ;;
  esac
done

MB_PATH_RAW=$(mb_resolve_path "$MB_ARG")
MB_PATH="$MB_PATH_RAW"
[ -d "$MB_PATH_RAW" ] && MB_PATH=$(cd "$MB_PATH_RAW" && pwd)

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
DEFAULT_PIPELINE="$SKILL_ROOT/references/pipeline.default.yaml"
PROJECT_PIPELINE="$MB_PATH/pipeline.yaml"

if [ -f "$PROJECT_PIPELINE" ]; then
  PIPELINE_PATH="$PROJECT_PIPELINE"
elif [ -f "$DEFAULT_PIPELINE" ]; then
  PIPELINE_PATH="$DEFAULT_PIPELINE"
else
  echo "[error] no pipeline.yaml found (project: $PROJECT_PIPELINE, default: $DEFAULT_PIPELINE)" >&2
  exit 2
fi

SKILLS_ROOT="${MB_SKILLS_ROOT:-$HOME/.claude/skills}"

PIPELINE_PATH="$PIPELINE_PATH" SKILLS_ROOT="$SKILLS_ROOT" python3 - <<'PY'
import os
import sys

pipeline = os.environ["PIPELINE_PATH"]
skills_root = os.environ["SKILLS_ROOT"]

try:
    import yaml  # type: ignore
    with open(pipeline, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except ImportError:
    # Best-effort minimal parser when PyYAML missing — handles the two
    # fields we actually need:
    #   roles.reviewer.agent
    #   roles.reviewer.override_if_skill_present.{skill, agent}
    text = open(pipeline, encoding="utf-8").read()
    data = {"roles": {"reviewer": {}}}
    in_reviewer = False
    in_override = False
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        # detect block boundary by indentation
        if line.startswith("  reviewer:"):
            in_reviewer = True
            in_override = False
            continue
        if in_reviewer:
            indent = len(line) - len(line.lstrip())
            if indent <= 2 and line.strip().endswith(":") and not line.startswith("  reviewer:"):
                in_reviewer = False
                in_override = False
                continue
            if line.lstrip().startswith("agent:") and indent == 4:
                data["roles"]["reviewer"]["agent"] = line.split(":", 1)[1].strip()
            elif line.lstrip().startswith("override_if_skill_present:"):
                in_override = True
                data["roles"]["reviewer"]["override_if_skill_present"] = {}
            elif in_override and indent >= 6:
                k, _, v = line.strip().partition(":")
                data["roles"]["reviewer"]["override_if_skill_present"][k.strip()] = v.strip()
            elif in_override and indent < 6:
                in_override = False

reviewer_block = data.get("roles", {}).get("reviewer") or {}
default_agent = reviewer_block.get("agent") or "mb-reviewer"
override = reviewer_block.get("override_if_skill_present")

if isinstance(override, dict):
    skill = override.get("skill")
    override_agent = override.get("agent")
    if skill and override_agent:
        skill_dir = os.path.join(skills_root, skill)
        if os.path.isdir(skill_dir):
            print(override_agent)
            sys.exit(0)

print(default_agent)
PY
