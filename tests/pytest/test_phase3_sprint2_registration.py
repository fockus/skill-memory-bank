"""Phase 3 Sprint 2 — registration tests for /mb work."""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def test_work_command_file_exists_with_frontmatter() -> None:
    p = REPO_ROOT / "commands" / "work.md"
    assert p.is_file(), "commands/work.md missing"
    text = p.read_text(encoding="utf-8")
    assert text.startswith("---\n")
    head = text.split("---\n", 2)[1]
    assert "description:" in head
    assert "allowed-tools:" in head


def test_work_command_documents_resolution_forms() -> None:
    text = (REPO_ROOT / "commands" / "work.md").read_text(encoding="utf-8")
    for keyword in ("Existing path", "Substring", "Topic name", "Freeform", "Empty"):
        assert keyword in text, f"commands/work.md missing '{keyword}'"


def test_work_command_documents_range_and_dry_run() -> None:
    text = (REPO_ROOT / "commands" / "work.md").read_text(encoding="utf-8")
    assert "--range" in text
    assert "--dry-run" in text


def test_mb_router_table_lists_work() -> None:
    text = (REPO_ROOT / "commands" / "mb.md").read_text(encoding="utf-8")
    assert "`work " in text


def test_mb_md_has_work_section() -> None:
    text = (REPO_ROOT / "commands" / "mb.md").read_text(encoding="utf-8")
    assert "### work " in text


def test_resolve_script_present() -> None:
    assert (REPO_ROOT / "scripts" / "mb-work-resolve.sh").is_file()


def test_range_script_present() -> None:
    assert (REPO_ROOT / "scripts" / "mb-work-range.sh").is_file()


def test_plan_script_present() -> None:
    assert (REPO_ROOT / "scripts" / "mb-work-plan.sh").is_file()
