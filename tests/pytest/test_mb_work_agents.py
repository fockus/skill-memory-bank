"""Phase 3 Sprint 2 — registration tests for /mb work agent files."""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
AGENTS = REPO_ROOT / "agents"

EXPECTED_AGENTS = (
    "mb-developer",
    "mb-backend",
    "mb-frontend",
    "mb-ios",
    "mb-android",
    "mb-architect",
    "mb-devops",
    "mb-qa",
    "mb-analyst",
    "mb-reviewer",
)


@pytest.mark.parametrize("agent", EXPECTED_AGENTS)
def test_agent_file_exists(agent: str) -> None:
    p = AGENTS / f"{agent}.md"
    assert p.is_file(), f"missing agents/{agent}.md"


@pytest.mark.parametrize("agent", EXPECTED_AGENTS)
def test_agent_frontmatter_keys(agent: str) -> None:
    text = (AGENTS / f"{agent}.md").read_text(encoding="utf-8")
    assert text.startswith("---\n"), f"{agent}: missing frontmatter open"
    parts = text.split("---\n", 2)
    assert len(parts) >= 3, f"{agent}: malformed frontmatter"
    fm = parts[1]
    for key in ("name", "description", "model"):
        assert re.search(rf"^{key}:", fm, re.M), f"{agent}: missing '{key}'"


@pytest.mark.parametrize("agent", EXPECTED_AGENTS)
def test_agent_name_matches_filename(agent: str) -> None:
    text = (AGENTS / f"{agent}.md").read_text(encoding="utf-8")
    m = re.search(r"^name:\s*([\w\-]+)\s*$", text.split("---\n", 2)[1], re.M)
    assert m is not None
    assert m.group(1) == agent, f"{agent}: name field mismatch"


@pytest.mark.parametrize("agent", EXPECTED_AGENTS)
def test_agent_model_is_sonnet(agent: str) -> None:
    text = (AGENTS / f"{agent}.md").read_text(encoding="utf-8")
    m = re.search(r"^model:\s*([\w\-]+)\s*$", text.split("---\n", 2)[1], re.M)
    assert m is not None
    assert m.group(1) == "sonnet", f"{agent}: model must be 'sonnet'"
