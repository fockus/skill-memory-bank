"""Tests for OpenSpec re-import — anchor matching + progress preservation (T5).

Contract (design.md § Interfaces — Covers REQ-016, REQ-017, REQ-018):

    anchor_map(prior_requirements_md) -> {openspec-name: REQ-NNN}       (D-06)
    merge_task_state(new_tasks_md, prior_tasks_md) -> (merged_md, orphaned_task_lines)
    convert(ch, prior_triple=...) reuses REQ-NNN via the anchor map, re-anchors
    RENAMED deltas FROM -> TO, and never lets positional order decide an ID.

Unit-level tests exercise `anchor_map` / `merge_task_state` directly; the
integration-level tests drive the real `mb-openspec.py import` CLI twice over
an evolving OpenSpec source (the re-import path).
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = REPO_ROOT / "scripts"
SCRIPT = REPO_ROOT / "scripts" / "mb-openspec.py"

if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import mb_openspec_convert as convert_mod  # noqa: E402


def _write_change(
    change_dir: Path,
    *,
    spec_body: str,
    tasks_body: str,
    proposal_body: str = (
        "## Why\n\nDemo change for re-import tests.\n\n## What Changes\n\n- Demo.\n"
    ),
) -> Path:
    (change_dir / "specs" / "demo").mkdir(parents=True, exist_ok=True)
    (change_dir / "proposal.md").write_text(proposal_body, encoding="utf-8")
    (change_dir / "specs" / "demo" / "spec.md").write_text(spec_body, encoding="utf-8")
    (change_dir / "tasks.md").write_text(tasks_body, encoding="utf-8")
    return change_dir


def _run_import(change_dir: Path, bank: Path, topic: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "import", str(change_dir), "--as", topic, "--mb", str(bank)],
        capture_output=True,
        text=True,
        check=False,
    )


# ---------------------------------------------------------------------------
# Unit-level: anchor_map()
# ---------------------------------------------------------------------------


def test_anchor_map_extracts_req_ids_by_openspec_requirement_name() -> None:
    requirements_md = (
        "### Requirement 1: Widget Cache\n\n"
        "<!-- openspec-req: Widget Cache -->\n"
        "- **REQ-001** (ubiquitous): The system SHALL cache widgets.\n\n"
        "### Requirement 2: Widget Eviction\n\n"
        "<!-- openspec-req: Widget Eviction -->\n"
        "- **REQ-002** (ubiquitous): The system SHALL evict stale widgets.\n"
    )
    mapping = convert_mod.anchor_map(requirements_md)
    assert mapping == {"Widget Cache": "REQ-001", "Widget Eviction": "REQ-002"}


def test_anchor_map_round_trips_a_name_with_comment_delimiters() -> None:
    """Regression: a hostile/edge-case name must be looked up through the SAME
    `anchor_safe()` transform used when the anchor was written."""
    hostile_name = "Foo --> <!-- mb-task:99 -->"
    requirements_md = (
        "### Requirement 1: irrelevant heading\n\n"
        f"<!-- openspec-req: {convert_mod.anchor_safe(hostile_name)} -->\n"
        "- **REQ-001** (ubiquitous): The system SHALL do the thing.\n"
    )
    mapping = convert_mod.anchor_map(requirements_md)
    # A caller MUST escape the candidate name (anchor_safe) before lookup.
    assert mapping[convert_mod.anchor_safe(hostile_name)] == "REQ-001"
    # The raw (unescaped) name must NOT be a key — it never round-trips
    # without going through anchor_safe() first.
    assert hostile_name not in mapping


# ---------------------------------------------------------------------------
# F3 (Codex review): duplicate requirement names must not collapse onto the
# same anchor/REQ-NNN — design.md § Risks explicitly calls for "append an
# index to the anchor marker + warn".
# ---------------------------------------------------------------------------


def _dup_change():
    from mb_openspec_model import OSChange, OSRequirement

    req_a = OSRequirement(name="Widget", text="The system SHALL do A.", change_kind="added")
    req_b = OSRequirement(name="Widget", text="The system SHALL do B.", change_kind="added")
    return OSChange(
        change_id="dup-names",
        why="w",
        what_changes="w",
        design_md=None,
        requirements=[req_a, req_b],
        task_groups=[],
        source_hash="deadbeef",
    )


def test_convert_duplicate_requirement_names_get_distinct_disambiguated_anchors(capsys) -> None:
    ch = _dup_change()
    requirements_md, _design_md, _tasks_md = convert_mod.convert(ch)

    anchor_lines = [
        line for line in requirements_md.splitlines() if line.startswith("<!-- openspec-req:")
    ]
    assert len(anchor_lines) == 2
    # Two distinct anchor names -- never the same key twice.
    assert anchor_lines[0] != anchor_lines[1]
    assert anchor_lines[0] == "<!-- openspec-req: Widget -->"
    assert anchor_lines[1] == "<!-- openspec-req: Widget#2 -->"

    captured = capsys.readouterr()
    assert "duplicate" in captured.err.lower()


def test_convert_duplicate_requirement_names_preserve_distinct_req_ids_on_reimport() -> None:
    """The bug: `_prior_requirement_index` keyed by escaped name alone
    collapses two "Widget" anchors into one dict entry (last-wins) -- so on
    re-import BOTH duplicates resolve to the SAME REQ-NNN, silently losing
    the first requirement's identity."""
    ch = _dup_change()
    first_requirements_md, _d, _t = convert_mod.convert(ch)

    # Sanity: the fresh import assigned two distinct IDs.
    assert "**REQ-001**" in first_requirements_md
    assert "**REQ-002**" in first_requirements_md

    second_requirements_md, _d2, _t2 = convert_mod.convert(
        ch, prior_triple=(first_requirements_md, "", "")
    )

    # Re-import over an UNCHANGED source must reuse both prior IDs distinctly
    # -- not collapse both requirements onto whichever ID the (buggy)
    # last-wins anchor lookup happened to keep.
    assert "**REQ-001**" in second_requirements_md
    assert "**REQ-002**" in second_requirements_md
    # Exactly one bullet per ID -- no duplication/collapse.
    assert second_requirements_md.count("**REQ-001**") == 1
    assert second_requirements_md.count("**REQ-002**") == 1


def _triple_collision_change():
    """Two requirements literally named ``Widget`` (a duplicate pair) PLUS a
    third, distinct requirement literally named ``Widget#2`` -- the exact
    collision R2 (Codex round-2) calls out: the second ``Widget``'s naive
    disambiguated candidate (``Widget#2``) is ALSO another requirement's own
    real name."""
    from mb_openspec_model import OSChange, OSRequirement

    req_a = OSRequirement(name="Widget", text="The system SHALL do A.", change_kind="added")
    req_b = OSRequirement(name="Widget", text="The system SHALL do B.", change_kind="added")
    req_c = OSRequirement(name="Widget#2", text="The system SHALL do C.", change_kind="added")
    return OSChange(
        change_id="triple-collision",
        why="w",
        what_changes="w",
        design_md=None,
        requirements=[req_a, req_b, req_c],
        task_groups=[],
        source_hash="deadbeef",
    )


def test_convert_disambiguated_anchor_never_collides_with_a_literal_same_name(
    capsys,
) -> None:
    """R2 (Codex round-2 residual on F3): the naive ``name#2`` disambiguation
    candidate must never collapse onto a THIRD, unrelated requirement that
    happens to be literally named ``Widget#2`` -- all three must end up with
    distinct anchors and distinct REQ-NNN identities, both on a fresh import
    and preserved across a re-import over the identical (unchanged) source.
    """
    ch = _triple_collision_change()
    requirements_md, _design_md, _tasks_md = convert_mod.convert(ch)

    anchor_lines = [
        line for line in requirements_md.splitlines() if line.startswith("<!-- openspec-req:")
    ]
    assert len(anchor_lines) == 3
    assert len(set(anchor_lines)) == 3, f"two anchors collided: {anchor_lines}"

    assert "**REQ-001**" in requirements_md
    assert "**REQ-002**" in requirements_md
    assert "**REQ-003**" in requirements_md
    assert requirements_md.count("**REQ-001**") == 1
    assert requirements_md.count("**REQ-002**") == 1
    assert requirements_md.count("**REQ-003**") == 1

    # Re-import over the identical (unchanged) source must preserve all
    # three IDs distinctly -- not collapse any two onto the same REQ-NNN via
    # a colliding anchor key in `_prior_requirement_index`/`anchor_map`.
    second_requirements_md, _d2, _t2 = convert_mod.convert(
        ch, prior_triple=(requirements_md, "", "")
    )
    assert second_requirements_md.count("**REQ-001**") == 1
    assert second_requirements_md.count("**REQ-002**") == 1
    assert second_requirements_md.count("**REQ-003**") == 1

    second_anchor_lines = [
        line
        for line in second_requirements_md.splitlines()
        if line.startswith("<!-- openspec-req:")
    ]
    assert len(second_anchor_lines) == 3
    assert len(set(second_anchor_lines)) == 3, f"two anchors collided: {second_anchor_lines}"


# ---------------------------------------------------------------------------
# Unit-level: merge_task_state()
# ---------------------------------------------------------------------------


def test_merge_task_state_preserves_checked_state_by_normalized_task_text() -> None:
    prior_tasks_md = (
        "<!-- mb-task:1 -->\n## Task 1: Build\n\n**Covers:** N/A\n**Role:** backend\n\n"
        "- [x] Implement in-memory cache\n"
        "- [ ] Add cache invalidation\n"
    )
    new_tasks_md = (
        "<!-- mb-task:1 -->\n## Task 1: Build\n\n**Covers:** N/A\n**Role:** backend\n\n"
        "- [ ] Implement   in-memory  cache\n"  # extra whitespace, must still match
        "- [ ] Add cache invalidation\n"
    )
    merged, orphans = convert_mod.merge_task_state(new_tasks_md, prior_tasks_md)
    assert "- [x] Implement   in-memory  cache" in merged
    assert "- [ ] Add cache invalidation" in merged
    assert orphans == []


def test_merge_task_state_new_task_arrives_unchecked_even_if_source_marks_it_done() -> None:
    prior_tasks_md = (
        "<!-- mb-task:1 -->\n## Task 1: Build\n\n**Covers:** N/A\n**Role:** backend\n\n"
        "- [x] Implement in-memory cache\n"
    )
    new_tasks_md = (
        "<!-- mb-task:1 -->\n## Task 1: Build\n\n**Covers:** N/A\n**Role:** backend\n\n"
        "- [x] Implement in-memory cache\n"
        "- [x] Add cache invalidation\n"  # brand-new task text, must arrive unchecked (D-05)
    )
    merged, orphans = convert_mod.merge_task_state(new_tasks_md, prior_tasks_md)
    assert "- [x] Implement in-memory cache" in merged
    assert "- [ ] Add cache invalidation" in merged
    assert orphans == []


def test_merge_task_state_removed_task_is_returned_as_an_orphan_never_dropped() -> None:
    prior_tasks_md = (
        "<!-- mb-task:1 -->\n## Task 1: Build\n\n**Covers:** N/A\n**Role:** backend\n\n"
        "- [x] Implement in-memory cache\n"
        "- [ ] Add cache invalidation\n"
    )
    new_tasks_md = (
        "<!-- mb-task:1 -->\n## Task 1: Build\n\n**Covers:** N/A\n**Role:** backend\n\n"
        "- [x] Implement in-memory cache\n"
    )
    merged, orphans = convert_mod.merge_task_state(new_tasks_md, prior_tasks_md)
    assert "Add cache invalidation" not in merged
    assert len(orphans) == 1
    assert "Add cache invalidation" in orphans[0]
    assert orphans[0].startswith("- [ ]")


# ---------------------------------------------------------------------------
# Unit-level: convert() with prior_triple — direct ID/anchor reuse, no CLI
# ---------------------------------------------------------------------------


def test_convert_reuses_req_id_via_prior_triple_when_requirement_text_changes() -> None:
    from mb_openspec_model import OSChange, OSRequirement, OSScenario

    def _change(text: str) -> OSChange:
        return OSChange(
            change_id="widget-cache",
            why="why",
            what_changes="what",
            design_md=None,
            requirements=[
                OSRequirement(
                    name="Widget Cache",
                    text=text,
                    change_kind="added",
                    scenarios=[OSScenario(name="Cache hit", steps=[("WHEN", "x"), ("THEN", "y")])],
                )
            ],
            task_groups=[],
            source_hash="hash1",
        )

    first_requirements_md, _design_md, _tasks_md = convert_mod.convert(_change("Original text."))
    assert "**REQ-001**" in first_requirements_md

    second_requirements_md, _design_md2, _tasks_md2 = convert_mod.convert(
        _change("Edited text with a TTL."),
        prior_triple=(first_requirements_md, "", ""),
    )
    assert "**REQ-001**" in second_requirements_md  # same anchor -> same ID, never renumbered
    assert "Edited text with a TTL." in second_requirements_md
    assert "<!-- openspec-req: Widget Cache -->" in second_requirements_md


def test_convert_allocates_a_fresh_id_for_a_genuinely_new_name_on_reimport() -> None:
    from mb_openspec_model import OSChange, OSRequirement, OSScenario

    def _req(name: str, text: str) -> OSRequirement:
        return OSRequirement(
            name=name,
            text=text,
            change_kind="added",
            scenarios=[OSScenario(name="s", steps=[("WHEN", "x"), ("THEN", "y")])],
        )

    ch1 = OSChange(
        change_id="c",
        why="w",
        what_changes="w",
        design_md=None,
        requirements=[_req("Widget Cache", "text one")],
        task_groups=[],
        source_hash="h1",
    )
    prior_requirements_md, _d, _t = convert_mod.convert(ch1)
    assert "**REQ-001**" in prior_requirements_md

    ch2 = OSChange(
        change_id="c",
        why="w",
        what_changes="w",
        design_md=None,
        requirements=[_req("Widget Cache", "text one"), _req("Widget Metrics", "text two")],
        task_groups=[],
        source_hash="h2",
    )
    requirements_md, _d2, _t2 = convert_mod.convert(
        ch2, prior_triple=(prior_requirements_md, "", "")
    )
    # Existing name keeps REQ-001; the brand-new name gets the NEXT id, not a
    # position-derived one.
    assert requirements_md.index("Widget Cache") < requirements_md.index("Widget Metrics")
    assert "<!-- openspec-req: Widget Cache -->\n- **REQ-001**" in requirements_md
    assert "<!-- openspec-req: Widget Metrics -->\n- **REQ-002**" in requirements_md


# ---------------------------------------------------------------------------
# Integration-level: full `import` CLI re-run over an edited/evolved source
# ---------------------------------------------------------------------------

_SPEC_V1 = (
    "## ADDED Requirements\n\n"
    "### Requirement: Widget Cache\n"
    "The system SHALL cache widget definitions in memory.\n\n"
    "#### Scenario: Cache hit\n"
    "- **WHEN** a widget is requested twice\n"
    "- **THEN** the second lookup is served from memory\n"
)
_TASKS_V1 = "## 1. Build\n\n- [ ] 1.1 Implement in-memory cache\n- [ ] 1.2 Add cache invalidation\n"


def test_reimport_preserves_checked_task_and_req_id_after_editing_requirement_text(
    tmp_path: Path,
) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    change_dir = tmp_path / "changes" / "add-widget-cache"
    _write_change(change_dir, spec_body=_SPEC_V1, tasks_body=_TASKS_V1)

    proc = _run_import(change_dir, bank, "widget-cache")
    assert proc.returncode == 0, proc.stderr

    spec_dir = bank / "specs" / "widget-cache"
    requirements_before = (spec_dir / "requirements.md").read_text(encoding="utf-8")
    assert "<!-- openspec-req: Widget Cache -->" in requirements_before
    assert "**REQ-001**" in requirements_before

    # Simulate `/mb work` checking off the first task.
    tasks_path = spec_dir / "tasks.md"
    tasks_before = tasks_path.read_text(encoding="utf-8")
    tasks_checked = tasks_before.replace(
        "- [ ] 1.1 Implement in-memory cache", "- [x] 1.1 Implement in-memory cache"
    )
    assert tasks_checked != tasks_before
    tasks_path.write_text(tasks_checked, encoding="utf-8")

    # Edit the SOURCE requirement text (name unchanged) and re-import.
    spec_v2 = _SPEC_V1.replace(
        "The system SHALL cache widget definitions in memory.",
        "The system SHALL cache widget definitions in memory with a 60s TTL.",
    )
    (change_dir / "specs" / "demo" / "spec.md").write_text(spec_v2, encoding="utf-8")

    proc2 = _run_import(change_dir, bank, "widget-cache")
    assert proc2.returncode == 0, proc2.stderr

    requirements_after = (spec_dir / "requirements.md").read_text(encoding="utf-8")
    assert "**REQ-001**" in requirements_after  # same anchor, same ID (REQ-016)
    assert "60s TTL" in requirements_after  # text refreshed from source
    assert "<!-- openspec-req: Widget Cache -->" in requirements_after

    tasks_after = tasks_path.read_text(encoding="utf-8")
    assert "- [x] 1.1 Implement in-memory cache" in tasks_after  # check-state preserved


def test_reimport_task_removed_from_source_lands_in_backlog(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    change_dir = tmp_path / "changes" / "add-widget-cache"
    _write_change(change_dir, spec_body=_SPEC_V1, tasks_body=_TASKS_V1)

    proc = _run_import(change_dir, bank, "widget-cache")
    assert proc.returncode == 0, proc.stderr

    tasks_v2 = "## 1. Build\n\n- [ ] 1.1 Implement in-memory cache\n"  # 1.2 removed from source
    (change_dir / "tasks.md").write_text(tasks_v2, encoding="utf-8")

    proc2 = _run_import(change_dir, bank, "widget-cache")
    assert proc2.returncode == 0, proc2.stderr

    tasks_after = (bank / "specs" / "widget-cache" / "tasks.md").read_text(encoding="utf-8")
    assert "Add cache invalidation" not in tasks_after  # not silently kept in tasks.md

    backlog = (bank / "backlog.md").read_text(encoding="utf-8")
    assert "Add cache invalidation" in backlog  # ...but never silently dropped (REQ-017)
    assert "widget-cache" in backlog


_SPEC_RENAME_V1 = (
    "## ADDED Requirements\n\n"
    "### Requirement: Change Owner\n"
    "The system SHALL record the user who authored a change.\n\n"
    "#### Scenario: Owner recorded\n"
    "- **WHEN** a change is created\n"
    "- **THEN** the system SHALL record its owner\n"
)
_SPEC_RENAME_V2 = (
    "## RENAMED Requirements\n"
    "- FROM: `### Requirement: Change Owner`\n"
    "- TO: `### Requirement: Change Author`\n"
)
_TASKS_RENAME = "## 1. Setup\n\n- [ ] 1.1 Track the author field\n"


def test_reimport_renamed_delta_moves_anchor_keeps_req_id_and_task_state(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    change_dir = tmp_path / "changes" / "rename-owner"
    _write_change(change_dir, spec_body=_SPEC_RENAME_V1, tasks_body=_TASKS_RENAME)

    proc = _run_import(change_dir, bank, "rename-owner")
    assert proc.returncode == 0, proc.stderr

    spec_dir = bank / "specs" / "rename-owner"
    requirements_v1 = (spec_dir / "requirements.md").read_text(encoding="utf-8")
    assert "<!-- openspec-req: Change Owner -->" in requirements_v1
    assert "**REQ-001**" in requirements_v1

    # Simulate /mb work progress on the one task.
    tasks_path = spec_dir / "tasks.md"
    tasks_v1 = tasks_path.read_text(encoding="utf-8")
    tasks_path.write_text(
        tasks_v1.replace("- [ ] 1.1 Track the author field", "- [x] 1.1 Track the author field"),
        encoding="utf-8",
    )

    (change_dir / "specs" / "demo" / "spec.md").write_text(_SPEC_RENAME_V2, encoding="utf-8")

    proc2 = _run_import(change_dir, bank, "rename-owner")
    assert proc2.returncode == 0, proc2.stderr

    requirements_v2 = (spec_dir / "requirements.md").read_text(encoding="utf-8")
    assert "<!-- openspec-req: Change Author -->" in requirements_v2  # anchor moved (REQ-018)
    assert "<!-- openspec-req: Change Owner -->" not in requirements_v2
    assert "**REQ-001**" in requirements_v2  # ID preserved across the rename

    tasks_v2 = tasks_path.read_text(encoding="utf-8")
    assert "- [x] 1.1 Track the author field" in tasks_v2  # galka preserved
