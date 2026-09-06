"""mb-work-cost-diet Sprint 1 Stage 4 — status.md rotation is wired into `/mb done`.

A rotation script nobody calls is dead weight: both the executing agent prompt
and the command doc must name it, or `status.md` keeps growing unbounded.
"""

from __future__ import annotations

from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]


@pytest.mark.parametrize("doc", ["agents/mb-manager.md", "commands/done.md"])
def test_done_flow_documents_status_rotation(doc: str) -> None:
    text = (REPO_ROOT / doc).read_text(encoding="utf-8")
    assert "mb-status-rotate.sh" in text, f"{doc}: `/mb done` flow never invokes mb-status-rotate.sh"
    assert "--apply" in text
