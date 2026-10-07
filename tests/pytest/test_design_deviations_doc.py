"""Deliberate deviations from the Anthropic skill guide are recorded as ADRs.

Plan 2026-10-06_fix_anthropic-skill-guide-compliance-sprint1-skill, Stage 5.
"""

from __future__ import annotations

from pathlib import Path

import pytest

DOC = Path(__file__).resolve().parents[2] / "references" / "design-principles.md"
HEADING = "## Anthropic skill guide: deliberate deviations"


def _section() -> str:
    text = DOC.read_text(encoding="utf-8")
    assert HEADING in text
    body = text.split(HEADING, 1)[1]
    return body.split("\n## ", 1)[0]


def test_deviations_section_listed_in_contents_toc() -> None:
    toc = DOC.read_text(encoding="utf-8").split("\n## ", 2)[1]
    assert toc.startswith("Contents")
    assert "(#anthropic-skill-guide-deliberate-deviations)" in toc


@pytest.mark.parametrize(
    "token",
    ["CLAUDE_SKILL_DIR", "881", "head -100", "AGR-061", "skill-memory-bank"],
)
def test_deviations_section_records_each_decision(token: str) -> None:
    assert token in _section()


def test_deviations_section_has_five_adr_items_with_sources() -> None:
    section = _section()
    assert section.count("\n### ") == 5
    for part in ("Context", "Decision", "Alternatives", "Consequences"):
        assert section.count(f"**{part}.**") == 5
    assert "platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices" in section
    assert "code.claude.com/docs/en/skills" in section
