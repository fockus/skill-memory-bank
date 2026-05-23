"""RED tests for mb-traceability-gen.sh Spec Task column (Stage 1).

These tests assert the NEW contract — the `Spec Task` column in the traceability
matrix, sourced from `specs/<topic>/tasks.md` parsed via mb_work_items.py.

All tests are expected RED until Stage 2 implements the feature in
scripts/mb-traceability-gen.sh.

Public contract extensions being tested:
  T6-ext. Scan `specs/*/tasks.md` for `<!-- mb-task:N -->` markers and extract
          `**Covers:** REQ-NNN` to populate a new `Spec Task` column.
  T7.     Matrix table header includes `Spec Task` column between Spec and Plan.
  T8.     Status logic: task + tests → ✅ ; task alone → 🏗️ ; nothing → ⬜.
  T9.     Multiple tasks covering the same REQ produce comma-separated cell.
  T10.    Missing tasks.md → no crash; REQ status = ⬜.
  T11.    Script is idempotent when tasks.md is present.
"""

from __future__ import annotations

import subprocess
from pathlib import Path
from textwrap import dedent

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-traceability-gen.sh"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _run(mb: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), str(mb)],
        capture_output=True,
        text=True,
        check=False,
    )


def _make_mb(tmp_path: Path) -> Path:
    """Return a minimal .memory-bank skeleton at tmp_path."""
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "plans").mkdir()
    (mb / "plans" / "done").mkdir()
    (mb / "specs").mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    (mb / "roadmap.md").write_text("# Roadmap\n", encoding="utf-8")
    return mb


def _make_spec(mb: Path, topic: str, req_lines: str) -> Path:
    """Create specs/<topic>/ with a requirements.md and an empty design.md."""
    spec_dir = mb / "specs" / topic
    spec_dir.mkdir(parents=True, exist_ok=True)
    (spec_dir / "requirements.md").write_text(
        f"# {topic} requirements\n\n{req_lines}\n",
        encoding="utf-8",
    )
    (spec_dir / "design.md").write_text(f"# {topic} design\n", encoding="utf-8")
    return spec_dir


def _make_tasks(spec_dir: Path, content: str) -> Path:
    """Write tasks.md under spec_dir."""
    p = spec_dir / "tasks.md"
    p.write_text(content, encoding="utf-8")
    return p


def _make_plan(mb: Path, filename: str, covers: list[str]) -> Path:
    """Create a plan file with frontmatter covers_requirements."""
    covers_yaml = "[" + ", ".join(covers) + "]"
    plan_path = mb / "plans" / filename
    plan_path.write_text(
        dedent(f"""\
            ---
            type: feature
            topic: demo
            status: in_progress
            depends_on: []
            parallel_safe: false
            linked_specs: []
            sprint: 1
            phase_of: demo
            created: 2026-05-21
            covers_requirements: {covers_yaml}
            ---

            # Plan: demo
            """),
        encoding="utf-8",
    )
    return plan_path


def _matrix_row(trace: str, req_id: str) -> list[str]:
    """Return cell list for a matrix row matching req_id, or empty list."""
    matrix_section = trace.split("## Matrix", 1)[1].split("## Orphans", 1)[0]
    for line in matrix_section.splitlines():
        if line.startswith(f"| {req_id} |"):
            return [c.strip() for c in line.strip().strip("|").split("|")]
    return []


_TASK1_COVERS_REQ001 = dedent("""\
    <!-- mb-task:1 -->
    ## Task 1: persist work items

    **Covers:** REQ-001
    **Role:** developer

    **What to do:**
    - Implement persistence layer.

    **Testing (TDD):**
    - Write pytest tests.

    **DoD:**
    - [ ] Tests pass.
""")

_TASK1_COVERS_REQ002 = dedent("""\
    <!-- mb-task:1 -->
    ## Task 1: first thing

    **Covers:** REQ-002
    **Role:** developer

    **What to do:**
    - Do the first thing.

    **DoD:**
    - [ ] Done.
""")

_TASK2_COVERS_REQ002 = dedent("""\
    <!-- mb-task:2 -->
    ## Task 2: second thing

    **Covers:** REQ-002
    **Role:** developer

    **What to do:**
    - Do the second thing.

    **DoD:**
    - [ ] Done.
""")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


def test_traceability_includes_spec_task_column(tmp_path: Path) -> None:
    """Matrix table header must include the literal column name `Spec Task`."""
    # Arrange
    mb = _make_mb(tmp_path)
    spec_dir = _make_spec(
        mb, "demo",
        "- **REQ-001** (ubiquitous): The system shall persist items.",
    )
    _make_tasks(spec_dir, _TASK1_COVERS_REQ001)

    # Act
    result = _run(mb)

    # Assert
    assert result.returncode == 0, result.stderr
    trace = (mb / "traceability.md").read_text(encoding="utf-8")
    matrix_section = trace.split("## Matrix", 1)[1]
    header_line = next(
        (ln for ln in matrix_section.splitlines() if ln.startswith("|")),
        "",
    )
    assert "Spec Task" in header_line, (
        f"Matrix header must contain 'Spec Task' column, got: {header_line!r}"
    )


def test_traceability_marks_req_covered_by_spec_task(tmp_path: Path) -> None:
    """REQ-001 row's Spec Task cell must reference specs/demo/tasks.md#task-1."""
    # Arrange
    mb = _make_mb(tmp_path)
    spec_dir = _make_spec(
        mb, "demo",
        "- **REQ-001** (ubiquitous): The system shall persist items.",
    )
    _make_tasks(spec_dir, _TASK1_COVERS_REQ001)

    # Act
    result = _run(mb)

    # Assert
    assert result.returncode == 0, result.stderr
    trace = (mb / "traceability.md").read_text(encoding="utf-8")
    cells = _matrix_row(trace, "REQ-001")
    assert cells, "REQ-001 row not found in matrix"
    # Column order: REQ | Spec | Spec Task | Plan / Stage | Tests | Status
    spec_task_cell = cells[2]
    assert "specs/demo/tasks.md#task-1" in spec_task_cell, (
        f"Spec Task cell must contain 'specs/demo/tasks.md#task-1', got: {spec_task_cell!r}"
    )


def test_traceability_status_done_when_task_plan_and_tests_present(tmp_path: Path) -> None:
    """REQ-001 covered by spec task + plan stage + test mentioning REQ_001 → status ✅."""
    # Arrange
    mb = _make_mb(tmp_path)
    spec_dir = _make_spec(
        mb, "demo",
        "- **REQ-001** (ubiquitous): The system shall persist items.",
    )
    _make_tasks(spec_dir, _TASK1_COVERS_REQ001)
    _make_plan(mb, "2026-05-21_feature_demo.md", ["REQ-001"])

    # Test file mentioning REQ_001 (underscore form)
    tests_dir = mb / "tests" / "unit"
    tests_dir.mkdir(parents=True)
    (tests_dir / "test_persist.py").write_text(
        "def test_REQ_001_items_are_saved():\n    assert True\n",
        encoding="utf-8",
    )

    # Act
    result = _run(mb)

    # Assert
    assert result.returncode == 0, result.stderr
    trace = (mb / "traceability.md").read_text(encoding="utf-8")
    cells = _matrix_row(trace, "REQ-001")
    assert cells, "REQ-001 row not found in matrix"
    status_cell = cells[-1]
    assert status_cell == "✅", (
        f"Status must be ✅ when task + plan + tests present, got: {status_cell!r}"
    )


def test_traceability_status_building_when_only_task_no_tests(tmp_path: Path) -> None:
    """REQ-001 has spec task but no tests → status 🏗️."""
    # Arrange
    mb = _make_mb(tmp_path)
    spec_dir = _make_spec(
        mb, "demo",
        "- **REQ-001** (ubiquitous): The system shall persist items.",
    )
    _make_tasks(spec_dir, _TASK1_COVERS_REQ001)
    # No test files, no plan

    # Act
    result = _run(mb)

    # Assert
    assert result.returncode == 0, result.stderr
    trace = (mb / "traceability.md").read_text(encoding="utf-8")
    cells = _matrix_row(trace, "REQ-001")
    assert cells, "REQ-001 row not found in matrix"
    status_cell = cells[-1]
    assert status_cell == "🏗️", (
        f"Status must be 🏗️ when only spec task present (no tests), got: {status_cell!r}"
    )


def test_traceability_orphan_when_no_task_no_plan(tmp_path: Path) -> None:
    """REQ-003 with no task and no plan → status ⬜ and appears in Orphans section."""
    # Arrange
    mb = _make_mb(tmp_path)
    _make_spec(
        mb, "demo",
        dedent("""\
            - **REQ-001** (ubiquitous): The system shall X.
            - **REQ-002** (event-driven): When Y, the system shall Z.
            - **REQ-003** (ubiquitous): The system shall W.
        """),
    )
    spec_dir = mb / "specs" / "demo"
    # Only REQ-001 covered by a task
    _make_tasks(spec_dir, _TASK1_COVERS_REQ001)
    # No plan

    # Act
    result = _run(mb)

    # Assert
    assert result.returncode == 0, result.stderr
    trace = (mb / "traceability.md").read_text(encoding="utf-8")

    cells = _matrix_row(trace, "REQ-003")
    assert cells, "REQ-003 row not found in matrix"
    status_cell = cells[-1]
    assert status_cell == "⬜", (
        f"REQ-003 with no coverage must have status ⬜, got: {status_cell!r}"
    )

    orphans_section = trace.split("## Orphans", 1)[1]
    assert "REQ-003" in orphans_section, (
        "REQ-003 must appear in Orphans section when uncovered"
    )


def test_traceability_handles_multiple_tasks_covering_same_req(tmp_path: Path) -> None:
    """Task 1 and Task 2 both covering REQ-002 → cell has both refs comma-separated."""
    # Arrange
    mb = _make_mb(tmp_path)
    spec_dir = _make_spec(
        mb, "demo",
        "- **REQ-002** (event-driven): When Y, the system shall Z.",
    )
    _make_tasks(spec_dir, _TASK1_COVERS_REQ002 + "\n" + _TASK2_COVERS_REQ002)

    # Act
    result = _run(mb)

    # Assert
    assert result.returncode == 0, result.stderr
    trace = (mb / "traceability.md").read_text(encoding="utf-8")
    cells = _matrix_row(trace, "REQ-002")
    assert cells, "REQ-002 row not found in matrix"
    spec_task_cell = cells[2]
    assert "specs/demo/tasks.md#task-1" in spec_task_cell, (
        f"Spec Task cell must contain task-1 ref, got: {spec_task_cell!r}"
    )
    assert "specs/demo/tasks.md#task-2" in spec_task_cell, (
        f"Spec Task cell must contain task-2 ref, got: {spec_task_cell!r}"
    )


def test_traceability_handles_spec_without_tasks_file(tmp_path: Path) -> None:
    """Spec dir exists with requirements but no tasks.md → no crash, REQ status ⬜."""
    # Arrange
    mb = _make_mb(tmp_path)
    _make_spec(
        mb, "demo",
        "- **REQ-001** (ubiquitous): The system shall X.",
    )
    # Deliberately no tasks.md created

    # Act
    result = _run(mb)

    # Assert
    assert result.returncode == 0, result.stderr
    trace = (mb / "traceability.md").read_text(encoding="utf-8")
    cells = _matrix_row(trace, "REQ-001")
    assert cells, "REQ-001 row not found in matrix"
    status_cell = cells[-1]
    assert status_cell == "⬜", (
        f"REQ without tasks.md must have status ⬜, got: {status_cell!r}"
    )


def test_traceability_idempotent_after_task_scan(tmp_path: Path) -> None:
    """Running mb-traceability-gen.sh twice with tasks.md present produces identical output."""
    # Arrange
    mb = _make_mb(tmp_path)
    spec_dir = _make_spec(
        mb, "demo",
        dedent("""\
            - **REQ-001** (ubiquitous): The system shall persist items.
            - **REQ-002** (event-driven): When Y, the system shall Z.
        """),
    )
    _make_tasks(spec_dir, _TASK1_COVERS_REQ001 + "\n" + _TASK1_COVERS_REQ002)
    _make_plan(mb, "2026-05-21_feature_demo.md", ["REQ-001"])

    # Act
    first_run = _run(mb)
    assert first_run.returncode == 0, first_run.stderr
    after_first = (mb / "traceability.md").read_text(encoding="utf-8")

    second_run = _run(mb)
    assert second_run.returncode == 0, second_run.stderr
    after_second = (mb / "traceability.md").read_text(encoding="utf-8")

    # Assert
    assert after_first == after_second, (
        "mb-traceability-gen.sh must be idempotent: two runs must produce identical output"
    )
