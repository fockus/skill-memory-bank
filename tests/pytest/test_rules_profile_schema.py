"""Rules profile schema + resolver contract tests (Sprint 3 / Stage 1).

These tests exercise the profile parser, validator, and resolver. They are
deliberately RED at Stage 1 because `memory_bank_skill.rules_profile`
does not yet exist — Stage 2 (`mb-profile.sh`) and Stage 3 (preset JSONs)
provide the implementation; Stage 4 wires it into `mb-rules-check.sh`.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "tests" / "fixtures" / "rules-profiles"
SCHEMA_DOC = REPO_ROOT / "references" / "rules-profile.schema.md"


# ---------------------------------------------------------------------------
# Schema doc presence (Stage 1 deliverable)
# ---------------------------------------------------------------------------


def test_schema_doc_exists_and_lists_dimensions() -> None:
    text = SCHEMA_DOC.read_text(encoding="utf-8")
    # Roles
    for role in ("backend", "frontend", "mobile"):
        assert role in text
    # Stacks
    for stack in ("go", "python", "javascript", "typescript", "java", "generic"):
        assert stack in text
    # Architectures (MVP subset)
    for arch in ("clean", "modular-monolith", "microservices", "ddd", "fsd", "mobile-udf"):
        assert arch in text
    # Delivery
    for delivery in ("tdd", "contract-first", "api-first", "sdd", "legacy-safe", "exploratory"):
        assert delivery in text
    # Strictness
    for s in ("advisory", "warn", "block"):
        assert s in text
    # Immutable baseline mention
    assert "immutable" in text.lower()
    # Canonical JSON statement (YAML docs-only)
    assert "JSON" in text
    assert "YAML" in text


# ---------------------------------------------------------------------------
# Fixtures present (Stage 1 deliverable)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "name",
    [
        "backend-go.json",
        "frontend-typescript.json",
        "frontend-javascript.json",
        "mobile-generic.json",
        "python-modular.json",
        "java-ddd.json",
        "rules-only-global.json",
    ],
)
def test_fixture_profile_exists_and_is_valid_json(name: str) -> None:
    path = FIXTURES / name
    assert path.is_file(), f"fixture missing: {path}"
    data = json.loads(path.read_text(encoding="utf-8"))
    assert data.get("schema_version") == 1
    assert "role" in data
    assert "stack" in data


# ---------------------------------------------------------------------------
# Parser + validator API (Stage 2 implementation)
# ---------------------------------------------------------------------------


def _import_module():
    from memory_bank_skill import rules_profile  # noqa: PLC0415

    return rules_profile


def test_parse_valid_backend_go_profile() -> None:
    mod = _import_module()
    profile = mod.parse_profile(FIXTURES / "backend-go.json")
    assert profile.role == "backend"
    assert profile.stack == "go"
    assert profile.architecture == "microservices"
    assert profile.delivery == "contract-first"
    assert profile.strictness == "warn"


def test_validate_rejects_unknown_role() -> None:
    mod = _import_module()
    errors = mod.validate_profile(
        {
            "schema_version": 1,
            "scope": "user",
            "role": "devops",  # not in MVP
            "stack": "go",
            "architecture": "clean",
            "delivery": "tdd",
        }
    )
    assert any(err.field == "role" for err in errors)


def test_validate_rejects_unknown_stack() -> None:
    mod = _import_module()
    errors = mod.validate_profile(
        {
            "schema_version": 1,
            "scope": "user",
            "role": "backend",
            "stack": "cobol",
            "architecture": "clean",
            "delivery": "tdd",
        }
    )
    assert any(err.field == "stack" for err in errors)


def test_validate_rejects_unknown_architecture() -> None:
    mod = _import_module()
    errors = mod.validate_profile(
        {
            "schema_version": 1,
            "scope": "user",
            "role": "backend",
            "stack": "go",
            "architecture": "soa-2003",
            "delivery": "tdd",
        }
    )
    assert any(err.field == "architecture" for err in errors)


def test_validate_rejects_unknown_top_level_key() -> None:
    mod = _import_module()
    errors = mod.validate_profile(
        {
            "schema_version": 1,
            "scope": "user",
            "role": "backend",
            "stack": "go",
            "architecture": "clean",
            "delivery": "tdd",
            "nonsense_field": True,
        }
    )
    assert any("nonsense_field" in err.message for err in errors)


def test_validate_rejects_disabling_immutable_baseline() -> None:
    """A profile that tries to disable `no-placeholders` or `protected-files`
    must be rejected: the immutable baseline cannot be disabled."""
    mod = _import_module()
    errors = mod.validate_profile(
        {
            "schema_version": 1,
            "scope": "user",
            "role": "backend",
            "stack": "go",
            "architecture": "clean",
            "delivery": "tdd",
            "baseline": {"no-placeholders": False, "protected-files": False},
        }
    )
    assert errors, "expected validation errors for disabling immutable baseline"


def test_validate_rejects_unsupported_schema_version() -> None:
    mod = _import_module()
    errors = mod.validate_profile(
        {
            "schema_version": 99,
            "scope": "user",
            "role": "backend",
            "stack": "go",
            "architecture": "clean",
            "delivery": "tdd",
        }
    )
    assert any(err.field == "schema_version" for err in errors)


# ---------------------------------------------------------------------------
# Resolver precedence (Stage 2 implementation)
# ---------------------------------------------------------------------------


def test_resolve_returns_baseline_when_no_profiles() -> None:
    mod = _import_module()
    resolved = mod.resolve_profile(user_profile=None, project_profile=None)
    # All fields fall back to built-in defaults; immutable rules always present.
    assert resolved.immutable_rules
    assert "no-placeholders" in resolved.immutable_rules
    assert "protected-files" in resolved.immutable_rules


def test_resolve_project_overrides_user_for_architecture() -> None:
    mod = _import_module()
    user = mod.parse_profile(FIXTURES / "rules-only-global.json")  # arch=clean
    project = mod.parse_profile(FIXTURES / "backend-go.json")  # arch=microservices
    resolved = mod.resolve_profile(user_profile=user, project_profile=project)
    assert resolved.architecture == "microservices"
    assert resolved.sources["architecture"] == "project"


def test_resolve_no_mb_uses_user_global_profile() -> None:
    """In rules-only mode (no Memory Bank), only the user-global profile sets
    configurable dimensions on top of the baseline."""
    mod = _import_module()
    user = mod.parse_profile(FIXTURES / "rules-only-global.json")
    resolved = mod.resolve_profile(user_profile=user, project_profile=None)
    assert resolved.role == "backend"
    assert resolved.stack == "go"
    assert resolved.sources["role"] == "user"


def test_resolve_task_override_cannot_weaken_baseline() -> None:
    """A task instruction trying to disable an immutable rule is ignored."""
    mod = _import_module()
    resolved = mod.resolve_profile(
        user_profile=None,
        project_profile=None,
        task_override={"baseline": {"no-placeholders": False}},
    )
    assert "no-placeholders" in resolved.immutable_rules


def test_resolve_task_override_can_tighten_strictness() -> None:
    mod = _import_module()
    resolved = mod.resolve_profile(
        user_profile=None,
        project_profile=None,
        task_override={"strictness": "block"},
    )
    assert resolved.strictness == "block"
    assert resolved.sources["strictness"] == "task"


def test_resolve_invalid_json_falls_back_to_baseline(tmp_path: Path) -> None:
    """A profile file with malformed JSON must not crash the resolver; it
    falls back to the immutable baseline plus a warning."""
    mod = _import_module()
    bad = tmp_path / "rules-profile.json"
    bad.write_text("{not valid json")
    with pytest.warns(UserWarning):
        profile = mod.parse_profile_safe(bad)
    assert profile is None  # safe-mode returns None for malformed input


# ---------------------------------------------------------------------------
# Prompt summary budget (4 KB cap is enforced by Stage 3 presets)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "fixture",
    [
        "backend-go.json",
        "frontend-typescript.json",
        "mobile-generic.json",
        "python-modular.json",
        "java-ddd.json",
    ],
)
def test_resolved_prompt_summary_under_4kb(fixture: str) -> None:
    mod = _import_module()
    project = mod.parse_profile(FIXTURES / fixture)
    resolved = mod.resolve_profile(user_profile=None, project_profile=project)
    assert resolved.prompt_summary
    assert len(resolved.prompt_summary.encode("utf-8")) <= 4096
