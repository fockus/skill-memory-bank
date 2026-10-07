"""Edit the key-rules selection of one rules-profile scope (`/mb rules`, install onboarding).

Only the `key_rules` field of the scope's profile changes; a missing profile is created
with the same defaults `mb-profile.sh init` writes, so `mb-profile.sh validate` passes.

CLI (invoked by scripts/mb-rules.sh):
    python3 -m memory_bank_skill.key_rules_edit <op> --scope=user|project --user=<path>
        [--project=<path>] [args]
    ops: list | enable <id> | disable <id> | add <text> | remove <n> | prompt
         | init [--enable=a,b] [--disable=a,b] [--custom=<text>]...
         | set <key> <value...> | discipline <value>   (alias of `set discipline`)
    set keys: architecture <name[,name…][,custom:<text>]> | tdd on|off|small+ | trophy on|off
              | coverage off|<overall>/<core>/<infra> | principle <solid|dry|kiss|yagni> on|off
              | discipline auto|strict|calm
Exit: 0 ok · 2 invalid selection or setting (unknown or locked id, bad custom rule, bad value).

Profile-backed rows have one switch each (AGR-076/077): enable/disable of solid/dry/kiss/yagni,
tdd, testing-trophy and coverage edit the `quality` field instead of key_rules.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from memory_bank_skill._io import atomic_write
from memory_bank_skill.key_rules import (
    SelectionError,
    load_catalog,
    resolve_effective,
    validate_key_rules,
)
from memory_bank_skill.quality import DEFAULT_ARCHITECTURE, PRINCIPLE_IDS, validate_settings
from memory_bank_skill.rules_profile import _DEFAULTS, SCHEMA_VERSION


def _read(path: str | None) -> dict:
    if not path or not Path(path).is_file():
        return {}
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _layer(data: dict) -> dict:
    kr = data.get("key_rules") or {}
    return {k: list(kr.get(k, [])) for k in ("enabled", "disabled", "custom")}


# Rows switched through `quality`: rule id → (path in quality, on value, off value).
SWITCHES = {
    **{p: (("principles", p), "on", "off") for p in PRINCIPLE_IDS},
    "tdd": (("tdd",), "small+", "off"),
    "testing-trophy": (("testing_trophy",), "on", "off"),
    "coverage": (("coverage", "enabled"), True, False),
}
_SET_KEYS = {"tdd": ("tdd",), "trophy": ("testing_trophy",)}


def _get(tree: dict, path: tuple[str, ...]) -> object:
    for key in path:
        tree = tree.get(key) if isinstance(tree, dict) else None
    return tree


def _put(tree: dict, path: tuple[str, ...], value: object) -> None:
    for key in path[:-1]:
        tree = tree.setdefault(key, {})
    tree[path[-1]] = value


def _drop(tree: dict, path: tuple[str, ...]) -> None:
    node = _get(tree, path[:-1]) if len(path) > 1 else tree
    if isinstance(node, dict):
        node.pop(path[-1], None)
    if len(path) > 1 and _get(tree, path[:-1]) == {}:
        _drop(tree, path[:-1])


def _architecture(value: str) -> str | list:
    """`a,b,custom:<text>` → profile `architecture` (a string when it is one name)."""
    names, _, custom = value.partition("custom:")
    items: list = [n.strip() for n in names.split(",") if n.strip()]
    if custom.strip():
        items.append({"custom": custom.strip()})
    return items[0] if len(items) == 1 and isinstance(items[0], str) else items


class Selection:
    """The editable `key_rules` layer (+ `quality`, `architecture`, `discipline`) of one scope;
    `base` is the user profile under a project."""

    def __init__(self, catalog: dict, data: dict, base: dict | None) -> None:
        self.catalog, self.base = catalog, base
        self.layer = _layer(data)
        self.quality = json.loads(json.dumps(data.get("quality") or {}))
        self.discipline: str | None = data.get("discipline")
        self.architecture: str | list | None = data.get("architecture")
        self.rules = {r["id"]: r for r in catalog["rules"]}
        self.numbers = {i: r["id"] for i, r in enumerate(catalog["rules"], 1)}

    def _own(self) -> dict:
        own = {"key_rules": self.layer, "quality": self.quality}
        if self.architecture is not None:
            own["architecture"] = self.architecture
        return own

    def resolved(self) -> dict:
        user, project = (self.base, self._own()) if self.base is not None else (self._own(), None)
        return resolve_effective(user, project, self.catalog)

    def active(self) -> set[str]:
        return {r["id"] for r in self.resolved()["rules"]}

    def _rule(self, rule_id: str) -> dict:
        if rule_id not in self.rules:
            errors = validate_key_rules({"enabled": [rule_id]}, self.catalog)
            raise SelectionError(errors[0].message)
        rule = self.rules[rule_id]
        if "source" in rule and rule_id not in SWITCHES:
            raise SelectionError(validate_key_rules({"enabled": [rule_id]}, self.catalog)[0].message)
        return rule

    def _switch(self, rule_id: str, on: bool) -> None:
        path, on_value, off_value = SWITCHES[rule_id]
        _drop(self.quality, path)
        if (rule_id in self.active()) != on:
            _put(self.quality, path, on_value if on else off_value)

    def enable(self, rule_id: str) -> None:
        self._rule(rule_id)
        if rule_id in SWITCHES:
            return self._switch(rule_id, True)
        self.layer["disabled"] = [i for i in self.layer["disabled"] if i != rule_id]
        if rule_id not in self.active():
            self.layer["enabled"].append(rule_id)

    def disable(self, rule_id: str) -> None:
        if self._rule(rule_id)["locked"]:
            raise SelectionError(f"locked rule {rule_id!r} cannot be disabled")
        if rule_id in SWITCHES:
            return self._switch(rule_id, False)
        self.layer["enabled"] = [i for i in self.layer["enabled"] if i != rule_id]
        if rule_id in self.active():
            self.layer["disabled"].append(rule_id)

    def set(self, key: str, values: list[str]) -> None:
        """`mb-rules.sh set <key> <value>`; values are checked by `validate_settings` on save."""
        value = " ".join(values)
        if key == "architecture" and value:
            self.architecture = _architecture(value)
        elif key in _SET_KEYS and len(values) == 1:
            _put(self.quality, _SET_KEYS[key], value)
        elif key == "coverage" and value == "off":
            _put(self.quality, ("coverage", "enabled"), False)
        elif key == "coverage" and len(values) == 1:
            parts = value.split("/")
            if len(parts) != 3 or not all(p.isdigit() for p in parts):
                raise SelectionError(f"coverage must be off or <overall>/<core>/<infra>, got {value!r}")
            self.quality["coverage"] = {**(self.quality.get("coverage") or {}), "enabled": True,
                                        **dict(zip(("overall", "core", "infra"), map(int, parts), strict=True))}
        elif key == "principle" and len(values) == 2 and values[0] in PRINCIPLE_IDS and values[1] in ("on", "off"):
            self._switch(values[0], values[1] == "on")
        elif key == "discipline" and len(values) == 1:
            self.discipline = value
        else:
            raise SelectionError(f"bad setting: set {key} {value}".rstrip()
                                 + " (keys: architecture, tdd, trophy, coverage, principle, discipline)")

    def toggle(self, rule_id: str) -> None:
        (self.disable if rule_id in self.active() else self.enable)(rule_id)

    def add(self, text: str) -> None:
        text = text.strip()
        errors = validate_key_rules({"custom": [text]}, self.catalog)
        if errors:
            raise SelectionError(errors[0].message)
        if text not in self.layer["custom"]:
            self.layer["custom"].append(text)

    def remove(self, number: str) -> None:
        if not number.isdigit() or not 1 <= int(number) <= len(self.layer["custom"]):
            raise SelectionError(f"no own rule number {number!r} (have {len(self.layer['custom'])})")
        del self.layer["custom"][int(number) - 1]


def save(path: str, scope: str, sel: Selection) -> None:
    data = _read(path)
    if (not data and not any(sel.layer.values()) and not sel.quality and not sel.discipline
            and sel.architecture is None):
        return  # nothing selected and no profile yet — the defaults need no file
    if not data:
        data = {"schema_version": SCHEMA_VERSION, "scope": scope, **_DEFAULTS,
                "architecture": list(DEFAULT_ARCHITECTURE)}
    data["key_rules"] = sel.layer
    data.pop("quality", None)
    if sel.quality:
        data["quality"] = sel.quality
    if sel.discipline:
        data["discipline"] = sel.discipline
    if sel.architecture is not None:
        data["architecture"] = sel.architecture
    errors = validate_key_rules(sel.layer, sel.catalog) + validate_settings(data)
    if errors:
        raise SelectionError(errors[0].message)
    atomic_write(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def _split(value: str) -> list[str]:
    return [i for i in value.split(",") if i]


def _cli_main(argv: list[str]) -> int:
    from memory_bank_skill.key_rules_prompt import (  # noqa: PLC0415 — it imports this module
        checklist,
        prompt,
    )
    op = argv[0] if argv else ""
    opts: dict[str, str] = {}
    customs: list[str] = []
    args: list[str] = []
    for a in argv[1:]:
        if a.startswith("--custom="):
            customs.append(a.split("=", 1)[1])
        elif a.startswith("--") and "=" in a:
            key, value = a[2:].split("=", 1)
            opts[key] = value
        else:
            args.append(a)
    scope = opts.get("scope", "user")
    path = opts["project"] if scope == "project" else opts["user"]
    catalog = load_catalog()
    base = _read(opts["user"]) if scope == "project" else None
    sel = Selection(catalog, _read(path), base)
    try:
        if op == "list":
            sys.stdout.write(checklist(sel, scope))
            return 0
        if op == "prompt":
            prompt(sel, scope, sys.stdin, sys.stdout)
        elif op == "init":
            sel.layer = {"enabled": [], "disabled": [], "custom": []}
            for switch_path, _, _ in SWITCHES.values():
                _drop(sel.quality, switch_path)
            for rule_id in _split(opts.get("enable", "")):
                sel.enable(rule_id)
            for rule_id in _split(opts.get("disable", "")):
                sel.disable(rule_id)
            for text in customs:
                sel.add(text)
        elif op in ("enable", "disable", "add", "remove") and len(args) == 1:
            getattr(sel, op)(args[0])
        elif op == "set" and args:
            sel.set(args[0], args[1:])
        elif op == "discipline":
            sel.set("discipline", args)
        else:
            print(f"usage: key_rules_edit {op or '<op>'}: see module docstring", file=sys.stderr)
            return 1
        save(path, scope, sel)
    except SelectionError as exc:
        print(f"mb-rules: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(_cli_main(sys.argv[1:]))
