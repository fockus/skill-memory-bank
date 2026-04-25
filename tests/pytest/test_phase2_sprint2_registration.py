"""Phase 2 Sprint 2 — registration tests for /mb sdd."""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def test_sdd_command_file_exists_with_frontmatter() -> None:
    p = REPO_ROOT / "commands" / "sdd.md"
    assert p.is_file(), "commands/sdd.md missing"
    text = p.read_text(encoding="utf-8")
    assert text.startswith("---\n")
    head = text.split("---\n", 2)[1]
    assert "description:" in head
    assert "allowed-tools:" in head


def test_sdd_command_documents_three_files() -> None:
    text = (REPO_ROOT / "commands" / "sdd.md").read_text(encoding="utf-8")
    for fname in ("requirements.md", "design.md", "tasks.md"):
        assert fname in text, f"commands/sdd.md must mention {fname}"


def test_mb_router_table_lists_sdd() -> None:
    text = (REPO_ROOT / "commands" / "mb.md").read_text(encoding="utf-8")
    assert "`sdd <topic>" in text


def test_mb_md_has_sdd_section() -> None:
    text = (REPO_ROOT / "commands" / "mb.md").read_text(encoding="utf-8")
    assert "### sdd <topic>" in text


def test_templates_md_has_spec_triple_templates() -> None:
    text = (REPO_ROOT / "references" / "templates.md").read_text(encoding="utf-8")
    assert "Spec Requirements" in text
    assert "Spec Design" in text
    assert "Spec Tasks" in text
