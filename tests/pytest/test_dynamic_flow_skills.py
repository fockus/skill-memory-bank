"""dynamic-flow T14: critique / risk-find / final-report are self-contained commands."""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
COMMANDS = REPO_ROOT / "commands"
TEMPLATES = REPO_ROOT / "flow-templates"
SKILLS = ("critique", "risk-find", "final-report")


def _frontmatter(name: str) -> dict[str, str]:
    text = (COMMANDS / f"{name}.md").read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    assert m, f"{name}.md has no frontmatter"
    out: dict[str, str] = {}
    for line in m.group(1).splitlines():
        key, _, value = line.partition(":")
        out[key.strip()] = value.strip()
    return out


@pytest.mark.parametrize("name", SKILLS)
def test_skill_frontmatter_has_description_and_tools(name: str) -> None:
    fm = _frontmatter(name)
    assert len(fm.get("description", "").strip('"')) > 40
    assert fm.get("allowed-tools", "").startswith("[")


@pytest.mark.parametrize("name", SKILLS)
def test_skill_is_referenced_by_a_flow_template(name: str) -> None:
    refs = [p.name for p in TEMPLATES.glob("*.md") if re.search(rf"`{name}`|\*\*{name}\*\*", p.read_text(encoding="utf-8"))]
    assert refs, f"no flow template references `{name}`"


@pytest.mark.parametrize("name", SKILLS)
def test_skill_declares_file_based_io_and_does_not_wrap_external_skills(name: str) -> None:
    text = (COMMANDS / f"{name}.md").read_text(encoding="utf-8")
    assert "## Input" in text and "## Output" in text
    assert "reflexion" not in text and "sadd" not in text


def test_critique_declares_validator_feedback_retry() -> None:
    text = (COMMANDS / "critique.md").read_text(encoding="utf-8")
    assert "## Validator-feedback retry" in text
    assert "checklist" in text
    assert re.search(r"max(imum)? attempts?.*\b2\b|default 2", text, re.I)
    assert "failed checks" in text
    assert "remaining failures" in text
