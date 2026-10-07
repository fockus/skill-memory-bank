"""Contract for references/effort-tiers.md — the single source of task tiers (AGR-067)."""

from __future__ import annotations

import re
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
REFERENCE = REPO_ROOT / "references" / "effort-tiers.md"
PIPELINE = REPO_ROOT / "references" / "pipeline.default.yaml"

TIERS = ["trivial", "small", "standard", "large", "extra"]
PRESETS = {"small": "simple", "standard": "medium", "large": "complex", "extra": "governed"}


def _sections() -> dict[str, str]:
    text = REFERENCE.read_text(encoding="utf-8")
    parts = re.split(r"^### (\w+)\s*$", text, flags=re.MULTILINE)
    return dict(zip(parts[1::2], parts[2::2], strict=True))


def test_effort_tiers_reference_lists_five_tiers_in_order() -> None:
    assert list(_sections()) == TIERS


def test_effort_tiers_each_tier_names_its_preset() -> None:
    sections = _sections()
    missing = [t for t, preset in PRESETS.items() if f"`{preset}`" not in sections[t]]
    assert missing == []


def test_effort_tiers_reference_carries_override_and_parallel_rules() -> None:
    text = REFERENCE.read_text(encoding="utf-8").lower()
    assert "explicit" in text and "beats the tier" in text
    assert "pick the lower" in text
    assert "parallel" in text and "one owner" in text


def test_effort_tiers_presets_exist_in_default_pipeline() -> None:
    pipeline = yaml.safe_load(PIPELINE.read_text(encoding="utf-8"))
    workflows = pipeline.get("workflows", {})
    if not set(PRESETS.values()) <= set(workflows):
        pytest.xfail("pipeline-presets Stage 2 in progress")
    assert pipeline.get("effort_tiers") == PRESETS
