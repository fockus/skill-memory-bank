"""AGR-080 — ADaPT-lite rules: plan coarse, decompose only the stuck item.

references/adapt.md is the single source of the principle and of the
``complexity_escalation`` block; planning texts and the agents point to it.
"""

from __future__ import annotations

from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
ADAPT = REPO / "references" / "adapt.md"


def _read(rel: str) -> str:
    return (REPO / rel).read_text(encoding="utf-8")


def test_adapt_reference_defines_escalation_block() -> None:
    text = ADAPT.read_text(encoding="utf-8")
    for token in ("complexity_escalation", "reason:", "estimate:", "proposed_subitems:",
                  "title:", "Files:"):
        assert token in text, f"adapt.md lacks block field {token!r}"


def test_adapt_reference_carries_triggers_fork_and_depth() -> None:
    text = ADAPT.read_text(encoding="utf-8")
    for token in ("verify_fail_cycles", "item_token_budget", "max_depth",
                  "continue", "simplify", "decompose", "skip", "arXiv 2311.05772",
                  "svp-adapt-escalation", "implemented in Stage 2"):
        assert token in text, f"adapt.md lacks {token!r}"


@pytest.mark.parametrize("rel", ("agents/mb-engineering-core.md", "agents/mb-architect.md"))
def test_agents_point_to_adapt_reference(rel: str) -> None:
    text = _read(rel)
    assert "references/adapt.md" in text
    assert "complexity_escalation" in text


@pytest.mark.parametrize(
    "rel", ("commands/plan.md", "references/effort-tiers.md", "references/templates.md"))
def test_planning_texts_mention_adapt(rel: str) -> None:
    text = _read(rel)
    assert "ADaPT" in text and "references/adapt.md" in text, rel


def test_architect_decomposes_one_item_into_two_to_five_subitems() -> None:
    text = _read("agents/mb-architect.md")
    assert "2–5 sub-items" in text and "Files:" in text and "AND" in text
