"""Always-loaded texts follow the effort tiers instead of demanding full ceremony on every task.

AGR-067 (five tiers), AGR-069 (the `/mb work` gate fires only when a plan/spec exists),
AGR-070 (coverage is opt-in with profile thresholds), AGR-078 (DoD for the plan, per stage only
at a real boundary). Source of the tiers: references/effort-tiers.md.
"""

from __future__ import annotations

from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
GLOBAL = ROOT / "rules" / "CLAUDE-GLOBAL.md"
TEMPLATE = ROOT / "references" / "claude-md-template.md"
PROJECT = ROOT / "CLAUDE.md"
RULES = ROOT / "rules" / "RULES.md"
ALWAYS_LOADED = [GLOBAL, TEMPLATE, PROJECT]

UNCONDITIONAL = [
    "Every task carries SMART DoD",
    "Coverage — overall 85%",
    "Coverage 85%+",
    "Multi-stage work → plan first",
    "multi-stage work → a `/mb plan` plan first",
]


@pytest.mark.parametrize("path", ALWAYS_LOADED, ids=lambda p: p.name)
@pytest.mark.parametrize("phrase", UNCONDITIONAL)
def test_always_loaded_text_has_no_unconditional_ceremony(path: Path, phrase: str) -> None:
    assert phrase not in path.read_text(encoding="utf-8")


@pytest.mark.parametrize("path", ALWAYS_LOADED, ids=lambda p: p.name)
def test_always_loaded_text_points_to_task_routing(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    assert "Task routing" in text or "effort-tiers" in text


@pytest.mark.parametrize("path", [PROJECT, TEMPLATE], ids=lambda p: p.name)
def test_work_gate_is_conditional_on_an_existing_plan_or_spec(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    headings = [line for line in text.splitlines() if line.startswith("#")]
    assert not [h for h in headings if "Mandatory" in h]
    assert "existing plan or spec" in text


def test_rules_tie_tdd_coverage_and_planning_to_the_tier() -> None:
    text = RULES.read_text(encoding="utf-8")
    assert "Multi-stage work → plan first" not in text
    assert "- Target: **85%+** overall" not in text
    coverage = text.split("### Coverage", 1)[1].split("\n---\n", 1)[0]
    assert "profile" in coverage
    tdd = text.split("## TDD — Test-Driven Development", 1)[1].split("\n---\n", 1)[0]
    assert "trivial" in tdd and "one test per stated behavior" in tdd
    assert "effort-tiers" in text.split("## Core rules", 1)[1].split("\n---\n", 1)[0]
