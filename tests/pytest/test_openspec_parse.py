"""Tests for `scripts/mb_openspec_parse.py` — read-only OpenSpec change parser.

Contract (design.md § Interfaces):
    parse_change(change_dir: Path) -> OSChange

Fixture: `tests/pytest/fixtures/openspec/changes/add-metadata-tracking/` — a
real-marker OpenSpec change with one ADDED requirement + scenario, one ADDED
requirement with zero scenarios, one MODIFIED requirement + scenario, one
REMOVED requirement with a Reason, one RENAMED requirement (FROM/TO), and a
tasks.md with a checkbox item, a checked item, and a non-checkbox line.
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = REPO_ROOT / "scripts"
FIXTURE = (
    REPO_ROOT / "tests" / "pytest" / "fixtures" / "openspec" / "changes" / "add-metadata-tracking"
)

if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import mb_openspec_parse as parse_mod  # noqa: E402


def _parse():
    return parse_mod.parse_change(FIXTURE)


def test_parse_change_returns_change_id_from_dir_name() -> None:
    ch = _parse()
    assert ch.change_id == "add-metadata-tracking"


def test_parse_change_extracts_why_and_what_changes() -> None:
    ch = _parse()
    assert "Change metadata is currently untracked" in ch.why
    assert "Add a `.openspec.yaml` metadata file" in ch.what_changes


def test_parse_change_reads_optional_design_md() -> None:
    ch = _parse()
    assert ch.design_md is not None
    assert "## Decisions" in ch.design_md


def test_parse_change_maps_added_requirements() -> None:
    ch = _parse()
    added = [r for r in ch.requirements if r.change_kind == "added"]
    names = [r.name for r in added]
    assert names == ["Change Metadata", "Metadata Schema Version"]
    assert "SHALL store and validate" in added[0].text


def test_parse_change_maps_modified_requirements() -> None:
    ch = _parse()
    modified = [r for r in ch.requirements if r.change_kind == "modified"]
    assert len(modified) == 1
    assert modified[0].name == "Change Status Field"


def test_parse_change_maps_removed_requirements_with_reason() -> None:
    ch = _parse()
    removed = [r for r in ch.requirements if r.change_kind == "removed"]
    assert len(removed) == 1
    assert removed[0].name == "Legacy Status Comment"
    assert removed[0].reason is not None
    assert "Superseded by the structured status field" in removed[0].reason


def test_parse_change_maps_renamed_requirements() -> None:
    ch = _parse()
    renamed = [r for r in ch.requirements if r.change_kind == "renamed"]
    assert len(renamed) == 1
    assert renamed[0].renamed_from == "Change Owner"
    assert renamed[0].name == "Change Author"


def test_parse_change_maps_scenarios_when_then() -> None:
    ch = _parse()
    change_metadata = next(r for r in ch.requirements if r.name == "Change Metadata")
    assert len(change_metadata.scenarios) == 1
    scenario = change_metadata.scenarios[0]
    assert scenario.name == "Metadata file created with new change"
    assert scenario.steps == [
        ("WHEN", "user runs `openspec new change add-feature`"),
        ("THEN", "the system creates `.openspec.yaml` in the change directory"),
    ]


def test_parse_change_requirement_without_scenario_has_empty_list() -> None:
    ch = _parse()
    schema_req = next(r for r in ch.requirements if r.name == "Metadata Schema Version")
    assert schema_req.scenarios == []


def test_parse_change_maps_task_groups_and_checkbox_state() -> None:
    ch = _parse()
    assert [g.number for g in ch.task_groups] == ["1", "2"]
    group1 = ch.task_groups[0]
    assert group1.title == "Metadata plumbing"
    assert group1.items[0] == (False, "1.1 Add `.openspec.yaml` schema")
    assert group1.items[1] == (True, "1.2 Wire schema validation into `openspec new change`")


def test_parse_change_non_checkbox_task_line_imported_as_plain_text_with_warning(
    capsys,
) -> None:
    ch = _parse()
    group1 = ch.task_groups[0]
    checked, text = group1.items[2]
    assert checked is None
    assert text == "1.3 Update the CLI docs (no checkbox — legacy note)"
    captured = capsys.readouterr()
    assert "non-checkbox task line" in captured.err


def test_parse_change_source_hash_is_stable_across_repeated_parses() -> None:
    first = parse_mod.parse_change(FIXTURE).source_hash
    second = parse_mod.parse_change(FIXTURE).source_hash
    assert first == second
    assert len(first) == 64  # sha256 hex digest


def test_parse_change_missing_dir_raises_file_not_found() -> None:
    import pytest

    with pytest.raises(FileNotFoundError):
        parse_mod.parse_change(FIXTURE.parent / "does-not-exist")


def test_parse_change_is_read_only(tmp_path) -> None:
    """Parsing must never write anything, anywhere (design.md § Architecture)."""
    import shutil

    copy_dir = tmp_path / "add-metadata-tracking"
    shutil.copytree(FIXTURE, copy_dir)
    before = {
        p.relative_to(copy_dir): p.stat().st_mtime_ns for p in copy_dir.rglob("*") if p.is_file()
    }
    parse_mod.parse_change(copy_dir)
    after = {
        p.relative_to(copy_dir): p.stat().st_mtime_ns for p in copy_dir.rglob("*") if p.is_file()
    }
    assert before == after
    assert set(before) == set(after)
