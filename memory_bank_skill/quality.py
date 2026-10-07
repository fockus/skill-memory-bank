"""Project quality settings: profile fields `quality`, `architecture`, `delivery`, `discipline`.

One source (AGR-076): the rules profile — user scope, then the project scope on top, per key.
The four principles (`quality.principles`) are also the only switch for the catalog key rules
solid/dry/kiss/yagni (AGR-077); `key_rules.profile_layer` folds them in.

CLI (invoked by `mb-profile.sh quality` and `mb-rules.sh sync`):
    python3 -m memory_bank_skill.quality resolve [--user=<path>] [--project=<path>] [--json]
    python3 -m memory_bank_skill.quality rules-md   (resolved JSON on stdin → the project RULES.md block)
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from memory_bank_skill.rules_profile import ALLOWED_ARCHITECTURES, ALLOWED_DELIVERY, ValidationError

PRINCIPLE_IDS = ("solid", "dry", "kiss", "yagni")
ON_OFF = ("on", "off")
TDD_VALUES = ("on", "off", "small+")
DISCIPLINE_VALUES = ("auto", "strict", "calm")
COVERAGE_KEYS = ("overall", "core", "infra")
CUSTOM_MAX_CHARS = 200
ARCHITECTURES = tuple(a for a in ALLOWED_ARCHITECTURES if a != "custom")
PRESETS_DIR = Path(__file__).resolve().parents[1] / "references" / "rules-presets" / "architecture"
RULES_MD_START = "<!-- mb-project-rules:start -->"
RULES_MD_END = "<!-- mb-project-rules:end -->"

DEFAULT_QUALITY = {
    "tdd": "small+",
    "testing_trophy": "on",
    "coverage": {"enabled": False, "overall": 85, "core": 95, "infra": 70},
    "principles": dict.fromkeys(PRINCIPLE_IDS, "on"),
}
# The three architecture lines the Key rules carried by default before AGR-076.
DEFAULT_ARCHITECTURE = ["clean", "fsd", "ddd"]
DEFAULT_DELIVERY = "tdd"
DEFAULT_DISCIPLINE = "auto"


def _err(field: str, code: str, message: str) -> ValidationError:
    return ValidationError(field=field, message=f"{code}: {message}")


def _choice(field: str, value: object, allowed: tuple[str, ...]) -> list[ValidationError]:
    if value in allowed:
        return []
    return [_err(field, "invalid_value", f"{value!r} not in {', '.join(allowed)}")]


def _object(field: str, value: object, allowed: tuple[str, ...]) -> list[ValidationError] | None:
    """None when `value` is an object with known keys only; else the errors."""
    if not isinstance(value, dict):
        return [_err(field, "not_an_object", f"{field} must be an object")]
    unknown = [k for k in value if k not in allowed]
    return [_err(f"{field}.{k}", "unknown_key", f"unknown key {k!r} (allowed: {', '.join(allowed)})")
            for k in unknown] or None


def validate_quality(value: object) -> list[ValidationError]:
    """Validate the `quality` profile field. Empty list = valid."""
    shape = _object("quality", value, tuple(DEFAULT_QUALITY))
    if shape is not None:
        return shape
    errors: list[ValidationError] = []
    if "tdd" in value:
        errors += _choice("quality.tdd", value["tdd"], TDD_VALUES)
    if "testing_trophy" in value:
        errors += _choice("quality.testing_trophy", value["testing_trophy"], ON_OFF)
    if "coverage" in value:
        coverage = value["coverage"]
        errors += _object("quality.coverage", coverage, ("enabled", *COVERAGE_KEYS)) or []
        if isinstance(coverage, dict):
            if "enabled" in coverage and not isinstance(coverage["enabled"], bool):
                errors.append(_err("quality.coverage.enabled", "invalid_value", "enabled must be true or false"))
            for key in (k for k in COVERAGE_KEYS if k in coverage):
                pct = coverage[key]
                if not isinstance(pct, int) or isinstance(pct, bool):
                    errors.append(_err(f"quality.coverage.{key}", "invalid_value", f"{key} must be an integer"))
                elif not 0 <= pct <= 100:
                    errors.append(_err(f"quality.coverage.{key}", "coverage_out_of_range",
                                       f"{key} must be 0..100, got {pct}"))
    if "principles" in value:
        principles = value["principles"]
        errors += _object("quality.principles", principles, PRINCIPLE_IDS) or []
        if isinstance(principles, dict):
            for key in (k for k in PRINCIPLE_IDS if k in principles):
                errors += _choice(f"quality.principles.{key}", principles[key], ON_OFF)
    return errors


def validate_architecture(value: object) -> list[ValidationError]:
    """`architecture`: a name, or a non-empty list of names and `{"custom": "<text>"}` items."""
    items = value if isinstance(value, list) else [value]
    if not items:
        return [_err("architecture", "unknown_architecture", "architecture list is empty")]
    names = ARCHITECTURES
    errors: list[ValidationError] = []
    for item in items:
        if isinstance(item, dict) and set(item) == {"custom"}:
            text = item["custom"]
            if not isinstance(text, str) or not text.strip() or "\n" in text or len(text) > CUSTOM_MAX_CHARS:
                errors.append(_err("architecture.custom", "custom_invalid",
                                   f"custom architecture needs one non-empty line ≤{CUSTOM_MAX_CHARS} chars"))
        elif item == "custom":
            errors.append(_err("architecture.custom", "custom_invalid",
                               'custom architecture needs its text: {"custom": "<text>"}'))
        elif item not in names:
            errors.append(_err("architecture", "unknown_architecture",
                               f"unknown architecture {item!r} (allowed: {', '.join(names)}, custom)"))
    return errors


def validate_discipline(value: object) -> list[ValidationError]:
    return _choice("discipline", value, DISCIPLINE_VALUES)


def validate_settings(data: dict) -> list[ValidationError]:
    """Errors of the quality-related fields a profile holds (missing fields are fine)."""
    errors: list[ValidationError] = []
    if "quality" in data:
        errors += validate_quality(data["quality"])
    if "architecture" in data:
        errors += validate_architecture(data["architecture"])
    if "discipline" in data:
        errors += validate_discipline(data["discipline"])
    return errors


def architecture_label(value: object) -> str:
    """Flat string form for consumers of the single-value `architecture` (e.g. "clean+ddd")."""
    items = value if isinstance(value, list) else [value]
    return "+".join("custom" if isinstance(i, dict) else str(i) for i in items)


def _flat(tree: dict, prefix: str = "") -> dict:
    out: dict = {}
    for key, value in tree.items():
        if isinstance(value, dict):
            out.update(_flat(value, f"{prefix}{key}."))
        else:
            out[f"{prefix}{key}"] = value
    return out


def _lookup(tree: dict, dotted: str) -> tuple[bool, object]:
    node: object = tree
    for part in dotted.split("."):
        if not isinstance(node, dict) or part not in node:
            return False, None
        node = node[part]
    return True, node


def resolve_quality(user: dict | None, project: dict | None) -> dict:
    """Effective settings: defaults, then user, then project — per leaf key — with sources."""
    defaults = {"quality": DEFAULT_QUALITY, "architecture": DEFAULT_ARCHITECTURE,
                "delivery": DEFAULT_DELIVERY, "discipline": DEFAULT_DISCIPLINE}
    # `architecture` is one leaf: a project list replaces the user list whole.
    values = _flat(defaults)
    sources = dict.fromkeys(values, "default")
    for name, layer in (("user", user or {}), ("project", project or {})):
        for key in values:
            found, value = _lookup(layer, key)
            if found:
                values[key], sources[key] = value, name
    arch = values.pop("architecture")
    items = arch if isinstance(arch, list) else [arch]
    resolved_quality = {
        "tdd": values["quality.tdd"],
        "testing_trophy": values["quality.testing_trophy"],
        "coverage": {k: values[f"quality.coverage.{k}"] for k in ("enabled", *COVERAGE_KEYS)},
        "principles": {p: values[f"quality.principles.{p}"] for p in PRINCIPLE_IDS},
    }
    return {
        "quality": resolved_quality,
        "architecture": {"names": [i for i in items if isinstance(i, str)],
                         "custom": next((i["custom"] for i in items if isinstance(i, dict)), None)},
        "delivery": values["delivery"],
        "discipline": values["discipline"],
        "sources": sources,
    }


def load_architecture_preset(name: str) -> dict:
    return json.loads((PRESETS_DIR / f"{name}.json").read_text(encoding="utf-8"))


def render_project_rules(resolved: dict) -> str:
    """The managed block of the project RULES.md: the effective settings, human-readable."""
    q, arch = resolved["quality"], resolved["architecture"]
    lines = [RULES_MD_START, "## Project quality settings", "",
             "Managed by `/mb rules set` (rules profile); text outside this block is yours.", "",
             "### Architecture"]
    for name in arch["names"]:
        preset = load_architecture_preset(name)
        lines += ["", f"**{name}** — {preset['description']}"]
        lines += [f"- [{r['severity']}] {r['rule_id'].rsplit('.', 1)[-1]}: {r['guidance']}" for r in preset["rules"]]
    if arch["custom"]:
        lines += ["", f"**custom** — {arch['custom']}"]
    cov = q["coverage"]
    coverage = (f"overall {cov['overall']}%, core/business {cov['core']}%, infrastructure {cov['infra']}%"
                if cov["enabled"] else "off (not checked)")
    lines += ["", "### Principles", "",
              " · ".join(f"{p.upper()}: {q['principles'][p]}" for p in PRINCIPLE_IDS),
              "", "### Tests", "",
              f"- TDD: {q['tdd']}" + (" (standard+ tier; small: one test per behavior)" if q["tdd"] == "small+" else ""),
              f"- Testing Trophy: {q['testing_trophy']}",
              f"- Coverage: {coverage}",
              RULES_MD_END]
    return "\n".join(lines) + "\n"


def _read(path: str | None) -> tuple[dict | None, list[ValidationError]]:
    if not path or not Path(path).is_file():
        return None, []
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    errors = validate_settings(data)
    if "delivery" in data:
        errors += _choice("delivery", data["delivery"], ALLOWED_DELIVERY)
    return (None if errors else data), errors


def _text(resolved: dict) -> str:
    flat = _flat({"quality": resolved["quality"]})
    arch = resolved["architecture"]
    flat["architecture"] = ", ".join(arch["names"] + ([f"custom: {arch['custom']}"] if arch["custom"] else []))
    flat["delivery"], flat["discipline"] = resolved["delivery"], resolved["discipline"]
    shown = {k: json.dumps(v) if isinstance(v, bool) else v for k, v in flat.items()}
    return "".join(f"{k} = {v} ({resolved['sources'][k]})\n" for k, v in shown.items())


def _cli_main(argv: list[str]) -> int:
    if argv and argv[0] == "rules-md":
        sys.stdout.write(render_project_rules(json.load(sys.stdin)))
        return 0
    if not argv or argv[0] != "resolve":
        print("Usage: quality.py resolve [--user=<p>] [--project=<p>] [--json] | rules-md < resolved.json",
              file=sys.stderr)
        return 1
    opts = dict(a[2:].split("=", 1) for a in argv[1:] if a.startswith("--") and "=" in a)
    layers, failed = [], False
    for scope in ("user", "project"):
        data, errors = _read(opts.get(scope))
        for err in errors:
            print(f"ERROR [{err.field}] {opts.get(scope)}: {err.message}", file=sys.stderr)
        failed = failed or bool(errors)
        layers.append(data)
    if failed:
        return 2
    resolved = resolve_quality(*layers)
    print(json.dumps(resolved, indent=2, ensure_ascii=False) if "--json" in argv else _text(resolved), end="")
    if "--json" in argv:
        print()
    return 0


if __name__ == "__main__":
    sys.exit(_cli_main(sys.argv[1:]))
