"""Doc-contract tests for the unified SDD-flow documentation.

Locks the contract that SKILL.md / commands / references/templates.md
describe the SDD-flow (discuss → sdd → work <topic> → verify → done)
consistently and reference the correct scripts and task format.
"""

from pathlib import Path

REPO = Path(__file__).parent.parent.parent


def _read(rel: str) -> str:
    return (REPO / rel).read_text()


def test_skill_md_documents_mb_task_marker() -> None:
    """SKILL.md contains the mb-task marker string (Tools row or Quick start)."""
    content = _read("SKILL.md")
    assert "mb-task" in content, "SKILL.md must mention the <!-- mb-task:N --> format"


def test_skill_md_lists_mb_work_items_in_tools() -> None:
    """SKILL.md Tools table contains mb_work_items.py."""
    content = _read("SKILL.md")
    assert "mb_work_items.py" in content, "SKILL.md Tools table must list mb_work_items.py"


def test_skill_md_lists_mb_spec_validate_in_tools() -> None:
    """SKILL.md Tools table contains mb-spec-validate.sh."""
    content = _read("SKILL.md")
    assert "mb-spec-validate.sh" in content, (
        "SKILL.md Tools table must list mb-spec-validate.sh"
    )


def test_skill_md_lists_mb_spec_tasks_migrate_in_tools() -> None:
    """SKILL.md Tools table contains mb-spec-tasks-migrate.sh."""
    content = _read("SKILL.md")
    assert "mb-spec-tasks-migrate.sh" in content, (
        "SKILL.md Tools table must list mb-spec-tasks-migrate.sh"
    )


def test_commands_sdd_md_references_spec_validate() -> None:
    """commands/sdd.md contains mb-spec-validate.sh."""
    content = _read("commands/sdd.md")
    assert "mb-spec-validate.sh" in content, (
        "commands/sdd.md must reference mb-spec-validate.sh as part of SDD-flow"
    )


def test_commands_plan_md_documents_linked_spec_wrapper() -> None:
    """commands/plan.md contains both linked_spec and tasks: strings."""
    content = _read("commands/plan.md")
    assert "linked_spec" in content, (
        "commands/plan.md must document the linked_spec frontmatter key"
    )
    assert "tasks:" in content, (
        "commands/plan.md must document the tasks: frontmatter key for plan-as-wrapper"
    )


def test_templates_md_has_spec_tasks_template() -> None:
    """references/templates.md contains both the mb-task marker and linked_spec."""
    content = _read("references/templates.md")
    assert "<!-- mb-task:" in content, (
        "references/templates.md must contain an <!-- mb-task:N --> template block"
    )
    assert "linked_spec" in content, (
        "references/templates.md must contain a linked_spec frontmatter example"
    )
