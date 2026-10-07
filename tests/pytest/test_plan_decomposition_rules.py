"""AGR-078 — planning rules do not force fine-grained stages.

A stage is a dependency boundary, a layer/owner change, a risky checkpoint or a
parallel chunk with disjoint ``Files:``; it is not a size unit. The planning
texts must not carry size limits or a minimum stage count as a requirement.
"""

from __future__ import annotations

from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]

PLANNING_FILES = (
    "commands/plan.md",
    "references/templates.md",
    "references/planning-and-verification.md",
    "rules/RULES.md",
    "scripts/mb-plan.sh",
    "agents/mb-architect.md",
    "commands/sdd.md",
)

FORCED_DECOMPOSITION = (
    "Stages must be atomic",
    "1-5 files",
    "5-15 tests",
    "5-30 min",
    "3-5 `<!-- mb-stage",
    "3-7 stages total",
    "Atomicity + declared dependencies",
    "explicitly written into each stage",
    "200k tokens per Sprint",
)


def _norm(text: str) -> str:
    # Treat en-dash ranges ("1–5") the same as hyphen ranges ("1-5").
    return text.replace("–", "-")


@pytest.mark.parametrize("rel", PLANNING_FILES)
def test_planning_file_without_forced_decomposition(rel: str) -> None:
    text = _norm((REPO / rel).read_text(encoding="utf-8"))
    found = [phrase for phrase in FORCED_DECOMPOSITION if phrase in text]
    assert not found, f"{rel} still forces fine-grained stages: {found}"


@pytest.mark.parametrize("rel", ("commands/plan.md", "references/templates.md"))
def test_stage_defined_by_boundaries(rel: str) -> None:
    text = _norm((REPO / rel).read_text(encoding="utf-8")).lower()
    for boundary in ("dependency", "layer", "owner", "risk", "parallel", "disjoint", "files:"):
        assert boundary in text, f"{rel}: boundary-based stage definition lacks {boundary!r}"
    assert "single-stage plan" in text, f"{rel}: a single-stage plan must be stated as valid"
