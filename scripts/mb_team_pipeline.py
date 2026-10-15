#!/usr/bin/env python3
"""Layered track pipeline resolver for /mb team (contract C2).

Usage:
  mb_team_pipeline.py resolve [--mb <bank>] [--pipeline <file>] [--size S]
      [--team k=v]... [--attr k=v]... [--prompt k=v]... [--host H] [--role R]
      [--source <plan|spec>] --json
  mb_team_pipeline.py parse-prompt --text "<user phrase>" --json

Layers, later wins (provenance names in brackets): presets[size] [preset:<size>]
-> team.overrides [override] -> init attrs --team [team] -> track attrs --attr
[track] -> explicit prompt --prompt [prompt]; values no layer sets come from the
built-in defaults or the host model profile [default]. `size` itself layers as
team.default_size [default] -> --team -> --attr / --size -> --prompt.

Keys: size mode work tdd verifier review lenses effort models.executor
models.verifier models.reviewer models.lead models.lenses models.lens.<name>.
Shorthand: review=lenses:logic,security. Every track runs through /mb work (REQ-001):
mode=direct and work=light are refused. Model values take a
slot (premium|mid -> model_profiles[host]), an exact id, or inherit.

Exit codes: 0 ok · 2 unknown or retired key/value, bad config
(the message names the field) · parse-prompt: 3 when the phrase needs a question.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import mb_pipeline_validate_team as schema  # noqa: E402
import mb_team_vocab  # noqa: E402
import mb_work_models as models_mod  # noqa: E402
from mb_team_config import ConfigError, load_configs  # noqa: E402

DEFAULTS = {"mode": "work", "work": "orchestrated", "tdd": "required", "verifier": "none", "review": "none",
            "lenses": [], "effort": "medium"}
RANKS = {"tdd": ("optional", "required"),
         "verifier": ("none", "plan-verifier"), "review": ("none", "single", "lenses"),
         "effort": ("low", "medium", "high")}
STEP_ROLE = {"verifier": "verifier", "reviewer": "reviewer", "lead": "reviewer_lead",
             "lenses": "reviewer_logic"}


def flatten(block: dict) -> dict:
    """Preset/override mapping -> flat keys (`models.lens.security`)."""
    flat = {}
    for key, value in (block or {}).items():
        if key == "models":
            for mkey, mval in (value or {}).items():
                if mkey == "lens":
                    for lens, model in (mval or {}).items():
                        flat[f"models.lens.{schema.normalize_lens(lens)}"] = model
                else:
                    flat[f"models.{mkey}"] = mval
        elif key == "lenses":
            flat["lenses"] = [schema.normalize_lens(v) for v in value]
        else:
            flat[key] = value
    return flat


def parse_kv(items: list[str], layer: str, err) -> dict:
    """`key=value` attributes of one layer -> flat dict; errors name the key or value."""
    flat: dict = {}
    for item in items:
        key, sep, value = item.partition("=")
        key, value = key.strip(), value.strip()
        field = f"{key} ({layer})"
        if not sep or not value:
            err(f"{field}: expected key=value, got {item!r}")
        elif key == "size":
            if value not in schema.SIZES:
                err(f"{field}: {value!r} not in {list(schema.SIZES)}")
            flat[key] = value
        elif key == "mode" and value.startswith("work:"):
            flat["mode"], flat["work"] = "work", value[5:]
            schema.check_value(err, f"work ({layer})", "work", flat["work"])
        elif key == "review" and value.startswith("lenses:"):
            flat["review"] = "lenses"
            flat.update(parse_kv([f"lenses={value[7:]}"], layer, err))
        elif key == "lenses":
            names = [v.strip() for v in value.split(",") if v.strip()]
            schema.check_lenses(err, field, names)
            flat[key] = [schema.normalize_lens(n) or n for n in names]
        elif key in schema.ENUMS:
            schema.check_value(err, field, key, value)
            flat[key] = value
        elif key.startswith("models.lens.") and schema.normalize_lens(key[12:]):
            flat[f"models.lens.{schema.normalize_lens(key[12:])}"] = value
        elif key.startswith("models.") and key[7:] in schema.ROLE_MODEL_KEYS:
            flat[key] = value
        else:
            err(f"{field}: unknown key; allowed size, {', '.join(schema.PIPELINE_KEYS[:-1])}, "
                f"models.{{{','.join(schema.ROLE_MODEL_KEYS)}}}, models.lens.<lens>")
    return flat


def _model(value: str, project: dict, bundled: dict, host: str, warnings: list) -> str:
    if value not in models_mod.SLOTS:
        return value
    profile = models_mod.merged(project, bundled, "model_profiles").get(host)
    if isinstance(profile, dict) and profile.get(value):
        return str(profile[value])
    warnings.append(f"model_profiles.{host}.{value} unset: inherit")
    return "inherit"


def resolve(team: dict, project: dict, bundled: dict, layers: dict, *, host: str = "claude-code",
            role: str = "developer", source: str = "") -> dict:
    """`source` is accepted for callers and unused: a track without one runs on its prompt.

    layers: {"team"|"track"|"prompt": flat dict}. Raises ConfigError naming the field."""
    values: dict = {"size": team["default_size"]}
    prov: dict = {"size": "default"}
    for name in ("team", "track", "prompt"):
        if "size" in layers.get(name, {}):
            values["size"], prov["size"] = layers[name]["size"], name
    size = values["size"]
    preset = flatten(team["presets"].get(size, {}))
    ordered = [(f"preset:{size}", preset), ("override", flatten(team["overrides"]))]
    ordered += [(name, {k: v for k, v in layers.get(name, {}).items() if k != "size"})
                for name in ("team", "track", "prompt")]
    for name, flat in ordered:
        for key, value in flat.items():
            values[key], prov[key] = value, name
    for key, value in DEFAULTS.items():
        if key not in values:
            values[key], prov[key] = value, "default"
    warnings: list[str] = []
    if values["review"] != "lenses":
        if values["lenses"] and prov["lenses"] != f"preset:{size}":
            warnings.append(f"lenses ignored: review={values['review']}")
        values["lenses"], prov["lenses"] = [], "default"
    elif not values["lenses"]:
        values["lenses"] = list(team["review"].get("lenses") or schema.LENSES)
        prov["lenses"] = "default"
    for key, ranks in RANKS.items():
        base = preset.get(key)
        if prov.get(key) == "prompt" and base in ranks and ranks.index(values[key]) < ranks.index(base):
            warnings.append(f"{key}={values[key]} from the prompt is below the preset:{size} value {base}")
    needed = ["executor"] + (["verifier"] if values["verifier"] != "none" else [])
    needed += {"single": ["reviewer"], "lenses": ["lead", "lenses"]}.get(values["review"], [])
    cost = models_mod.resolve_cost(project, bundled, host)
    resolved_models: dict = {}
    for key in needed:
        raw = values.get(f"models.{key}")
        if raw is None:
            step_role = role if key == "executor" else STEP_ROLE[key]
            resolved_models[key] = models_mod.resolve_model(step_role, project, bundled, host, cost)[0]
            prov[f"models.{key}"] = "default"
        else:
            resolved_models[key] = _model(str(raw), project, bundled, host, warnings)
    lens_models = {lens: _model(str(values[f"models.lens.{lens}"]), project, bundled, host, warnings)
                   for lens in values["lenses"] if f"models.lens.{lens}" in values}
    if lens_models:
        resolved_models["lens"] = lens_models
    keep = {f"models.{k}" for k in needed} | {f"models.lens.{k}" for k in lens_models}
    prov = {k: v for k, v in prov.items() if not k.startswith("models.") or k in keep}
    pipeline = {k: values[k] for k in ("size", "mode", "work", "tdd", "verifier", "review", "lenses", "effort")}
    pipeline["models"] = resolved_models
    return {"pipeline": pipeline, "provenance": prov, "warnings": warnings}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="mb_team_pipeline.py")
    sub = parser.add_subparsers(dest="command", required=True)
    res = sub.add_parser("resolve")
    res.add_argument("--mb", default="")
    res.add_argument("--pipeline", default="")
    res.add_argument("--size", default="")
    for flag in ("--team", "--attr", "--prompt"):
        res.add_argument(flag, action="append", default=[])
    res.add_argument("--host", default="claude-code")
    res.add_argument("--role", default="developer")
    res.add_argument("--source", default="")
    res.add_argument("--json", action="store_true", help="accepted; output is always JSON")
    pp = sub.add_parser("parse-prompt")
    pp.add_argument("--text", required=True)
    pp.add_argument("--json", action="store_true", help="accepted; output is always JSON")
    args = parser.parse_args(argv)
    if args.command == "parse-prompt":
        out = mb_team_vocab.parse(args.text)
        print(json.dumps(out, ensure_ascii=False))
        return 3 if out["questions"] else 0
    errors: list[str] = []
    track = ([f"size={args.size}"] if args.size else []) + args.attr
    layers = {"team": parse_kv(args.team, "team", errors.append),
              "track": parse_kv(track, "track", errors.append),
              "prompt": parse_kv(args.prompt, "prompt", errors.append)}
    try:
        if errors:
            raise ConfigError(errors)
        project, bundled, team = load_configs(args.pipeline, args.mb)
        out = resolve(team, project, bundled, layers, host=args.host, role=args.role, source=args.source)
    except ConfigError as exc:
        for msg in exc.errors:
            sys.stderr.write(f"[team] {msg}\n")
        return 2
    print(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
