"""Phase 3 Sprint 1 — registration tests for `/mb config` + pipeline.yaml."""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def test_config_command_file_exists_with_frontmatter() -> None:
    p = REPO_ROOT / "commands" / "config.md"
    assert p.is_file(), "commands/config.md missing"
    text = p.read_text(encoding="utf-8")
    assert text.startswith("---\n")
    head = text.split("---\n", 2)[1]
    assert "description:" in head
    assert "allowed-tools:" in head


def test_config_command_documents_subcommands() -> None:
    text = (REPO_ROOT / "commands" / "config.md").read_text(encoding="utf-8")
    for sub in ("init", "show", "validate", "path"):
        assert sub in text, f"commands/config.md must mention '{sub}' subcommand"


def test_mb_router_table_lists_config() -> None:
    text = (REPO_ROOT / "commands" / "mb.md").read_text(encoding="utf-8")
    assert "`config" in text


def test_mb_md_has_config_section() -> None:
    text = (REPO_ROOT / "commands" / "mb.md").read_text(encoding="utf-8")
    assert "### config" in text


def test_pipeline_default_at_expected_path() -> None:
    assert (REPO_ROOT / "references" / "pipeline.default.yaml").is_file()
