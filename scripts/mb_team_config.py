#!/usr/bin/env python3
"""Effective `team:` config of a bank and resource JSON (contract C3).

Usage:
  mb_team_config.py show [--mb <bank>] [--pipeline <file>] [--json]
  mb_team_config.py resource <name> [--mb <bank>] [--pipeline <file>] [--json]

`show` prints the effective team block: the project block over the bundled one
(presets size by size and key by key, review/checkpoint key by key, resources and
rules from the project). Output is always JSON.

Exit codes: 0 ok · 2 invalid config or usage (each error names the field) ·
3 unknown resource.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import mb_pipeline_validate_team as schema  # noqa: E402
from mb_pipeline_minimal_yaml import minimal_pipeline_load  # noqa: E402

DEFAULT_PIPELINE = HERE.parent / "references" / "pipeline.default.yaml"
RESOURCE_DEFAULTS = {"kind": "mutex", "scope": "host", "maintenance": None,
                     "watch_interval_s": 30, "poll_s": 5}


class ConfigError(Exception):
    """Invalid pipeline/team config; `errors` name the fields."""

    def __init__(self, errors: list[str]):
        super().__init__("; ".join(errors))
        self.errors = errors


def load(path: Path) -> tuple[dict, str]:
    """(config, text) with PyYAML when importable, else the stdlib fallback parser."""
    text = path.read_text(encoding="utf-8")
    try:
        import yaml  # type: ignore
    except ImportError:
        return minimal_pipeline_load(text), text
    try:
        data = yaml.safe_load(text) or {}
    except yaml.YAMLError as exc:
        raise ConfigError([f"{path}: YAML parse error: {exc}"]) from exc
    if not isinstance(data, dict):
        raise ConfigError([f"{path}: top-level must be a mapping"])
    return data, text


def pipeline_path(bank: str) -> Path:
    """The pipeline the bank resolves to (`mb-pipeline.sh path`)."""
    out = subprocess.run(["bash", str(HERE / "mb-pipeline.sh"), "path", bank],
                         capture_output=True, text=True, check=False)
    if out.returncode != 0 or not out.stdout.strip():
        raise ConfigError([f"mb-pipeline.sh path failed: {out.stderr.strip()}"])
    return Path(out.stdout.strip())


def _block(cfg: dict, key: str) -> dict:
    value = cfg.get(key)
    return value if isinstance(value, dict) else {}


def _merge_fields(base: dict, top: dict) -> dict:
    merged = {**base, **top}
    if "models" in base or "models" in top:
        models = {**_block(base, "models"), **_block(top, "models")}
        lens = {**_block(_block(base, "models"), "lens"), **_block(_block(top, "models"), "lens")}
        if lens:
            models["lens"] = lens
        merged["models"] = models
    return merged


def effective_team(project: dict, bundled: dict) -> dict:
    p, b = _block(project, "team"), _block(bundled, "team")
    presets = {size: _merge_fields(_block(_block(b, "presets"), size), _block(_block(p, "presets"), size))
               for size in schema.SIZES}
    review = _merge_fields(_block(b, "review"), _block(p, "review"))
    return {
        "default_size": p.get("default_size", b.get("default_size", "standard")),
        "max_parallel": p.get("max_parallel", b.get("max_parallel", 6)),
        "presets": presets,
        "overrides": {**_block(b, "overrides"), **_block(p, "overrides")},
        "rules": list(p.get("rules") or b.get("rules") or []),
        "review": review,
        "resources": {**_block(b, "resources"), **_block(p, "resources")},
        "checkpoint": {**_block(b, "checkpoint"), **_block(p, "checkpoint")},
    }


def load_configs(pipeline: str = "", bank: str = "") -> tuple[dict, dict, dict]:
    """(project cfg, bundled cfg, effective team); raises ConfigError on a bad team block."""
    bundled, _ = load(DEFAULT_PIPELINE)
    schema.normalize(bundled.get("team"))
    path = Path(pipeline) if pipeline else pipeline_path(bank) if bank else DEFAULT_PIPELINE
    project, text = load(path)
    errors: list[str] = []
    schema.validate(project.get("team"), errors.append, text)  # normalizes in place
    if errors:
        raise ConfigError(errors)
    return project, bundled, effective_team(project, bundled)


def resource_json(team: dict, name: str, bank: str) -> dict:
    """C3 JSON of one resource; KeyError when it is not declared."""
    spec = {**RESOURCE_DEFAULTS, **team["resources"][name]}
    pre = _block(spec, "preconditions")
    stop = _block(spec, "stop_threshold")
    if spec["scope"] == "bank":
        if not bank:
            raise ConfigError([f"team.resources.{name}.scope: bank scope needs --mb <bank>"])
        path = os.path.join(os.path.abspath(bank), ".locks", "res", name)
    else:
        base = os.environ.get("MB_LOCK_DIR") or os.path.join(os.environ.get("TMPDIR") or "/tmp", "mb-locks")
        path = os.path.join(base, name)
    return {
        "name": name, "kind": spec["kind"], "scope": spec["scope"], "path": path,
        "preconditions": {k: pre.get(k) for k in ("free_disk_gb", "disk_path", "check")},
        "stop_threshold": {k: stop.get(k) for k in ("free_disk_gb", "check")},
        "maintenance": spec["maintenance"],
        "watch_interval_s": spec["watch_interval_s"], "poll_s": spec["poll_s"],
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="mb_team_config.py")
    parser.add_argument("command", choices=("show", "resource"))
    parser.add_argument("name", nargs="?")
    parser.add_argument("--mb", default="")
    parser.add_argument("--pipeline", default="")
    parser.add_argument("--json", action="store_true", help="accepted; output is always JSON")
    args = parser.parse_args(argv)
    try:
        _project, _bundled, team = load_configs(args.pipeline, args.mb)
        if args.command == "show":
            result = team
        elif not args.name:
            raise ConfigError(["resource: name required"])
        elif args.name not in team["resources"]:
            sys.stderr.write(f"[team] unknown resource '{args.name}'; declared {sorted(team['resources'])}\n")
            return 3
        else:
            result = resource_json(team, args.name, args.mb)
    except ConfigError as exc:
        for msg in exc.errors:
            sys.stderr.write(f"[team] {msg}\n")
        return 2
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
