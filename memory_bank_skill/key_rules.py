"""Key-rules catalog: validation of the profile field `key_rules` and scope resolution.

The catalog lives in `rules/key-rules.json`; the user's selection lives in the
existing rules profile (`references/rules-profile.schema.md`, field `key_rules`).

CLI (invoked by `mb-profile.sh key-rules` and `mb-rules.sh render`):
    python3 -m memory_bank_skill.key_rules resolve [--user=<path>] [--project=<path>]
        [--catalog=<path>] [--json]
    python3 -m memory_bank_skill.key_rules block --pointer=<line> [--base=<resolved.json>]
        (resolved JSON on stdin; --base = the user-level selection → delta block, AGR-083)
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from memory_bank_skill.quality import (
    PRINCIPLE_IDS,
    load_architecture_preset,
    resolve_quality,
    validate_settings,
)
from memory_bank_skill.rules_profile import ValidationError

CATALOG_PATH = Path(__file__).resolve().parents[1] / "rules" / "key-rules.json"
CUSTOM_MAX_CHARS = 200
_BUCKETS = ("enabled", "disabled", "custom")
BLOCK_START = "<!-- mb-key-rules:start -->"
BLOCK_END = "<!-- mb-key-rules:end -->"
STRICT_REPLACES = "targeted-verification"
STRICT_ID = "strict-discipline"
# Former catalog toggles now set through the profile `architecture` field (AGR-076).
MOVED_TO_ARCHITECTURE = ("clean-architecture", "fsd", "ddd-folders", "mobile-udf", "backend-macro")
_SET_HINT = {"architecture": "architecture <name[,name]|custom:text>", "quality.tdd": "tdd on|off|small+",
             "quality.testing_trophy": "trophy on|off", "quality.coverage": "coverage off|<overall>/<core>/<infra>"}


class SelectionError(Exception):
    """An edit the catalog or the profile settings do not allow (`mb-rules.sh` exit 2)."""


def load_catalog(path: Path | str | None = None) -> dict:
    return json.loads(Path(path or CATALOG_PATH).read_text(encoding="utf-8"))


def _err(field: str, code: str, message: str) -> ValidationError:
    # The reason code leads the message so callers can match on it.
    return ValidationError(field=field, message=f"{code}: {message}")


def validate_key_rules(value: object, catalog: dict) -> list[ValidationError]:
    """Validate a `key_rules` profile field against the catalog. Empty list = valid."""
    if not isinstance(value, dict):
        return [_err("key_rules", "not_an_object", "key_rules must be an object")]
    errors = [_err(f"key_rules.{k}", "unknown_key", f"unknown key {k!r} (allowed: {', '.join(_BUCKETS)})")
              for k in value if k not in _BUCKETS]
    rules = {r["id"]: r for r in catalog["rules"]}
    sources = {r["id"]: r["source"] for r in catalog["rules"] if "source" in r}
    sources.update(dict.fromkeys(MOVED_TO_ARCHITECTURE, "architecture"))
    for bucket in _BUCKETS:
        items = value.get(bucket, [])
        if not isinstance(items, list) or not all(isinstance(i, str) for i in items):
            errors.append(_err(f"key_rules.{bucket}", "not_a_list", f"{bucket} must be a list of strings"))
            continue
        for item in items:
            if bucket == "custom":
                if not item.strip() or "\n" in item or len(item) > CUSTOM_MAX_CHARS:
                    errors.append(_err("key_rules.custom", "custom_invalid",
                                       f"custom rule must be one non-empty line ≤{CUSTOM_MAX_CHARS} chars: {item[:40]!r}"))
            elif item in sources:
                errors.append(_err(f"key_rules.{bucket}.{item}", "profile_setting",
                                   f"{item!r} is a profile setting: mb-rules.sh set {_SET_HINT[sources[item]]}"))
            elif item not in rules:
                errors.append(_err(f"key_rules.{bucket}.{item}", "unknown_rule", f"unknown key rule id {item!r}"))
            elif item in PRINCIPLE_IDS:
                errors.append(_err(f"key_rules.{bucket}.{item}", "principle_in_quality",
                                   f"principle {item!r} is switched via quality.principles.{item}: on|off"))
            elif bucket == "disabled" and rules[item]["locked"]:
                errors.append(_err(f"key_rules.disabled.{item}", "locked_rule",
                                   f"locked rule {item!r} cannot be disabled"))
    return errors


def profile_layer(data: dict) -> dict:
    """The profile's key_rules buckets with `quality.principles` folded in — the only switch
    for the four principle rules (validation keeps their ids out of the buckets)."""
    layer = {k: list((data.get("key_rules") or {}).get(k, [])) for k in _BUCKETS}
    principles = (data.get("quality") or {}).get("principles") or {}
    layer["enabled"] += [p for p in PRINCIPLE_IDS if principles.get(p) == "on"]
    layer["disabled"] += [p for p in PRINCIPLE_IDS if principles.get(p) == "off"]
    return layer


def resolve_discipline(user: dict | None, project: dict | None) -> str:
    """`discipline` setting: project, else user, else auto."""
    return (project or {}).get("discipline") or (user or {}).get("discipline") or "auto"


def resolve_key_rules(user: dict | None, project: dict | None, catalog: dict) -> dict:
    """Effective rules: defaults, then user, then project on top; locked always on; catalog order.

    Rows with a `source` always pass: `apply_settings` decides them from the profile settings."""
    active = {r["id"]: r["default"] or r["locked"] or "source" in r for r in catalog["rules"]}
    for layer in (user or {}, project or {}):
        active.update(dict.fromkeys(layer.get("enabled", []), True))
        active.update({i: False for i in layer.get("disabled", []) if i in active})
    keys = ("id", "group", "text", "locked", "ref", "source", "variants")
    rules = [{k: r[k] for k in keys if k in r} for r in catalog["rules"] if active[r["id"]] or r["locked"]]
    custom = [*(user or {}).get("custom", []), *(project or {}).get("custom", [])]
    return {"rules": rules, "custom": custom}


def _architecture_lines(arch: dict) -> list[str]:
    lines = [load_architecture_preset(name)["one_liner"] for name in arch["names"]]
    return lines + ([f"Architecture: {arch['custom']}"] if arch["custom"] else [])


def apply_settings(rules: list[dict], settings: dict) -> list[dict]:
    """Expand the `source` rows from the resolved profile settings (`quality.resolve_quality`):
    architecture → one line per selected preset; tdd/trophy off → no line; coverage → thresholds."""
    q, out = settings["quality"], []
    for rule in rules:
        base = {k: v for k, v in rule.items() if k not in ("source", "variants")}
        source = rule.get("source")
        if source == "architecture":
            out += [{**base, "text": text} for text in _architecture_lines(settings["architecture"])]
        elif source == "quality.tdd" and q["tdd"] != "off":
            out.append({**base, "text": rule.get("variants", {}).get(q["tdd"], rule["text"])})
        elif source == "quality.testing_trophy" and q["testing_trophy"] == "on":
            out.append(base)
        elif source == "quality.coverage" and q["coverage"]["enabled"]:
            out.append({**base, "text": rule["text"].format(**q["coverage"])})
        elif source is None:
            out.append(base)
    return out


def resolve_effective(user: dict | None, project: dict | None, catalog: dict | None = None) -> dict:
    """The rendered selection for raw (validated) user/project profiles: rules, custom, discipline."""
    catalog = catalog or load_catalog()
    resolved = resolve_key_rules(*(profile_layer(d) if d else None for d in (user, project)), catalog)
    resolved["rules"] = apply_settings(resolved["rules"], resolve_quality(user, project))
    resolved["discipline"] = resolve_discipline(user, project)
    return resolved


def _rows(resolved: dict, catalog: dict | None) -> list[tuple[str, str]]:
    """(id, text) per rendered rule line. `discipline: strict` swaps the calm `targeted-verification`
    line for the catalog `strict_lines` (Iron Law essence); `auto` renders calm — the host's main
    model is unknown here."""
    rules = resolved["rules"]
    if resolved.get("discipline") != "strict":
        return [(r["id"], r["text"]) for r in rules]
    rows = [(r["id"], r["text"]) for r in rules if r["id"] != STRICT_REPLACES]
    return rows + [(STRICT_ID, line) for line in (catalog or load_catalog())["strict_lines"]]


def _delta_lines(resolved: dict, base: dict, catalog: dict | None) -> list[str]:
    """Rule lines of `resolved` that differ from `base` (the user-level selection): added or changed
    rows with their text, the project's own custom rules, then the replaced and the dropped ids."""
    def groups(rows: list[tuple[str, str]]) -> dict[str, list[str]]:
        out: dict[str, list[str]] = {}
        for rule_id, text in rows:
            out.setdefault(rule_id, []).append(text)
        return out

    mine, theirs = groups(_rows(resolved, catalog)), groups(_rows(base, catalog))
    lines = [f"- {t}" for i, texts in mine.items() if texts != theirs.get(i) for t in texts]
    lines += [f"- {c} (your rule)" for c in resolved["custom"] if c not in base["custom"]]
    replaced = [f"`{i}`" for i in theirs if i in mine and mine[i] != theirs[i]]
    off = [f"`{i}`" for i in theirs if i not in mine]
    if replaced:
        lines.append(f"- Replaces the global line: {', '.join(replaced)}.")
    if off:
        lines.append(f"- Off in this project: {', '.join(off)}.")
    return lines


def render_block(resolved: dict, pointer: str, catalog: dict | None = None, base: dict | None = None) -> str:
    """The managed Key rules block, then the pointer line.

    Full (base None): one line per rule, custom last. Delta (`base` = the user-level selection,
    AGR-083): only the project's differences — hosts with a global instructions file already load
    the full block there; no differences → one line saying the global Key rules apply.
    """
    if base is None:
        lines = [f"- {text}" for _, text in _rows(resolved, catalog)]
        lines += [f"- {c} (your rule)" for c in resolved["custom"]]
        body = ["## Key rules", "", *lines]
    elif lines := _delta_lines(resolved, base, catalog):
        body = ["## Key rules — project overrides", "", "Global Key rules apply with these differences:", *lines]
    else:
        body = ["## Key rules", "", "Global Key rules apply; this project has no overrides."]
    return "\n".join([BLOCK_START, *body, "", pointer, BLOCK_END]) + "\n"


def _read_layer(path: str | None, catalog: dict) -> tuple[dict | None, list[ValidationError]]:
    """The profile at `path` (None when absent or invalid) and its key_rules/quality errors."""
    if not path or not Path(path).is_file():
        return None, []
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    errors = validate_key_rules(data.get("key_rules", {}), catalog) + validate_settings(data)
    return (None if errors else data), errors


def _cli_main(argv: list[str]) -> int:
    if argv and argv[0] == "block":
        opts = dict(a[2:].split("=", 1) for a in argv[1:] if a.startswith("--") and "=" in a)
        base = json.loads(Path(opts["base"]).read_text(encoding="utf-8")) if "base" in opts else None
        sys.stdout.write(render_block(json.load(sys.stdin), opts.get("pointer", ""), base=base))
        return 0
    if not argv or argv[0] != "resolve":
        print("Usage: key_rules.py resolve [--user=<p>] [--project=<p>] [--catalog=<p>] [--json]", file=sys.stderr)
        return 1
    opts = dict(a[2:].split("=", 1) for a in argv[1:] if a.startswith("--") and "=" in a)
    catalog = load_catalog(opts.get("catalog"))
    user, user_errors = _read_layer(opts.get("user"), catalog)
    project, project_errors = _read_layer(opts.get("project"), catalog)
    errors = [(opts.get("user"), e) for e in user_errors] + [(opts.get("project"), e) for e in project_errors]
    for path, err in errors:
        print(f"ERROR [{err.field}] {path}: {err.message}", file=sys.stderr)
    if errors:
        return 2
    resolved = resolve_effective(user, project, catalog)
    if "--json" in argv:
        print(json.dumps(resolved, indent=2, ensure_ascii=False))
    else:
        print("".join(f"- {line}\n" for line in [r["text"] for r in resolved["rules"]] + resolved["custom"]), end="")
    return 0


if __name__ == "__main__":
    sys.exit(_cli_main(sys.argv[1:]))
