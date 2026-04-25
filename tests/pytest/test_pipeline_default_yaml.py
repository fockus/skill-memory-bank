"""Phase 3 Sprint 1 — `references/pipeline.default.yaml` schema sanity.

The shipped default file must be parseable YAML and contain every section
spec §9 mandates. These tests guard against accidental key drift in the
default the rest of the engine falls back to.
"""

from __future__ import annotations

from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_YAML = REPO_ROOT / "references" / "pipeline.default.yaml"


@pytest.fixture(scope="module")
def cfg() -> dict:
    assert DEFAULT_YAML.is_file(), f"missing {DEFAULT_YAML}"
    text = DEFAULT_YAML.read_text(encoding="utf-8")
    data = yaml.safe_load(text)
    assert isinstance(data, dict), "default must be a mapping"
    return data


REQUIRED_TOP_LEVEL = (
    "version",
    "roles",
    "stage_pipeline",
    "budget",
    "protected_paths",
    "sprint_context_guard",
    "review_rubric",
    "sdd",
)


def test_default_yaml_exists() -> None:
    assert DEFAULT_YAML.is_file()


@pytest.mark.parametrize("key", REQUIRED_TOP_LEVEL)
def test_default_has_required_top_level_key(cfg: dict, key: str) -> None:
    assert key in cfg, f"missing top-level key '{key}'"


def test_version_is_one(cfg: dict) -> None:
    assert cfg["version"] == 1


REQUIRED_ROLES = (
    "developer",
    "backend",
    "frontend",
    "ios",
    "android",
    "architect",
    "devops",
    "qa",
    "analyst",
    "reviewer",
    "verifier",
)


@pytest.mark.parametrize("role", REQUIRED_ROLES)
def test_roles_contain_required_role(cfg: dict, role: str) -> None:
    roles = cfg["roles"]
    assert isinstance(roles, dict)
    assert role in roles, f"missing role '{role}'"
    spec = roles[role]
    assert isinstance(spec, dict)
    assert "agent" in spec, f"role '{role}' missing 'agent'"


def test_stage_pipeline_has_three_steps(cfg: dict) -> None:
    sp = cfg["stage_pipeline"]
    assert isinstance(sp, list)
    assert len(sp) == 3
    steps = [s["step"] for s in sp]
    assert steps == ["implement", "review", "verify"]


def test_review_step_has_severity_gate_and_max_cycles(cfg: dict) -> None:
    review = next(s for s in cfg["stage_pipeline"] if s["step"] == "review")
    gate = review["severity_gate"]
    assert set(gate.keys()) == {"blocker", "major", "minor"}
    for key, val in gate.items():
        assert isinstance(val, int) and val >= 0, f"{key} must be int >= 0"
    assert isinstance(review["max_cycles"], int)
    assert review["max_cycles"] >= 1
    assert review["on_max_cycles"] in ("stop_for_human", "continue_with_warning")


def test_verify_step_has_checks(cfg: dict) -> None:
    verify = next(s for s in cfg["stage_pipeline"] if s["step"] == "verify")
    assert "checks" in verify
    assert isinstance(verify["checks"], list)
    assert len(verify["checks"]) >= 5


def test_sprint_context_guard_thresholds(cfg: dict) -> None:
    guard = cfg["sprint_context_guard"]
    assert guard["soft_warn_tokens"] > 0
    assert guard["hard_stop_tokens"] > guard["soft_warn_tokens"]


def test_protected_paths_is_non_empty_list(cfg: dict) -> None:
    paths = cfg["protected_paths"]
    assert isinstance(paths, list)
    assert len(paths) >= 1
    for p in paths:
        assert isinstance(p, str) and p


REQUIRED_RUBRIC_SECTIONS = ("logic", "code_rules", "security", "scalability", "tests")


@pytest.mark.parametrize("section", REQUIRED_RUBRIC_SECTIONS)
def test_review_rubric_section_non_empty(cfg: dict, section: str) -> None:
    rubric = cfg["review_rubric"]
    assert section in rubric
    assert isinstance(rubric[section], list)
    assert len(rubric[section]) >= 1
    for item in rubric[section]:
        assert isinstance(item, str) and item.strip()


def test_sdd_fields_present(cfg: dict) -> None:
    sdd = cfg["sdd"]
    for key in (
        "require_ears_in_sdd_command",
        "require_ears_in_plan_command",
        "require_ears_in_plan_with_sdd_flag",
        "covers_requirements_policy",
        "full_mode_path",
    ):
        assert key in sdd, f"missing sdd.{key}"
    assert sdd["covers_requirements_policy"] in ("warn", "block", "off")


def test_budget_section_shape(cfg: dict) -> None:
    budget = cfg["budget"]
    assert "warn_at_percent" in budget
    assert "stop_at_percent" in budget
    assert 0 <= budget["warn_at_percent"] <= 100
    assert 0 <= budget["stop_at_percent"] <= 100
