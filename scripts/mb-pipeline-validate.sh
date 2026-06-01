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

usage() {
  cat >&2 <<'USAGE'
Usage: mb-pipeline-validate.sh <path-to-pipeline.yaml>

Validates the file against the spec §9 schema:
  - required top-level keys (version, roles, stage_pipeline, budget,
    protected_paths, sprint_context_guard, review_rubric, sdd)
  - version == 1
  - roles entries have an 'agent' field
  - stage_pipeline references only declared roles ('auto' permitted on implement)
  - severity_gate keys ⊆ {blocker, major, minor}, values int >= 0
  - max_cycles >= 1, on_max_cycles ∈ {stop_for_human, continue_with_warning}
  - sprint_context_guard.hard_stop_tokens > soft_warn_tokens, both > 0
  - budget.warn_at_percent / stop_at_percent ∈ [0, 100]
  - review_rubric: 5 sections, each non-empty list of strings
  - sdd.covers_requirements_policy ∈ {warn, block, off}
USAGE
}

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

case "$1" in
  -h|--help) usage; exit 0 ;;
esac

PATH_ARG="$1"

if [ ! -f "$PATH_ARG" ]; then
  echo "[validate] file not found: $PATH_ARG" >&2
  exit 1
fi

MB_PIPELINE_PATH="$PATH_ARG" python3 - <<'PY'
import os
import sys

try:
    import yaml  # type: ignore
except ImportError:
    yaml = None

path = os.environ["MB_PIPELINE_PATH"]
errors = []


def err(msg: str) -> None:
    errors.append(msg)


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
    value = value.strip()
    if not value:
        return None
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1]
    lowered = value.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    if lowered in {"null", "none", "~"}:
        return None
    try:
        return int(value)
    except ValueError:
        return value


def parse_inline_list(value: str) -> list:
    inner = value.strip()[1:-1].strip()
    if not inner:
        return []
    return [parse_scalar(part.strip()) for part in inner.split(",")]


def parse_inline_map(value: str) -> dict:
    inner = value.strip()[1:-1].strip()
    result = {}
    if not inner:
        return result
    for part in inner.split(","):
        key, sep, raw_value = part.partition(":")
        if sep:
            result[key.strip()] = parse_scalar(raw_value)
    return result


def parse_value(value: str):
    value = value.strip()
    if value.startswith("[") and value.endswith("]"):
        return parse_inline_list(value)
    if value.startswith("{") and value.endswith("}"):
        return parse_inline_map(value)
    return parse_scalar(value)


def block_lines(lines: list[str], name: str) -> list[tuple[int, str]]:
    block: list[tuple[int, str]] = []
    in_block = False
    for raw in lines:
        line = strip_comment(raw).rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()
        if not in_block:
            if indent == 0 and stripped == f"{name}:":
                in_block = True
            continue
        if indent == 0 and not stripped.startswith("-"):
            break
        block.append((indent, stripped))
    return block


def parse_simple_mapping(lines: list[str], name: str) -> dict:
    result = {}
    for indent, stripped in block_lines(lines, name):
        if indent != 2 or stripped.startswith("-"):
            continue
        key, sep, value = stripped.partition(":")
        if sep:
            result[key.strip()] = parse_value(value)
    return result


def parse_simple_list(lines: list[str], name: str) -> list:
    result = []
    for _indent, stripped in block_lines(lines, name):
        if stripped.startswith("- "):
            result.append(parse_value(stripped[2:]))
    return result


def parse_roles(lines: list[str]) -> dict:
    roles = {}
    current = None
    for indent, stripped in block_lines(lines, "roles"):
        if indent == 2:
            key, sep, value = stripped.partition(":")
            if not sep:
                continue
            current = key.strip()
            roles[current] = parse_value(value) if value.strip() else {}
        elif indent == 4 and current:
            key, sep, value = stripped.partition(":")
            if sep:
                roles.setdefault(current, {})[key.strip()] = parse_value(value)
    return roles


def parse_stage_pipeline(lines: list[str]) -> list[dict]:
    steps: list[dict] = []
    current = None
    nested_key = None
    for indent, stripped in block_lines(lines, "stage_pipeline"):
        if indent == 2 and stripped.startswith("- "):
            current = {}
            steps.append(current)
            nested_key = None
            item = stripped[2:]
            key, sep, value = item.partition(":")
            if sep:
                current[key.strip()] = parse_value(value)
        elif indent == 4 and current is not None:
            key, sep, value = stripped.partition(":")
            if not sep:
                continue
            nested_key = None
            if value.strip():
                current[key.strip()] = parse_value(value)
            else:
                current[key.strip()] = [] if key.strip() in {"checks"} else {}
                nested_key = key.strip()
        elif indent == 6 and current is not None and nested_key:
            if stripped.startswith("- ") and isinstance(current[nested_key], list):
                current[nested_key].append(parse_value(stripped[2:]))
            elif isinstance(current[nested_key], dict):
                key, sep, value = stripped.partition(":")
                if sep:
                    current[nested_key][key.strip()] = parse_value(value)
    return steps


def parse_review_rubric(lines: list[str]) -> dict:
    rubric = {}
    current = None
    for indent, stripped in block_lines(lines, "review_rubric"):
        if indent == 2:
            key, sep, _value = stripped.partition(":")
            if sep:
                current = key.strip()
                rubric[current] = []
        elif indent == 4 and current and stripped.startswith("- "):
            rubric[current].append(parse_value(stripped[2:]))
    return rubric


def minimal_pipeline_load(text: str) -> dict:
    lines = text.splitlines()
    cfg = {}
    for raw in lines:
        line = strip_comment(raw).rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()
        if indent == 0 and ":" in stripped:
            key, _sep, value = stripped.partition(":")
            if value.strip():
                cfg[key.strip()] = parse_value(value)
    cfg["roles"] = parse_roles(lines)
    cfg["stage_pipeline"] = parse_stage_pipeline(lines)
    cfg["budget"] = parse_simple_mapping(lines, "budget")
    cfg["protected_paths"] = parse_simple_list(lines, "protected_paths")
    cfg["sprint_context_guard"] = parse_simple_mapping(lines, "sprint_context_guard")
    cfg["review_rubric"] = parse_review_rubric(lines)
    cfg["sdd"] = parse_simple_mapping(lines, "sdd")
    return cfg


with open(path, "r", encoding="utf-8") as fh:
    text = fh.read()

if not text.strip():
    err("empty file")

if yaml is None:
    cfg = minimal_pipeline_load(text) if text.strip() else None
else:
    try:
        cfg = yaml.safe_load(text) if text.strip() else None
    except yaml.YAMLError as exc:
        err(f"YAML parse error: {exc}")
        cfg = None

if cfg is None:
    for e in errors:
        sys.stderr.write(f"[validate] {e}\n")
    sys.exit(1)

if not isinstance(cfg, dict):
    sys.stderr.write("[validate] top-level must be a mapping\n")
    sys.exit(1)

REQUIRED = (
    "version",
    "roles",
    "stage_pipeline",
    "budget",
    "protected_paths",
    "sprint_context_guard",
    "review_rubric",
    "sdd",
)
for k in REQUIRED:
    if k not in cfg:
        err(f"missing required top-level key: {k}")

if cfg.get("version") != 1:
    err(f"version: expected 1, got {cfg.get('version')!r}")

# ── roles ────────────────────────────────────────────────────────────
roles = cfg.get("roles") or {}
if not isinstance(roles, dict):
    err("roles: must be a mapping")
    roles = {}
for rname, rspec in roles.items():
    if not isinstance(rspec, dict):
        err(f"roles.{rname}: must be a mapping")
        continue
    if "agent" not in rspec or not rspec["agent"]:
        err(f"roles.{rname}: missing 'agent'")

# ── stage_pipeline ──────────────────────────────────────────────────
sp = cfg.get("stage_pipeline")
if not isinstance(sp, list) or not sp:
    err("stage_pipeline: must be a non-empty list")
    sp = []

valid_max_cycles = {"stop_for_human", "continue_with_warning"}
SEVERITY_KEYS = {"blocker", "major", "minor"}
ALLOWED_ROLE_NAMES = set(roles.keys()) | {"auto"}

for idx, step in enumerate(sp):
    if not isinstance(step, dict):
        err(f"stage_pipeline[{idx}]: must be a mapping")
        continue
    name = step.get("step", f"<idx{idx}>")
    role = step.get("role")
    if role is None:
        err(f"stage_pipeline[{name}]: missing 'role'")
    elif role not in ALLOWED_ROLE_NAMES:
        err(f"stage_pipeline[{name}]: role '{role}' not declared in roles")
    if name == "review":
        gate = step.get("severity_gate") or {}
        if not isinstance(gate, dict):
            err(f"stage_pipeline[review].severity_gate: must be a mapping")
            gate = {}
        unknown = set(gate.keys()) - SEVERITY_KEYS
        if unknown:
            err(f"stage_pipeline[review].severity_gate: unknown keys {sorted(unknown)}; allowed {sorted(SEVERITY_KEYS)}")
        for sev_k, sev_v in gate.items():
            if not isinstance(sev_v, int) or isinstance(sev_v, bool) or sev_v < 0:
                err(f"stage_pipeline[review].severity_gate.{sev_k}: must be int >= 0")
        mc = step.get("max_cycles")
        if not isinstance(mc, int) or isinstance(mc, bool) or mc < 1:
            err(f"stage_pipeline[review].max_cycles: must be int >= 1 (got {mc!r})")
        omc = step.get("on_max_cycles")
        if omc not in valid_max_cycles:
            err(f"stage_pipeline[review].on_max_cycles: '{omc}' not in {sorted(valid_max_cycles)}")

# ── budget ──────────────────────────────────────────────────────────
budget = cfg.get("budget") or {}
if not isinstance(budget, dict):
    err("budget: must be a mapping")
    budget = {}
for pkey in ("warn_at_percent", "stop_at_percent"):
    if pkey in budget:
        v = budget[pkey]
        if not isinstance(v, (int, float)) or isinstance(v, bool) or not (0 <= v <= 100):
            err(f"budget.{pkey}: must be number in [0, 100] (got {v!r})")
if "default_limit" in budget and budget["default_limit"] is not None:
    v = budget["default_limit"]
    if not isinstance(v, (int, float)) or isinstance(v, bool) or v < 0:
        err(f"budget.default_limit: must be null or non-negative number")

# ── protected_paths ────────────────────────────────────────────────
pp = cfg.get("protected_paths")
if not isinstance(pp, list):
    err("protected_paths: must be a list")
else:
    for i, item in enumerate(pp):
        if not isinstance(item, str) or not item:
            err(f"protected_paths[{i}]: must be a non-empty string")

# ── sprint_context_guard ───────────────────────────────────────────
guard = cfg.get("sprint_context_guard") or {}
if not isinstance(guard, dict):
    err("sprint_context_guard: must be a mapping")
    guard = {}
soft = guard.get("soft_warn_tokens")
hard = guard.get("hard_stop_tokens")
if not isinstance(soft, int) or isinstance(soft, bool) or soft <= 0:
    err("sprint_context_guard.soft_warn_tokens: must be int > 0")
if not isinstance(hard, int) or isinstance(hard, bool) or hard <= 0:
    err("sprint_context_guard.hard_stop_tokens: must be int > 0")
if isinstance(soft, int) and isinstance(hard, int) and not isinstance(soft, bool) and not isinstance(hard, bool):
    if hard <= soft:
        err(f"sprint_context_guard: hard_stop_tokens ({hard}) must be > soft_warn_tokens ({soft})")

# ── review_rubric ─────────────────────────────────────────────────
rubric = cfg.get("review_rubric") or {}
if not isinstance(rubric, dict):
    err("review_rubric: must be a mapping")
    rubric = {}
REQUIRED_RUBRIC = ("logic", "code_rules", "security", "scalability", "tests")
for sec in REQUIRED_RUBRIC:
    if sec not in rubric:
        err(f"review_rubric.{sec}: missing")
        continue
    items = rubric[sec]
    if not isinstance(items, list) or not items:
        err(f"review_rubric.{sec}: must be a non-empty list")
        continue
    for i, item in enumerate(items):
        if not isinstance(item, str) or not item.strip():
            err(f"review_rubric.{sec}[{i}]: must be a non-empty string")

# ── sdd ────────────────────────────────────────────────────────────
sdd = cfg.get("sdd") or {}
if not isinstance(sdd, dict):
    err("sdd: must be a mapping")
    sdd = {}
for bool_key in (
    "require_ears_in_sdd_command",
    "require_ears_in_plan_command",
    "require_ears_in_plan_with_sdd_flag",
):
    if bool_key not in sdd:
        err(f"sdd.{bool_key}: missing")
    elif not isinstance(sdd[bool_key], bool):
        err(f"sdd.{bool_key}: must be boolean")
policy = sdd.get("covers_requirements_policy")
if policy not in ("warn", "block", "off"):
    err(f"sdd.covers_requirements_policy: must be one of warn|block|off (got {policy!r})")
if "full_mode_path" not in sdd or not isinstance(sdd.get("full_mode_path"), str):
    err("sdd.full_mode_path: missing or not a string")
# Optional opt-in gate: when present, must be boolean. Absent → treated as false.
if "require_scenarios" in sdd and not isinstance(sdd["require_scenarios"], bool):
    err("sdd.require_scenarios: must be boolean")

# ── final ─────────────────────────────────────────────────────────
if errors:
    for e in errors:
        sys.stderr.write(f"[validate] {e}\n")
    sys.exit(1)
sys.exit(0)
PY
