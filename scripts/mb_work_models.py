"""Per-role model resolution for /mb work: cost tiers × host profiles (AGR-074).

Used by mb-work-plan.sh (resolution, discipline) and mb_pipeline_validate_core.py
(schema). Per role, first match wins:

    cli (`--model`, item role only) ▸ roles.<role>.model ▸
    model_profiles[host][cost_tiers[cost][class]] ▸ "inherit"

Cost: `--cost` ▸ hosts.<host>.cost ▸ `cost` ▸ "optimal". For cost_tiers,
model_profiles and hosts a project block replaces the default key by key.
"""

from __future__ import annotations

import fnmatch
import os
import sys

TIERS = ("premium", "optimal", "economy")
SLOTS = ("premium", "mid")
HOST_KEYS = ("cost", "preset", "verify")
CADENCES = ("stage", "plan", "run", "off")
CLASSES = ("implementer", "planner", "researcher", "verifier", "reviewer", "judge")
_ROLE_CLASS = {
    **dict.fromkeys(
        ("developer", "backend", "frontend", "ios", "android", "devops", "qa", "debugger", "analyst"),
        "implementer"),
    "architect": "planner",
    "planner": "planner",
    "researcher": "researcher",
    "verifier": "verifier",
    "reviewer": "reviewer",
    "judge": "judge",
}
STEP_ROLES = ("verifier", "reviewer", "judge")


def role_class(role: str):  # -> str | None (python3.9 hosts: no PEP 604)
    if role.startswith("reviewer_"):
        return "reviewer"
    return _ROLE_CLASS.get(role)


def _mapping(value) -> dict:
    return value if isinstance(value, dict) else {}


def merged(cfg: dict, default_cfg: dict, key: str) -> dict:
    return {**_mapping(default_cfg.get(key)), **_mapping(cfg.get(key))}


def resolve_cost(cfg: dict, default_cfg: dict, host: str, cli_cost: str = "") -> str:
    host_cost = _mapping(merged(cfg, default_cfg, "hosts").get(host)).get("cost")
    return str(cli_cost or host_cost or cfg.get("cost") or default_cfg.get("cost") or "optimal")


def _role_model(roles: dict, role: str) -> str:
    return str(_mapping(roles.get(role)).get("model") or "")


def resolve_model(role, cfg, default_cfg, host, cost, cli_model="", legacy_developer=False):
    """Return (model, source) with source in cli | role | profile | inherit.

    `legacy_developer`: an item role without its own model takes
    roles.developer.model (pre-AGR-074 behaviour, still source `role`).
    """
    if cli_model:
        return cli_model, "cli"
    roles = _mapping(cfg.get("roles"))
    model = _role_model(roles, role) or (_role_model(roles, "developer") if legacy_developer else "")
    if model:
        return model, "role"
    profile = merged(cfg, default_cfg, "model_profiles").get(host)
    slot = _mapping(merged(cfg, default_cfg, "cost_tiers").get(cost)).get(role_class(role) or "")
    if isinstance(profile, dict) and slot:
        if profile.get(slot):
            return str(profile[slot]), "profile"
        sys.stderr.write(f"[work-plan] model_profiles.{host}.{slot} unset: {role} inherits\n")
    return "inherit", "inherit"


def strict_models(cfg: dict, default_cfg: dict) -> list:
    for source in (cfg, default_cfg):
        block = _mapping(source.get("discipline"))
        if isinstance(block.get("strict_models"), list):
            return [str(p).lower() for p in block["strict_models"]]
    return []


def discipline_for(model: str, patterns: list) -> str:
    name = model.strip().lower()
    if not name or name == "inherit":
        return "calm"
    candidates = {name, name.rsplit("/", 1)[-1]}
    hit = any(fnmatch.fnmatchcase(c, pat) for c in candidates for pat in patterns)
    return "strict" if hit else "calm"


def load_default() -> dict:
    """The shipped pipeline.default.yaml, or {} without PyYAML (fail-open)."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "references",
                        "pipeline.default.yaml")
    try:
        import yaml  # type: ignore

        with open(path, encoding="utf-8") as fh:
            return yaml.safe_load(fh) or {}
    except Exception:
        return {}


def validate(cfg: dict, err, workflow_names=None, default_cfg=None) -> None:
    """Schema for cost / cost_tiers / model_profiles / hosts; reports through err()."""
    cost = cfg.get("cost")
    if cost is not None and cost not in TIERS:
        err(f"cost: '{cost}' not in {list(TIERS)}")
    tiers = cfg.get("cost_tiers")
    if tiers is not None and not isinstance(tiers, dict):
        err("cost_tiers: must be a mapping")
    for tier, classes in _mapping(tiers).items():
        if tier not in TIERS:
            err(f"cost_tiers.{tier}: unknown tier; allowed {list(TIERS)}")
            continue
        if not isinstance(classes, dict):
            err(f"cost_tiers.{tier}: must be a mapping of role class → premium|mid")
            continue
        for cls, slot in classes.items():
            if cls not in CLASSES:
                err(f"cost_tiers.{tier}.{cls}: unknown role class; allowed {list(CLASSES)}")
            elif slot not in SLOTS:
                err(f"cost_tiers.{tier}.{cls}: '{slot}' not in {list(SLOTS)}")
        missing = [c for c in CLASSES if c not in classes]
        if missing:
            err(f"cost_tiers.{tier}: missing role class(es) {missing}")
    profiles = cfg.get("model_profiles")
    if profiles is not None and not isinstance(profiles, dict):
        err("model_profiles: must be a mapping")
    strict = strict_models(cfg, default_cfg or {})
    for host, profile in _mapping(profiles).items():
        if not isinstance(profile, dict) or set(profile) != set(SLOTS):
            err(f"model_profiles.{host}: needs exactly {list(SLOTS)} (got {profile!r})")
            continue
        for slot, model in profile.items():
            if not isinstance(model, str) or not model:
                err(f"model_profiles.{host}.{slot}: must be a non-empty model id")
            elif host == "pi" and "/" not in model:
                err(f"model_profiles.pi.{slot}: '{model}' needs provider/id (Pi maps aliases to the parent model, AGR-056)")
            elif slot == "mid" and discipline_for(model, strict) == "strict":
                err(f"model_profiles.{host}.mid: '{model}' matches discipline.strict_models (no cheapest model, AGR-074)")
    hosts = cfg.get("hosts")
    if hosts is not None and not isinstance(hosts, dict):
        err("hosts: must be a mapping")
    for host, spec in _mapping(hosts).items():
        unknown = sorted(set(_mapping(spec)) - set(HOST_KEYS))
        if not isinstance(spec, dict) or unknown:
            err(f"hosts.{host}: must be a mapping with keys {list(HOST_KEYS)} (unknown: {unknown})")
            continue
        if "cost" in spec and spec["cost"] not in TIERS:
            err(f"hosts.{host}.cost: '{spec['cost']}' not in {list(TIERS)}")
        if "verify" in spec and spec["verify"] not in CADENCES:
            err(f"hosts.{host}.verify: '{spec['verify']}' not in {list(CADENCES)}")
        if "preset" in spec and workflow_names is not None and spec["preset"] not in workflow_names:
            err(f"hosts.{host}.preset: workflow '{spec['preset']}' is not declared")
