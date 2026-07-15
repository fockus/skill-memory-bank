"""Tests for `scripts/mb_openspec_convert.py` — deterministic converter.

Contract (design.md § Interfaces):
    convert(ch, prior_triple=None, normalize=False) -> (requirements_md, design_md, tasks_md)

NFR-001: identical input yields byte-identical output; a committed golden
fixture guards regressions and a second `convert()` call must be idempotent.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = REPO_ROOT / "scripts"
FIXTURE = (
    REPO_ROOT / "tests" / "pytest" / "fixtures" / "openspec" / "changes" / "add-metadata-tracking"
)
GOLDEN = (
    REPO_ROOT / "tests" / "pytest" / "fixtures" / "openspec" / "golden" / "add-metadata-tracking"
)

if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import mb_openspec_convert as convert_mod  # noqa: E402
import mb_openspec_parse as parse_mod  # noqa: E402
from mb_openspec_model import OSChange, OSRequirement  # noqa: E402


def _convert():
    ch = parse_mod.parse_change(FIXTURE)
    return convert_mod.convert(ch)


def _change_with_requirement(req: OSRequirement) -> OSChange:
    return OSChange(
        change_id="adversarial-change",
        why="why",
        what_changes="what",
        design_md=None,
        requirements=[req],
        task_groups=[],
        source_hash="deadbeef",
    )


def test_convert_requirements_matches_golden_fixture_byte_for_byte() -> None:
    requirements_md, _design_md, _tasks_md = _convert()
    expected = (GOLDEN / "requirements.md").read_text(encoding="utf-8")
    assert requirements_md == expected


def test_convert_design_matches_golden_fixture_byte_for_byte() -> None:
    _requirements_md, design_md, _tasks_md = _convert()
    expected = (GOLDEN / "design.md").read_text(encoding="utf-8")
    assert design_md == expected


def test_convert_tasks_matches_golden_fixture_byte_for_byte() -> None:
    _requirements_md, _design_md, tasks_md = _convert()
    expected = (GOLDEN / "tasks.md").read_text(encoding="utf-8")
    assert tasks_md == expected


def test_convert_is_idempotent_on_a_second_call() -> None:
    ch = parse_mod.parse_change(FIXTURE)
    first = convert_mod.convert(ch)
    second = convert_mod.convert(ch)
    assert first == second


def test_convert_every_emitted_requirement_carries_an_anchor_comment() -> None:
    requirements_md, _design_md, _tasks_md = _convert()
    assert "<!-- openspec-req: Change Metadata -->" in requirements_md
    assert "<!-- openspec-req: Metadata Schema Version -->" in requirements_md
    assert "<!-- openspec-req: Change Status Field -->" in requirements_md


def test_convert_removed_requirement_becomes_a_design_removed_scope_note() -> None:
    requirements_md, design_md, _tasks_md = _convert()
    assert "Legacy Status Comment" not in requirements_md
    assert "## Removed scope" in design_md
    assert "### Legacy Status Comment" in design_md
    assert "Superseded by the structured status field" in design_md


def test_convert_renamed_requirement_is_deferred_not_emitted_as_req(capsys) -> None:
    requirements_md, design_md, _tasks_md = _convert()
    assert "REQ-004" not in requirements_md  # only ADDED+MODIFIED consume REQ-NNN
    assert "Change Owner" not in requirements_md
    assert "Change Owner" in design_md  # surfaced as a deferred-rename note instead
    captured = capsys.readouterr()
    assert "deferred to re-import" in captured.err


def test_convert_non_checkbox_task_becomes_plain_text_line() -> None:
    _requirements_md, _design_md, tasks_md = _convert()
    assert "- 1.3 Update the CLI docs (no checkbox — legacy note)" in tasks_md
    assert "- [ ] 1.3" not in tasks_md
    assert "- [x] 1.3" not in tasks_md


def test_convert_requirement_without_scenarios_gets_deterministic_stub(capsys) -> None:
    requirements_md, _design_md, _tasks_md = _convert()
    assert "### Scenario: (none provided)" in requirements_md
    captured = capsys.readouterr()
    assert "no scenarios" in captured.err


def test_convert_req_ids_are_monotonic_in_document_order() -> None:
    requirements_md, _design_md, _tasks_md = _convert()
    assert "**REQ-001**" in requirements_md
    assert "**REQ-002**" in requirements_md
    assert "**REQ-003**" in requirements_md
    assert requirements_md.index("REQ-001") < requirements_md.index("REQ-002")
    assert requirements_md.index("REQ-002") < requirements_md.index("REQ-003")


def test_convert_neutralizes_comment_delimiters_in_a_malicious_requirement_name(
    capsys,
) -> None:
    """A hostile OpenSpec name must not forge markers or leave dangling '-->'."""
    malicious = OSRequirement(
        name="Foo --> <!-- mb-task:99 -->",
        text="The system SHALL do the thing.",
        change_kind="added",
    )
    ch = _change_with_requirement(malicious)
    requirements_md, _design_md, _tasks_md = convert_mod.convert(ch)

    assert "<!-- mb-task:99 -->" not in requirements_md
    assert "<!-- mb-task:" not in requirements_md

    anchor_lines = [
        line for line in requirements_md.splitlines() if line.startswith("<!-- openspec-req:")
    ]
    assert len(anchor_lines) == 1
    anchor_line = anchor_lines[0]
    assert anchor_line == "<!-- openspec-req: Foo --&gt; &lt;!-- mb-task:99 --&gt; -->"
    # No dangling '-->' outside of the well-formed anchors/scenario markers.
    stray = requirements_md.replace(anchor_line, "")
    stray = re.sub(r"<!--\s*/?mb-scenario:\d+\s*-->", "", stray)
    assert "-->" not in stray

    captured = capsys.readouterr()
    assert "comment delimiters" in captured.err


def test_convert_golden_fixture_names_are_untouched_by_anchor_safe() -> None:
    """The committed golden fixture has no comment-delimiter names — no-op."""
    ch = parse_mod.parse_change(FIXTURE)
    for req in ch.requirements:
        assert convert_mod.anchor_safe(req.name) == req.name
