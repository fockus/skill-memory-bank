"""Schema of the `team:` block of pipeline.yaml (/mb team, AGR-097).

Shared by the whole-file validator (mb_pipeline_validate_core.py), the team
config reader (mb_team_config.py) and the track pipeline resolver
(mb_team_pipeline.py), so a value the validator accepts is a value the
resolver can use. Errors go through `err(msg)` and name the field.
"""

from __future__ import annotations

import re

SIZES = ("trivial", "small", "standard", "large", "extra")
LENSES = ("logic", "tests", "code_rules", "security", "scalability")
LENS_ALIASES = {"quality": "code_rules"}
ENUMS = {
    "mode": ("work",),
    "work": ("orchestrated",),
    "tdd": ("required", "optional"),
    "verifier": ("none", "plan-verifier"),
    "review": ("none", "single", "lenses"),
    "effort": ("low", "medium", "high"),
}
RETIRED = {"mode": ("direct",), "work": ("light",)}  # AGR-103 / REQ-001
PIPELINE_KEYS = (*ENUMS, "lenses", "models")
ROLE_MODEL_KEYS = ("executor", "verifier", "reviewer", "lead", "lenses")
SEVERITIES = ("blocker", "major", "medium", "minor")
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$")

_TEAM_KEYS = ("default_size", "max_parallel", "presets", "overrides", "rules", "review",
              "resources", "checkpoint")
_REVIEW_KEYS = ("enabled", "lenses", "clean_when", "max_cycles", "models")
_RESOURCE_KEYS = ("kind", "scope", "preconditions", "stop_threshold", "maintenance",
                  "watch_interval_s", "poll_s")
_PRECONDITION_KEYS = ("free_disk_gb", "disk_path", "check")
_STOP_KEYS = ("free_disk_gb", "check")
_CHECKPOINT_KEYS = ("dir", "max_untracked_mb", "extra")


def normalize_lens(name) -> str | None:
    name = LENS_ALIASES.get(name, name)
    return name if name in LENSES else None


def _is_int(value, minimum: int = 0) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= minimum


def _unknown(err, prefix: str, block: dict, allowed) -> None:
    for key in block:
        if key not in allowed:
            err(f"{prefix}.{key}: unknown key; allowed {list(allowed)}")


def _mapping(err, prefix: str, value) -> dict:
    if value is None:
        return {}
    if not isinstance(value, dict):
        err(f"{prefix}: must be a mapping")
        return {}
    return value


def _string(err, field: str, value) -> None:
    if not isinstance(value, str) or not value:
        err(f"{field}: must be a non-empty string (got {value!r})")


def check_lenses(err, field: str, value) -> None:
    if not isinstance(value, list):
        err(f"{field}: must be a list of lenses {list(LENSES)}")
        return
    bad = [v for v in value if normalize_lens(v) is None]
    if bad:
        err(f"{field}: unknown lens(es) {bad}; allowed {list(LENSES)} (alias quality)")


def check_value(err, field: str, key: str, value) -> None:
    """One pipeline field (`mode`, `lenses`, …); `field` is the full name for messages."""
    if key in ENUMS:
        if value in RETIRED.get(key, ()):
            err(f"{field}: {value!r} is retired (REQ-001: every track runs through /mb work); "
                f"use {key}: {ENUMS[key][0]}")
        elif value not in ENUMS[key]:
            err(f"{field}: {value!r} not in {list(ENUMS[key])}")
    elif key == "lenses":
        check_lenses(err, field, value)


def check_models(err, field: str, models) -> None:
    models = _mapping(err, field, models)
    for key, value in models.items():
        if key == "lens":
            for lens, model in _mapping(err, f"{field}.lens", value).items():
                if normalize_lens(lens) is None:
                    err(f"{field}.lens.{lens}: unknown lens; allowed {list(LENSES)}")
                _string(err, f"{field}.lens.{lens}", model)
        elif key in ROLE_MODEL_KEYS:
            _string(err, f"{field}.{key}", value)
        else:
            err(f"{field}.{key}: unknown key; allowed {[*ROLE_MODEL_KEYS, 'lens']}")


def normalize(team):
    """`verifier: none` is None to the stdlib parser and "none" to PyYAML; unify to "none"."""
    if not isinstance(team, dict):
        return team
    presets = team.get("presets")
    blocks = [team.get("overrides"), *(presets.values() if isinstance(presets, dict) else ())]
    for block in blocks:
        if isinstance(block, dict):
            for key in ("verifier", "review"):
                if key in block and block[key] is None:
                    block[key] = "none"
    return team


def check_pipeline_fields(err, prefix: str, block) -> None:
    block = _mapping(err, prefix, block)
    _unknown(err, prefix, block, PIPELINE_KEYS)
    for key, value in block.items():
        if key == "models":
            check_models(err, f"{prefix}.models", value)
        elif key in PIPELINE_KEYS:
            check_value(err, f"{prefix}.{key}", key, value)


def _check_review(err, review) -> None:
    review = _mapping(err, "team.review", review)
    _unknown(err, "team.review", review, _REVIEW_KEYS)
    if "enabled" in review and not isinstance(review["enabled"], bool):
        err("team.review.enabled: must be boolean")
    if "lenses" in review:
        check_lenses(err, "team.review.lenses", review["lenses"])
    clean = _mapping(err, "team.review.clean_when", review.get("clean_when"))
    for sev, limit in clean.items():
        if sev not in SEVERITIES:
            err(f"team.review.clean_when.{sev}: unknown severity; allowed {list(SEVERITIES)}")
        elif not _is_int(limit):
            err(f"team.review.clean_when.{sev}: must be int >= 0")
    if "max_cycles" in review and not _is_int(review["max_cycles"], 1):
        err("team.review.max_cycles: must be int >= 1")
    if "models" in review:
        check_models(err, "team.review.models", review["models"])


def _check_resource(err, name, spec) -> None:
    if not isinstance(name, str) or not NAME_RE.match(name):
        err(f"team.resources: invalid name {name!r} (letters, digits, '_' and '-', max 32)")
        return
    prefix = f"team.resources.{name}"
    spec = _mapping(err, prefix, spec)
    _unknown(err, prefix, spec, _RESOURCE_KEYS)
    if spec.get("kind", "mutex") != "mutex":
        err(f"{prefix}.kind: {spec['kind']!r} not in ['mutex']")
    if spec.get("scope", "host") not in ("host", "bank"):
        err(f"{prefix}.scope: {spec['scope']!r} not in ['host', 'bank']")
    for block_name, allowed in (("preconditions", _PRECONDITION_KEYS), ("stop_threshold", _STOP_KEYS)):
        block = _mapping(err, f"{prefix}.{block_name}", spec.get(block_name))
        _unknown(err, f"{prefix}.{block_name}", block, allowed)
        if "free_disk_gb" in block and not _is_int(block["free_disk_gb"]):
            err(f"{prefix}.{block_name}.free_disk_gb: must be int >= 0")
        for key in ("disk_path", "check"):
            if block.get(key) is not None:
                _string(err, f"{prefix}.{block_name}.{key}", block[key])
    if spec.get("maintenance") is not None:
        _string(err, f"{prefix}.maintenance", spec["maintenance"])
    for key in ("watch_interval_s", "poll_s"):
        if key in spec and not _is_int(spec[key], 1):
            err(f"{prefix}.{key}: must be int >= 1")


def _check_checkpoint(err, checkpoint) -> None:
    checkpoint = _mapping(err, "team.checkpoint", checkpoint)
    _unknown(err, "team.checkpoint", checkpoint, _CHECKPOINT_KEYS)
    for key in ("dir", "extra"):
        if checkpoint.get(key) is not None:
            _string(err, f"team.checkpoint.{key}", checkpoint[key])
    if "max_untracked_mb" in checkpoint and not _is_int(checkpoint["max_untracked_mb"]):
        err("team.checkpoint.max_untracked_mb: must be int >= 0")


def nested_inline_errors(text: str, err) -> int:
    """Flag `{…{…}…}` / `[…{…}…]` inside `team:` (design D6); returns the count.

    The stdlib parser reads a nested inline map as a string while PyYAML reads a
    dict, so the two paths would validate different configs. Checked on text,
    because after parsing a nested inline map is indistinguishable from a block.
    """
    from mb_pipeline_minimal_yaml import strip_comment

    count = 0
    path: list[tuple[int, str]] = []
    in_team = False
    for raw in text.splitlines():
        line = strip_comment(raw).rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        if indent == 0:
            in_team = line.strip() == "team:"
            path = []
            continue
        if not in_team:
            continue
        key, _sep, value = line.strip().partition(":")
        path = [p for p in path if p[0] < indent] + [(indent, key.strip())]
        value = value.strip()
        if value[:1] in "{[" and any(c in value[1:-1] for c in "{["):
            err(f"team.{'.'.join(p[1] for p in path)}: nested inline mapping or list; use a block mapping")
            count += 1
    return count


def validate(team, err, text: str | None = None) -> None:
    """Validate the `team:` value; `text` (the whole file) enables the D6 check."""
    if team is None:
        return
    if text is not None and nested_inline_errors(text, err):
        return  # the two parsers disagree on this block; structural errors would differ
    team = _mapping(err, "team", normalize(team))
    _unknown(err, "team", team, _TEAM_KEYS)
    if "default_size" in team and team["default_size"] not in SIZES:
        err(f"team.default_size: {team['default_size']!r} not in {list(SIZES)}")
    if "max_parallel" in team and not _is_int(team["max_parallel"], 1):
        err("team.max_parallel: must be int >= 1")
    presets = _mapping(err, "team.presets", team.get("presets"))
    for size, block in presets.items():
        if size not in SIZES:
            err(f"team.presets.{size}: unknown size; allowed {list(SIZES)}")
        else:
            check_pipeline_fields(err, f"team.presets.{size}", block)
    if "overrides" in team:
        check_pipeline_fields(err, "team.overrides", team["overrides"])
    rules = team.get("rules")
    if rules is not None and (not isinstance(rules, list) or not all(isinstance(r, str) and r for r in rules)):
        err("team.rules: must be a list of non-empty strings")
    if "review" in team:
        _check_review(err, team["review"])
    for name, spec in _mapping(err, "team.resources", team.get("resources")).items():
        _check_resource(err, name, spec)
    if "checkpoint" in team:
        _check_checkpoint(err, team["checkpoint"])
