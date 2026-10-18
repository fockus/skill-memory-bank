#!/usr/bin/env python3
"""Strict OpenCode representation of canonical MB role assignments (no alias mapping)."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT), str(ROOT / "scripts")]
import mb_work_models as models  # noqa: E402

from memory_bank_skill.pipeline_yaml import load_text  # noqa: E402


def model_reference(model: str, thinking: str = "") -> str:
    """Map explicit thinking to a native variant; inheritance has no reasoning override."""
    if model in ("", "inherit"):
        if thinking:
            raise ValueError("thinking without a model cannot select a native variant; set provider/model#variant")
        return ""
    if not re.fullmatch(r"[^/#\s]+/[^#\s]+(?:#[^/#\s]+)?", model):
        raise ValueError(f"{model!r} needs provider/model with an optional non-empty #variant (no alias mapping)")
    base, _, variant = model.partition("#")
    if thinking and variant and thinking != variant:
        raise ValueError(f"thinking {thinking!r} conflicts with variant {variant!r} in {model!r}")
    variant = thinking or variant
    if variant and not re.fullmatch(r"[^/#\s]+", variant):
        raise ValueError("invalid native variant")
    return base + (f"#{variant}" if variant else "")


def assignments(pipeline: Path, cost: str = "", overrides: dict | None = None,
                needed: set[str] | None = None) -> dict:
    """Keep raw canonical results, then validate at this host's boundary."""
    cfg = load_text(pipeline.read_text(encoding="utf-8"))
    default = load_text((ROOT / "references/pipeline.default.yaml").read_text(encoding="utf-8"))
    if not isinstance(cfg, dict) or not isinstance(default, dict):
        raise ValueError("pipeline YAML must be a mapping")
    roles = cfg.get("roles") or default["roles"]
    if not isinstance(roles, dict):
        raise ValueError("pipeline roles must be a mapping")
    cost = models.resolve_cost(cfg, default, "opencode", cost)
    result = {}
    if needed is not None:
        roles = {role: roles.get(role, default["roles"].get(role, {})) for role in needed}
    for role, spec in roles.items():
        if not isinstance(spec, dict):
            raise ValueError(f"roles.{role} must be a mapping")
        agent = spec.get("agent") or (default["roles"].get(role) or {}).get("agent")
        if needed is not None and not agent:
            raise ValueError(f"selected role {role!r} needs an explicit native agent; no fallback role is substituted")
        item_role = role != "planner" and models.role_class(role) not in models.STEP_ROLES
        cli = (overrides or {}).get(role, (overrides or {}).get("implementer", "") if item_role else "")
        resolved_role = "reviewer" if role.startswith("reviewer_") and not spec.get("model") else role
        model, source = models.resolve_model(resolved_role, cfg, default, "opencode", cost, cli,
                                              legacy_developer=item_role)
        fallback = (cfg.get("roles") or {}).get("developer" if item_role else resolved_role) or {}
        thinking = str(spec.get("thinking") or
                       (fallback.get("thinking") if isinstance(fallback, dict) else "") or "")
        # A run-only model selector is complete, including its variant, not a persisted effort pin.
        native = model_reference(model, "" if cli else thinking)
        result[role] = {"agent": agent or f"mb-{role}", "model": model,
                        "native": native, "source": source, "thinking": thinking}
    return result


if __name__ == "__main__":
    try:
        print(json.dumps(assignments(Path(sys.argv[1]))))
    except (OSError, ValueError) as exc:
        print(f"opencode-models: {exc}", file=sys.stderr)
        raise SystemExit(1) from None
