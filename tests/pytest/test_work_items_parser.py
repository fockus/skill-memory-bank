"""Stage 1 RED contract tests — shared work-item parser.

Locks in the public API contract for ``scripts/mb_work_items.py`` (does not
exist yet — Stage 2 will implement it).  Every test here MUST fail with
``ModuleNotFoundError: No module named 'scripts.mb_work_items'`` and MUST NOT
fail with a SyntaxError or fixture error.

Public API being locked:

    parse_work_items(path: pathlib.Path) -> list[WorkItem]

    @dataclass(frozen=True)
    class WorkItem:
        source: Literal["plan", "spec"]
        topic: str
        item_no: int
        kind: Literal["stage", "task"]
        heading: str
        body: str
        role: str
        agent: str
        status: Literal["pending", "in-progress", "done"]
        covers: tuple[str, ...]
        dod_lines: tuple[str, ...]
"""

from __future__ import annotations

import pathlib
import textwrap

import pytest

from scripts.mb_work_items import WorkItem, parse_work_items

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

PLAN_HEADER = "---\ntype: feature\ntopic: test-topic\nstatus: in-progress\n---\n\n# Plan\n\n"


def _make_stage(no: int, heading: str, body: str = "") -> str:
    default_body = textwrap.dedent(
        f"""\
        **Covers:** REQ-{no:03d}
        **Role:** developer

        **DoD:**
        - [ ] criterion one
        """
    )
    return f"<!-- mb-stage:{no} -->\n## Stage {no}: {heading}\n\n{body or default_body}\n"


def _make_task(no: int, heading: str, body: str = "") -> str:
    default_body = textwrap.dedent(
        f"""\
        **Covers:** REQ-{no:03d}
        **Role:** developer

        **DoD:**
        - [ ] criterion one
        """
    )
    return f"<!-- mb-task:{no} -->\n## Task {no}: {heading}\n\n{body or default_body}\n"


# ──────────────────────────────────────────────────────────────────────────────
# Test 1 — plan with three stages
# ──────────────────────────────────────────────────────────────────────────────


def test_parse_plan_three_stages_returns_three_workitems(tmp_path: pathlib.Path) -> None:
    # Arrange
    plan = tmp_path / "2026-05-21_feature_foo.md"
    plan.write_text(
        PLAN_HEADER
        + _make_stage(1, "First stage")
        + _make_stage(2, "Second stage")
        + _make_stage(3, "Third stage"),
        encoding="utf-8",
    )

    # Act
    items = parse_work_items(plan)

    # Assert
    assert len(items) == 3
    assert all(isinstance(i, WorkItem) for i in items)
    assert all(i.source == "plan" for i in items)
    assert all(i.kind == "stage" for i in items)
    assert [i.item_no for i in items] == [1, 2, 3]


# ──────────────────────────────────────────────────────────────────────────────
# Test 2 — spec with three tasks
# ──────────────────────────────────────────────────────────────────────────────


def test_parse_spec_three_tasks_returns_three_workitems(tmp_path: pathlib.Path) -> None:
    # Arrange
    spec_dir = tmp_path / "my-feature"
    spec_dir.mkdir()
    tasks = spec_dir / "tasks.md"
    tasks.write_text(
        "# Tasks\n\n"
        + _make_task(1, "First task")
        + _make_task(2, "Second task")
        + _make_task(3, "Third task"),
        encoding="utf-8",
    )

    # Act
    items = parse_work_items(tasks)

    # Assert
    assert len(items) == 3
    assert all(isinstance(i, WorkItem) for i in items)
    assert all(i.source == "spec" for i in items)
    assert all(i.kind == "task" for i in items)
    assert [i.item_no for i in items] == [1, 2, 3]


# ──────────────────────────────────────────────────────────────────────────────
# Test 3 — no markers → empty list
# ──────────────────────────────────────────────────────────────────────────────


def test_parse_no_markers_returns_empty_list(tmp_path: pathlib.Path) -> None:
    # Arrange
    md = tmp_path / "plain.md"
    md.write_text(
        "# Some markdown\n\nNo markers here, just prose.\n\n## Section\n\n- item one\n",
        encoding="utf-8",
    )

    # Act
    items = parse_work_items(md)

    # Assert
    assert items == []


# ──────────────────────────────────────────────────────────────────────────────
# Test 4 — mixed markers → ValueError
# ──────────────────────────────────────────────────────────────────────────────


def test_parse_mixed_markers_raises_value_error(tmp_path: pathlib.Path) -> None:
    # Arrange
    mixed = tmp_path / "mixed.md"
    mixed.write_text(
        "# Mixed\n\n"
        + _make_stage(1, "A stage")
        + _make_task(2, "A task"),
        encoding="utf-8",
    )

    # Act / Assert
    with pytest.raises(ValueError, match="mixed"):
        parse_work_items(mixed)


# ──────────────────────────────────────────────────────────────────────────────
# Test 5 — covers: comma-separated REQ IDs
# ──────────────────────────────────────────────────────────────────────────────


def test_extract_covers_parses_comma_separated_req_ids(tmp_path: pathlib.Path) -> None:
    # Arrange
    body = textwrap.dedent(
        """\
        **Covers:** REQ-001, REQ-002

        **DoD:**
        - [ ] done
        """
    )
    plan = tmp_path / "2026-01-01_feature_covers.md"
    plan.write_text(PLAN_HEADER + _make_stage(1, "Covers test", body), encoding="utf-8")

    # Act
    items = parse_work_items(plan)

    # Assert
    assert len(items) == 1
    assert items[0].covers == ("REQ-001", "REQ-002")


# ──────────────────────────────────────────────────────────────────────────────
# Test 6 — covers: case-insensitive field label, upper-normalised IDs
# ──────────────────────────────────────────────────────────────────────────────


def test_extract_covers_case_insensitive(tmp_path: pathlib.Path) -> None:
    # Arrange — lowercase field label AND lowercase req id
    body = textwrap.dedent(
        """\
        **covers:** req-001

        **DoD:**
        - [ ] done
        """
    )
    plan = tmp_path / "2026-01-01_feature_covers_ci.md"
    plan.write_text(PLAN_HEADER + _make_stage(1, "Case insensitive covers", body), encoding="utf-8")

    # Act
    items = parse_work_items(plan)

    # Assert — parser normalises the ID to upper-case
    assert len(items) == 1
    assert "REQ-001" in items[0].covers


# ──────────────────────────────────────────────────────────────────────────────
# Test 7 — explicit Role wins over auto-detect
# ──────────────────────────────────────────────────────────────────────────────


def test_explicit_role_wins_over_autodetect(tmp_path: pathlib.Path) -> None:
    # Arrange — body has both "pytest" (qa signal) AND explicit Role: backend
    body = textwrap.dedent(
        """\
        **Covers:** REQ-007
        **Role:** backend

        Run pytest and unittest to validate endpoints.

        **DoD:**
        - [ ] tests pass
        """
    )
    plan = tmp_path / "2026-01-01_feature_explicit_role.md"
    plan.write_text(PLAN_HEADER + _make_stage(1, "Explicit role", body), encoding="utf-8")

    # Act
    items = parse_work_items(plan)

    # Assert — explicit Role overrides qa auto-detect
    assert len(items) == 1
    assert items[0].role == "backend"
    assert items[0].agent == "mb-backend"


# ──────────────────────────────────────────────────────────────────────────────
# Tests 8, 9 — role auto-detect (parametrized)
# ──────────────────────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("body_snippet", "expected_role"),
    [
        # pytest/unittest body → qa
        (
            "Run pytest and unittest. Write test_foo cases.\n\n**DoD:**\n- [ ] tests pass\n",
            "qa",
        ),
        # neutral body → developer (default)
        (
            "Update the configuration file and apply the patch.\n\n**DoD:**\n- [ ] done\n",
            "developer",
        ),
    ],
    ids=["pytest_body_yields_qa", "no_signal_defaults_to_developer"],
)
def test_role_autodetect(
    tmp_path: pathlib.Path, body_snippet: str, expected_role: str
) -> None:
    # Arrange
    body = f"**Covers:** REQ-010\n\n{body_snippet}"
    plan = tmp_path / f"2026-01-01_feature_autodetect_{expected_role}.md"
    plan.write_text(PLAN_HEADER + _make_stage(1, f"Auto detect {expected_role}", body), encoding="utf-8")

    # Act
    items = parse_work_items(plan)

    # Assert
    assert len(items) == 1
    assert items[0].role == expected_role


# ──────────────────────────────────────────────────────────────────────────────
# Tests 10, 11, 12 — status detection (parametrized)
# ──────────────────────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("dod_section", "expected_status"),
    [
        # all checked → done
        (
            "**DoD:**\n- [x] first\n- [x] second\n- [x] third\n",
            "done",
        ),
        # mix of checked and unchecked → in-progress
        (
            "**DoD:**\n- [x] first\n- [ ] second\n- [ ] third\n",
            "in-progress",
        ),
        # none checked → pending
        (
            "**DoD:**\n- [ ] first\n- [ ] second\n- [ ] third\n",
            "pending",
        ),
    ],
    ids=["all_dod_checked_is_done", "partial_dod_checked_is_in_progress", "no_dod_checked_is_pending"],
)
def test_status_detection(
    tmp_path: pathlib.Path, dod_section: str, expected_status: str
) -> None:
    # Arrange
    body = f"**Covers:** REQ-020\n**Role:** developer\n\n{dod_section}"
    plan = tmp_path / f"2026-01-01_feature_status_{expected_status}.md"
    plan.write_text(PLAN_HEADER + _make_stage(1, f"Status {expected_status}", body), encoding="utf-8")

    # Act
    items = parse_work_items(plan)

    # Assert
    assert len(items) == 1
    assert items[0].status == expected_status


# ──────────────────────────────────────────────────────────────────────────────
# Test 13 — topic from plan filename strips date prefix
# ──────────────────────────────────────────────────────────────────────────────


def test_topic_from_plan_strips_date_prefix(tmp_path: pathlib.Path) -> None:
    # Arrange — filename: 2026-05-21_feature_foo.md
    # Convention choice: topic = stem after stripping "YYYY-MM-DD_" prefix,
    # i.e. "feature_foo" (the full remainder, preserving the type segment).
    plan = tmp_path / "2026-05-21_feature_foo.md"
    plan.write_text(PLAN_HEADER + _make_stage(1, "Foo stage"), encoding="utf-8")

    # Act
    items = parse_work_items(plan)

    # Assert — topic must NOT contain the date prefix "2026-05-21_"
    assert len(items) == 1
    assert "2026-05-21" not in items[0].topic
    # Topic is everything after the date prefix: "feature_foo"
    assert items[0].topic == "feature_foo"


# ──────────────────────────────────────────────────────────────────────────────
# Test 14 — topic from spec uses parent directory name
# ──────────────────────────────────────────────────────────────────────────────


def test_topic_from_spec_uses_parent_dir_name(tmp_path: pathlib.Path) -> None:
    # Arrange — spec at specs/my-feature/tasks.md
    spec_dir = tmp_path / "specs" / "my-feature"
    spec_dir.mkdir(parents=True)
    tasks = spec_dir / "tasks.md"
    tasks.write_text(
        "# Tasks\n\n" + _make_task(1, "Initial task"),
        encoding="utf-8",
    )

    # Act
    items = parse_work_items(tasks)

    # Assert — topic comes from the parent directory, not the filename
    assert len(items) == 1
    assert items[0].topic == "my-feature"


# ──────────────────────────────────────────────────────────────────────────────
# Test 15 — dod_lines captured verbatim (count + content)
# ──────────────────────────────────────────────────────────────────────────────


def test_dod_lines_captured_verbatim(tmp_path: pathlib.Path) -> None:
    # Arrange — four checkbox lines; two checked, two not
    dod_block = textwrap.dedent(
        """\
        **DoD:**
        - [ ] write the tests
        - [x] define the schema
        - [ ] lint passes
        - [x] CI green
        """
    )
    body = f"**Covers:** REQ-099\n**Role:** developer\n\n{dod_block}"
    plan = tmp_path / "2026-01-01_feature_dod_verbatim.md"
    plan.write_text(PLAN_HEADER + _make_stage(1, "DoD verbatim", body), encoding="utf-8")

    # Act
    items = parse_work_items(plan)

    # Assert
    assert len(items) == 1
    item = items[0]
    assert len(item.dod_lines) == 4
    # Lines are preserved verbatim (including checkbox syntax)
    assert "- [ ] write the tests" in item.dod_lines
    assert "- [x] define the schema" in item.dod_lines
    assert "- [ ] lint passes" in item.dod_lines
    assert "- [x] CI green" in item.dod_lines
