"""Contract: the MB drift/auto-commit recipe stays documented (I-087 B2).

The audit found MB_AUTO_COMMIT existed but was documented nowhere as a recipe, and the
new mb-freshness.sh drift alarm needs a discoverable home. This pins both so the recipe
cannot silently drift out of the docs.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / "SKILL.md"
SESSION_DOC = ROOT / "docs" / "concepts" / "session-memory.md"
DONE = ROOT / "commands" / "done.md"


def test_skill_documents_auto_commit_recipe() -> None:
    text = SKILL.read_text(encoding="utf-8")
    assert "MB_AUTO_COMMIT" in text, "SKILL.md must document the MB_AUTO_COMMIT recipe"


def test_session_doc_documents_auto_commit_and_freshness() -> None:
    text = SESSION_DOC.read_text(encoding="utf-8")
    assert "MB_AUTO_COMMIT" in text, "session-memory.md must show the MB_AUTO_COMMIT recipe"
    assert "mb-freshness.sh" in text, (
        "session-memory.md must reference the mb-freshness.sh drift alarm"
    )


def test_done_command_links_auto_commit_and_freshness() -> None:
    text = DONE.read_text(encoding="utf-8")
    assert "MB_AUTO_COMMIT" in text, "commands/done.md must mention MB_AUTO_COMMIT"
    assert "mb-freshness.sh" in text, "commands/done.md must note the freshness/drift relationship"
