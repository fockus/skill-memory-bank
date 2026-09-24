"""SRP/DRY wording and the code-graph routing table each live in one canonical place.

Copies that drifted apart (SRP "candidate" vs "split" vs "split if both", DRY "extract three
identical lines" vs "three identical lines beat an abstraction", four routing tables) left the
agent reconciling contradictory rules on every item.
"""

from __future__ import annotations

from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
RULE_SURFACES = [
    REPO_ROOT / "rules" / "CLAUDE-GLOBAL.md",
    REPO_ROOT / "rules" / "RULES.md",
    *sorted((REPO_ROOT / "agents").glob("*.md")),
]
CONTRADICTING_PHRASES = [
    "Split if both are violated",
    "three identical lines justify extraction",
    "duplication >2",
    "duplicate >2 times",
    "≥ 3 offenders = CRITICAL",
    "CRITICAL (≥3 files)",
    "≥ 2 identical 3+ line blocks",
]


@pytest.mark.parametrize("path", RULE_SURFACES, ids=lambda p: p.name)
def test_no_surface_restates_srp_or_dry_against_the_canon(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    for phrase in CONTRADICTING_PHRASES:
        assert phrase not in text, (path.name, phrase)


def test_canon_states_the_diff_based_srp_block() -> None:
    rules = (REPO_ROOT / "rules" / "RULES.md").read_text(encoding="utf-8")
    assert "split candidate (WARNING)" in rules
    assert "pushes the file over the threshold" in rules
    assert "the same logic in 3+ places" in rules


def test_code_graph_routing_table_lives_only_in_tooling_core() -> None:
    marker = "Code-understanding tools (graph-first, fail-open)"
    holders = [p.name for p in (REPO_ROOT / "agents").glob("*.md") if marker in p.read_text(encoding="utf-8")]
    assert holders == ["mb-tooling-core.md"]
    stale_copies = [
        p.name for p in (REPO_ROOT / "agents").glob("*.md")
        if "Code-graph routing (when the graph is fresh)" in p.read_text(encoding="utf-8")
    ]
    assert stale_copies == []
