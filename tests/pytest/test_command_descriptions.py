"""Command descriptions follow the Anthropic skill guide: WHAT + WHEN, concise, triggers preserved.

Claude Code lists every ``commands/*.md`` as a skill and picks commands by ``description`` only,
so each one must say what it does and when to use it, without losing any trigger word of the
pre-rewrite description (baseline snapshot in ``fixtures/command_descriptions_baseline.json``).
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest
import yaml

REPO = Path(__file__).resolve().parents[2]
COMMANDS = sorted((REPO / "commands").glob("*.md"))
BASELINE = json.loads(
    (Path(__file__).parent / "fixtures" / "command_descriptions_baseline.json").read_text(encoding="utf-8")
)
STOPWORDS = {
    "with", "from", "into", "that", "this", "the", "and", "for", "when", "use",
    "then", "than", "your", "their", "them", "over", "under", "after", "before",
    "without", "plus", "only", "also", "each", "every", "any",
}
TOTAL_BUDGET = 6000


def _frontmatter(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        return {}
    return yaml.safe_load(text.split("---\n", 2)[1]) or {}


def _significant_words(text: str) -> set[str]:
    tokens = re.findall(r"[a-z0-9]+", text.lower())
    return {t for t in tokens if len(t) >= 4 and t not in STOPWORDS}


IDS = [p.name for p in COMMANDS]


def test_baseline_covers_every_command():
    assert set(BASELINE) == set(IDS)


@pytest.mark.parametrize("path", COMMANDS, ids=IDS)
def test_description_states_what_and_when(path: Path):
    desc = _frontmatter(path).get("description")
    assert isinstance(desc, str) and 1 <= len(desc) <= 1024
    assert "use when" in desc.lower()
    assert not re.search(r"<[A-Za-z/!?][^>]*>", desc), "no XML tags (write placeholders as {topic})"
    assert not desc.startswith(("I ", "You "))


@pytest.mark.parametrize("path", COMMANDS, ids=IDS)
def test_no_disable_model_invocation(path: Path):
    # AGR-061: Claude keeps auto-invoking every command
    assert "disable-model-invocation" not in _frontmatter(path)


@pytest.mark.parametrize("path", COMMANDS, ids=IDS)
def test_old_trigger_words_preserved(path: Path):
    new = _frontmatter(path).get("description", "").lower()
    missing = sorted(w for w in _significant_words(BASELINE[path.name]) if w not in new)
    assert missing == []


def test_total_description_length_within_listing_budget():
    total = sum(len(_frontmatter(p).get("description", "")) for p in COMMANDS)
    assert total <= TOTAL_BUDGET, total
