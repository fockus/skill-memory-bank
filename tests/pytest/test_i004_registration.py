"""I-004 registration — script presence + commands/done.md wiring + backlog flip."""

from __future__ import annotations

import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def test_auto_commit_script_exists_and_executable() -> None:
    p = REPO_ROOT / "scripts" / "mb-auto-commit.sh"
    assert p.exists()
    assert os.access(p, os.X_OK)


def test_commands_done_references_auto_commit() -> None:
    text = (REPO_ROOT / "commands" / "done.md").read_text(encoding="utf-8")
    assert "mb-auto-commit.sh" in text
    assert "MB_AUTO_COMMIT" in text


def test_backlog_i004_flipped_to_done() -> None:
    text = (REPO_ROOT / ".memory-bank" / "backlog.md").read_text(encoding="utf-8")
    # Find the I-004 section and verify it's marked DONE.
    idx = text.index("### I-004")
    end = text.find("\n### ", idx + 1)
    section = text[idx: end if end != -1 else len(text)]
    assert "DONE" in section, f"I-004 not flipped to DONE: {section[:200]}"
    assert "Outcome" in section, "I-004 missing **Outcome:** line"
