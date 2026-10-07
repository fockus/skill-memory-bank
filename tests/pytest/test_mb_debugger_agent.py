"""mb-debugger — systematic-debugging discipline ported from superpowers (MIT).

The agent body keeps the four-phase process and the Iron Law; every bundled
reference/script path it names must ship with the skill.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
AGENT = REPO_ROOT / "agents" / "mb-debugger.md"
COPIED = [
    "references/debugging/root-cause-tracing.md",
    "references/debugging/defense-in-depth.md",
    "references/debugging/condition-based-waiting.md",
    "references/debugging/condition-based-waiting-example.ts",
    "scripts/mb-find-polluter.sh",
]


def test_debugger_agent_keeps_iron_law() -> None:
    assert "NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST" in AGENT.read_text(encoding="utf-8")


@pytest.mark.parametrize(
    "heading",
    [
        "### Phase 1: Root Cause Investigation",
        "### Phase 2: Pattern Analysis",
        "### Phase 3: Hypothesis and Testing",
        "### Phase 4: Implementation",
    ],
)
def test_debugger_agent_has_four_phases(heading: str) -> None:
    assert heading in AGENT.read_text(encoding="utf-8").splitlines()


def test_debugger_agent_bundled_paths_exist() -> None:
    text = AGENT.read_text(encoding="utf-8")
    paths = set(re.findall(r"(?:references/debugging|scripts)/[\w.-]+\.(?:md|ts|sh)", text))
    assert "scripts/mb-find-polluter.sh" in paths
    assert {p for p in paths if p.startswith("references/debugging/")} >= {
        "references/debugging/root-cause-tracing.md",
        "references/debugging/defense-in-depth.md",
        "references/debugging/condition-based-waiting.md",
    }
    missing = sorted(p for p in paths if not (REPO_ROOT / p).is_file())
    assert not missing, missing


def test_debugger_agent_drops_superpowers_skill_references() -> None:
    assert "superpowers:" not in AGENT.read_text(encoding="utf-8")


@pytest.mark.parametrize("rel", COPIED + ["agents/mb-debugger.md"])
def test_ported_files_carry_mit_attribution(rel: str) -> None:
    head = "\n".join((REPO_ROOT / rel).read_text(encoding="utf-8").splitlines()[:12])
    assert "superpowers" in head and "MIT" in head, rel
