"""Phase 2 Sprint 1 — registration & template tests.

Verify that:

* ``commands/discuss.md`` exists with proper frontmatter.
* ``commands/mb.md`` router table contains the ``discuss`` row and the
  ``### discuss`` detail section.
* ``references/templates.md`` carries the ``context/<topic>.md`` template
  with all required sections.
"""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def test_discuss_command_file_exists_with_frontmatter() -> None:
    discuss = REPO_ROOT / "commands" / "discuss.md"
    assert discuss.is_file(), "commands/discuss.md missing"
    text = discuss.read_text(encoding="utf-8")
    # Frontmatter present
    assert text.startswith("---\n"), "frontmatter must be at top"
    head = text.split("---\n", 2)[1]
    assert "description:" in head, "frontmatter must declare description"
    assert "allowed-tools:" in head, "frontmatter must declare allowed-tools"


def test_discuss_command_documents_5_phases() -> None:
    discuss = (REPO_ROOT / "commands" / "discuss.md").read_text(encoding="utf-8")
    for phase in (
        "Phase 1",
        "Phase 2",
        "Phase 3",
        "Phase 4",
        "Phase 5",
    ):
        assert phase in discuss, f"{phase} marker not found in commands/discuss.md"
    # All 5 EARS pattern names mentioned somewhere
    for pat in ("Ubiquitous", "Event-driven", "State-driven", "Optional", "Unwanted"):
        assert pat in discuss, f"EARS pattern {pat} missing"


def test_mb_router_table_lists_discuss() -> None:
    mb_md = (REPO_ROOT / "commands" / "mb.md").read_text(encoding="utf-8")
    # Look for the row in the routing table
    assert "`discuss <topic>`" in mb_md, "discuss row missing from /mb router table"


def test_mb_md_has_discuss_section() -> None:
    mb_md = (REPO_ROOT / "commands" / "mb.md").read_text(encoding="utf-8")
    assert "### discuss <topic>" in mb_md, "### discuss <topic> section missing"


def test_templates_md_has_context_template() -> None:
    tpl = (REPO_ROOT / "references" / "templates.md").read_text(encoding="utf-8")
    # Template heading
    assert "## Context (`context/<topic>.md`)" in tpl
    # Required sections inside the template
    for section in (
        "## Purpose & Users",
        "## Functional Requirements (EARS)",
        "## Non-Functional Requirements",
        "## Constraints",
        "## Edge Cases & Failure Modes",
        "## Out of Scope",
    ):
        assert section in tpl, f"context template missing section: {section}"
    # All 5 EARS pattern names mentioned in the template body
    for pat in ("ubiquitous", "event-driven", "state-driven", "optional", "unwanted"):
        assert pat in tpl, f"EARS pattern {pat} missing from template"
