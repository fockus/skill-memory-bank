"""Built-in preset JSON validation + composition snapshot tests (Sprint 3 / Stage 3).

Uses stdlib only (pathlib + json). No external dependencies.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
PRESETS_ROOT = REPO_ROOT / "references" / "rules-presets"

VALID_KINDS = {"role", "stack", "architecture", "delivery"}
VALID_SEVERITIES = {"advisory", "warn", "block"}

# Maximum guidance length per rule (chars, not bytes — spec says ≤200 chars)
MAX_GUIDANCE_CHARS = 200

# Maximum total concatenated guidance for a 4-preset composition (bytes)
MAX_COMPOSITION_BYTES = 4096


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _load_all_presets() -> list[tuple[Path, dict]]:
    """Return (path, parsed_json) for every *.json file under PRESETS_ROOT."""
    result = []
    for path in sorted(PRESETS_ROOT.rglob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        result.append((path, data))
    return result


def _load_preset(kind: str, name: str) -> dict:
    path = PRESETS_ROOT / kind / f"{name}.json"
    assert path.is_file(), f"preset missing: {path}"
    return json.loads(path.read_text(encoding="utf-8"))


def _composition_guidance_bytes(*preset_pairs: tuple[str, str]) -> int:
    """Concatenate guidance text from multiple (kind, name) presets and return byte length."""
    parts: list[str] = []
    for kind, name in preset_pairs:
        data = _load_preset(kind, name)
        for rule in data.get("rules", []):
            parts.append(rule.get("guidance", ""))
    return len("\n".join(parts).encode("utf-8"))


# ---------------------------------------------------------------------------
# 1. Schema validation — every preset validates
# ---------------------------------------------------------------------------


def test_every_preset_json_validates_against_schema() -> None:
    """Every preset must have required top-level fields, valid severities, unique rule_ids,
    and guidance ≤200 chars per rule."""
    presets = _load_all_presets()
    assert presets, "No preset files found under references/rules-presets/"

    seen_rule_ids: dict[str, Path] = {}
    errors: list[str] = []

    for path, data in presets:
        rel = path.relative_to(REPO_ROOT)

        # Required top-level fields
        for field in ("preset_version", "kind", "name", "description", "rules"):
            if field not in data:
                errors.append(f"{rel}: missing required field '{field}'")

        # kind must be valid
        kind = data.get("kind", "")
        if kind not in VALID_KINDS:
            errors.append(f"{rel}: kind='{kind}' not in {VALID_KINDS}")

        # rules must be a list
        rules = data.get("rules", [])
        if not isinstance(rules, list):
            errors.append(f"{rel}: 'rules' must be a list")
            continue

        for i, rule in enumerate(rules):
            rule_id = rule.get("rule_id", "")
            severity = rule.get("severity", "")
            guidance = rule.get("guidance", "")

            # rule_id present and non-empty
            if not rule_id:
                errors.append(f"{rel}: rules[{i}] missing 'rule_id'")

            # rule_id must be globally unique
            if rule_id in seen_rule_ids:
                errors.append(
                    f"{rel}: rule_id '{rule_id}' duplicates one in "
                    f"{seen_rule_ids[rule_id].relative_to(REPO_ROOT)}"
                )
            else:
                seen_rule_ids[rule_id] = path

            # severity must be valid
            if severity not in VALID_SEVERITIES:
                errors.append(
                    f"{rel}: rules[{i}] severity='{severity}' not in {VALID_SEVERITIES}"
                )

            # guidance ≤200 chars
            if len(guidance) > MAX_GUIDANCE_CHARS:
                errors.append(
                    f"{rel}: rules[{i}] guidance is {len(guidance)} chars (max {MAX_GUIDANCE_CHARS}): "
                    f"{rule_id}"
                )

    assert not errors, "Preset schema violations:\n" + "\n".join(errors)


# ---------------------------------------------------------------------------
# 2. Coverage: required files exist
# ---------------------------------------------------------------------------


def test_role_presets_cover_backend_frontend_mobile() -> None:
    for name in ("backend", "frontend", "mobile"):
        path = PRESETS_ROOT / "roles" / f"{name}.json"
        assert path.is_file(), f"role preset missing: {path}"


def test_stack_presets_cover_required_languages() -> None:
    for name in ("go", "python", "javascript", "typescript", "java", "generic"):
        path = PRESETS_ROOT / "stacks" / f"{name}.json"
        assert path.is_file(), f"stack preset missing: {path}"


def test_architecture_presets_cover_required_styles() -> None:
    for name in ("clean", "modular-monolith", "microservices", "ddd", "fsd", "mobile-udf"):
        path = PRESETS_ROOT / "architecture" / f"{name}.json"
        assert path.is_file(), f"architecture preset missing: {path}"


def test_delivery_presets_cover_required_modes() -> None:
    for name in ("tdd", "contract-first", "api-first", "sdd", "legacy-safe", "exploratory"):
        path = PRESETS_ROOT / "delivery" / f"{name}.json"
        assert path.is_file(), f"delivery preset missing: {path}"


# ---------------------------------------------------------------------------
# 3. Composition budget: 4 preset files concatenated stay under 4 KB
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "role,stack,architecture,delivery",
    [
        ("backend", "go", "microservices", "contract-first"),
        ("frontend", "typescript", "fsd", "sdd"),
        ("mobile", "generic", "mobile-udf", "api-first"),
        ("backend", "java", "ddd", "api-first"),
        ("backend", "python", "modular-monolith", "tdd"),
    ],
)
def test_composition_under_4kb(role: str, stack: str, architecture: str, delivery: str) -> None:
    """Concatenated guidance for a 4-preset composition must fit in 4 KB."""
    size = _composition_guidance_bytes(
        ("roles", role),
        ("stacks", stack),
        ("architecture", architecture),
        ("delivery", delivery),
    )
    assert size <= MAX_COMPOSITION_BYTES, (
        f"Composition ({role}+{stack}+{architecture}+{delivery}) is {size} bytes, "
        f"exceeds {MAX_COMPOSITION_BYTES} byte limit"
    )


# ---------------------------------------------------------------------------
# 4. Immutable baseline safety: no preset disables baseline rules
# ---------------------------------------------------------------------------


def test_no_preset_disables_immutable_baseline() -> None:
    """No preset rule_id must match forbidden patterns that would indicate
    disabling an immutable baseline rule."""
    forbidden_patterns = ("baseline.",)
    presets = _load_all_presets()
    violations: list[str] = []

    for path, data in presets:
        rel = path.relative_to(REPO_ROOT)
        for rule in data.get("rules", []):
            rule_id = rule.get("rule_id", "")
            for pattern in forbidden_patterns:
                if rule_id.startswith(pattern):
                    violations.append(
                        f"{rel}: rule_id '{rule_id}' matches forbidden pattern '{pattern}*'"
                    )

    assert not violations, (
        "Presets must not reference baseline rule ids (presets are additive only):\n"
        + "\n".join(violations)
    )


def test_legacy_safe_does_not_weaken_no_placeholders() -> None:
    """delivery/legacy-safe.json must not contain any rule_id that references
    'no-placeholders'. Legacy-safe extends flexibility for testing strategy only;
    it cannot weaken the immutable no-placeholders baseline."""
    data = _load_preset("delivery", "legacy-safe")
    for rule in data.get("rules", []):
        rule_id = rule.get("rule_id", "")
        assert "no-placeholders" not in rule_id, (
            f"legacy-safe must not reference no-placeholders in rule_id: '{rule_id}'"
        )
        # Also check guidance text does not contain a disable-equivalent phrase
        guidance = rule.get("guidance", "").lower()
        assert "disable" not in guidance or "no-placeholder" not in guidance, (
            f"legacy-safe rule '{rule_id}' guidance appears to disable no-placeholders baseline"
        )
