"""mb-work-cost-diet Sprint 1 Stage 6 — the board is read through `mb-coord.sh active`.

A 200 KB append-only board that every agent is told to "read before stages,
commits and shared-file edits" is a per-session tax. The docs that carry that
instruction must name the command instead, or the tax stays.
"""

from __future__ import annotations

from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]


@pytest.mark.parametrize("doc", ["agents/mb-engineering-core.md", "references/coordination.md"])
def test_board_readers_are_pointed_at_mb_coord_active(doc: str) -> None:
    text = (REPO_ROOT / doc).read_text(encoding="utf-8")
    assert "mb-coord.sh active" in text, f"{doc}: still sends the reader at the whole board"


def test_coordination_reference_documents_the_tag_grammar() -> None:
    text = (REPO_ROOT / "references/coordination.md").read_text(encoding="utf-8")
    for tag in ("FREEZE", "LIFT", "HANDOVER", "ACK", "STATUS"):
        assert f"## {tag} ·" in text, f"tag grammar for {tag} is undocumented"
