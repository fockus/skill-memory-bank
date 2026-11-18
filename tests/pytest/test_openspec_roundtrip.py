"""OpenSpec round-trip groundwork (master-completion Stage 8, AGR-105).

Import keeps what a later export needs: capability and delta kind in a meta
line before each anchor, RENAMED deltas emitted, task identity keyed on the
``N.M`` id, Covers/Role bank-side after the first import, and a committed
``specs/<topic>/openspec-sync.json`` sidecar with per-unit hashes of both
sides. ``sync`` adopts a baseline for imports that predate the sidecar.
"""

from __future__ import annotations

import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = REPO_ROOT / "scripts"
SCRIPT = SCRIPTS_DIR / "mb-openspec.py"
FIXTURE = (
    REPO_ROOT / "tests" / "pytest" / "fixtures" / "openspec" / "changes" / "add-metadata-tracking"
)

if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import mb_openspec_convert as convert_mod  # noqa: E402
import mb_openspec_parse as parse_mod  # noqa: E402

_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_META_LINE = re.compile(r"(?m)^<!-- openspec: [^\n]*-->\n")

_SPEC = (
    "## ADDED Requirements\n\n"
    "### Requirement: Widget Cache\n"
    "The system SHALL cache widget definitions in memory.\n\n"
    "#### Scenario: Cache hit\n"
    "- **WHEN** a widget is requested twice\n"
    "- **THEN** the second lookup is served from memory\n"
)
_TASKS = "## 1. Build\n\n- [ ] 1.1 Implement in-memory cache\n- [ ] 1.2 Add cache invalidation\n"


def _load_cli():
    spec = importlib.util.spec_from_file_location("mb_openspec_cli_roundtrip", SCRIPT)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _write_change(change_dir: Path, *, spec_body: str = _SPEC, tasks_body: str = _TASKS) -> Path:
    (change_dir / "specs" / "widgets").mkdir(parents=True, exist_ok=True)
    (change_dir / "proposal.md").write_text(
        "## Why\n\nWidgets are slow.\n\n## What Changes\n\n- Cache them.\n", encoding="utf-8"
    )
    (change_dir / "specs" / "widgets" / "spec.md").write_text(spec_body, encoding="utf-8")
    (change_dir / "tasks.md").write_text(tasks_body, encoding="utf-8")
    return change_dir


def _cli(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args], capture_output=True, text=True, check=False
    )


def _import(change_dir: Path, bank: Path, topic: str = "widgets") -> None:
    proc = _cli("import", str(change_dir), "--as", topic, "--mb", str(bank))
    assert proc.returncode == 0, proc.stderr


def _snapshot(root: Path) -> dict[str, bytes]:
    return {p.relative_to(root).as_posix(): p.read_bytes() for p in root.rglob("*") if p.is_file()}


def _make_pre_sidecar(spec_dir: Path) -> None:
    """Turn a fresh import into what the pre-Stage-8 code wrote: no meta lines, no sidecar."""
    for name in ("requirements.md", "design.md"):
        path = spec_dir / name
        path.write_text(_META_LINE.sub("", path.read_text(encoding="utf-8")), encoding="utf-8")
    (spec_dir / "openspec-sync.json").unlink()


@pytest.fixture
def setup_widgets(tmp_path: Path) -> tuple[Path, Path, Path]:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    change_dir = _write_change(tmp_path / "openspec" / "changes" / "add-widget-cache")
    _import(change_dir, bank)
    return bank, change_dir, bank / "specs" / "widgets"


# --- parse / convert ---------------------------------------------------------


def test_parse_requirement_carries_capability_from_its_spec_dir() -> None:
    ch = parse_mod.parse_change(FIXTURE)
    assert ch.requirements
    assert {r.capability for r in ch.requirements} == {"change-tracking"}


def test_convert_meta_line_with_cap_and_kind_precedes_each_anchor() -> None:
    requirements_md, _design, _tasks = convert_mod.convert(parse_mod.parse_change(FIXTURE))
    assert (
        "<!-- openspec: cap=change-tracking; kind=added -->\n"
        "<!-- openspec-req: Change Metadata -->\n- **REQ-001**"
    ) in requirements_md
    assert (
        "<!-- openspec: cap=change-tracking; kind=modified -->\n"
        "<!-- openspec-req: Change Status Field -->"
    ) in requirements_md


def test_convert_removed_scope_entry_carries_its_meta_line() -> None:
    _req, design_md, _tasks = convert_mod.convert(parse_mod.parse_change(FIXTURE))
    assert (
        "<!-- openspec: cap=change-tracking; kind=removed -->\n### Legacy Status Comment"
    ) in design_md


def test_convert_renamed_delta_is_imported_on_first_import() -> None:
    requirements_md, design_md, _tasks = convert_mod.convert(parse_mod.parse_change(FIXTURE))
    assert (
        "<!-- openspec: cap=change-tracking; kind=renamed; from=Change Owner -->\n"
        "<!-- openspec-req: Change Author -->\n- **REQ-004**"
    ) in requirements_md
    assert "Deferred renames" not in design_md


# --- tasks -------------------------------------------------------------------


def test_merge_task_state_keeps_state_by_task_id_when_text_is_reworded() -> None:
    head = "<!-- mb-task:1 -->\n## Task 1: Build\n\n**Covers:** N/A\n**Role:** backend\n\n"
    prior = head + "- [x] 1.1 Implement cache\n"
    new = head + "- [ ] 1.1 Implement the in-memory cache\n"
    merged, orphans = convert_mod.merge_task_state(new, prior)
    assert "- [x] 1.1 Implement the in-memory cache" in merged
    assert orphans == []


def test_reimport_keeps_hand_set_covers_and_role(setup_widgets) -> None:
    bank, change_dir, spec_dir = setup_widgets
    tasks_path = spec_dir / "tasks.md"
    edited = (
        tasks_path.read_text(encoding="utf-8")
        .replace("**Covers:** N/A", "**Covers:** REQ-001")
        .replace("**Role:** backend", "**Role:** qa")
    )
    tasks_path.write_text(edited, encoding="utf-8")
    _write_change(change_dir, tasks_body=_TASKS + "- [ ] 1.3 Document the cache\n")

    _import(change_dir, bank)

    tasks_after = tasks_path.read_text(encoding="utf-8")
    assert "**Covers:** REQ-001" in tasks_after
    assert "**Role:** qa" in tasks_after
    assert "1.3 Document the cache" in tasks_after


# --- sidecar -----------------------------------------------------------------


def test_import_writes_sidecar_with_per_unit_hashes_of_both_sides(setup_widgets) -> None:
    _bank, _change_dir, spec_dir = setup_widgets
    data = json.loads((spec_dir / "openspec-sync.json").read_text(encoding="utf-8"))
    units = data["units"]
    req = units["req:Widget Cache"]
    assert (req["cap"], req["kind"], req["name"]) == ("widgets", "added", "Widget Cache")
    task = units["task:1.1"]
    assert task["os_checked"] is False and task["mb_checked"] is False
    for key in ("req:Widget Cache", "task:1.1", "group:1", "proposal:why", "proposal:what-changes"):
        assert _HEX64.match(units[key]["os"]), key
        assert _HEX64.match(units[key]["mb"]), key
    fm_hash = re.search(r"openspec_hash: (\w+)", (spec_dir / "requirements.md").read_text())
    assert fm_hash and data["openspec_hash"] == fm_hash.group(1)


def test_import_sidecar_crash_never_finalizes_the_new_hash(tmp_path: Path, monkeypatch) -> None:
    mod = _load_cli()
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    change_dir = _write_change(tmp_path / "openspec" / "changes" / "add-widget-cache")
    orig = mod.atomic_write

    def crash_on_sidecar(path, content):
        if Path(path).name == "openspec-sync.json":
            raise RuntimeError("simulated crash writing the sidecar")
        return orig(path, content)

    monkeypatch.setattr(mod, "atomic_write", crash_on_sidecar)
    with pytest.raises(RuntimeError, match="simulated crash"):
        mod.run_import(change_dir=change_dir, mb_path=bank, topic="widgets")
    assert not (bank / "specs" / "widgets" / "requirements.md").exists()


# --- sync: adopt a baseline for pre-sidecar imports --------------------------


def test_sync_adopts_baseline_for_a_pre_sidecar_import(setup_widgets) -> None:
    bank, change_dir, spec_dir = setup_widgets
    fresh = _snapshot(spec_dir)
    _make_pre_sidecar(spec_dir)
    source_before = _snapshot(change_dir)

    proc = _cli("sync", "widgets", "--mb", str(bank))

    assert proc.returncode == 0, proc.stderr
    assert "baseline adopted" in proc.stdout
    assert _snapshot(spec_dir) == fresh  # meta lines back, sidecar written, nothing else
    assert _snapshot(change_dir) == source_before


def test_sync_adopt_keeps_a_bank_edit_when_the_source_did_not_move(setup_widgets) -> None:
    bank, _change_dir, spec_dir = setup_widgets
    _make_pre_sidecar(spec_dir)
    req_path = spec_dir / "requirements.md"
    req_path.write_text(
        req_path.read_text(encoding="utf-8").replace("in memory.", "in memory, per tenant."),
        encoding="utf-8",
    )

    proc = _cli("sync", "widgets", "--mb", str(bank))

    assert proc.returncode == 0, proc.stderr
    assert "per tenant" in req_path.read_text(encoding="utf-8")
    assert "req:Widget Cache" in proc.stdout  # reported as a bank edit (export candidate)
    data = json.loads((spec_dir / "openspec-sync.json").read_text(encoding="utf-8"))
    assert data["units"]["req:Widget Cache"]["mb"]


def test_sync_adopt_conflict_when_both_sides_changed_writes_nothing(setup_widgets) -> None:
    bank, change_dir, spec_dir = setup_widgets
    _make_pre_sidecar(spec_dir)
    req_path = spec_dir / "requirements.md"
    req_path.write_text(
        req_path.read_text(encoding="utf-8").replace("in memory.", "in memory, per tenant."),
        encoding="utf-8",
    )
    _write_change(change_dir, spec_body=_SPEC.replace("in memory.", "in Redis."))
    before = _snapshot(spec_dir)

    proc = _cli("sync", "widgets", "--mb", str(bank))

    assert proc.returncode == 1
    assert "conflict" in proc.stderr and "req:Widget Cache" in proc.stderr
    assert _snapshot(spec_dir) == before
    assert not (bank / "backlog.md").exists()


def test_sync_corrupt_sidecar_adopts_baseline_without_touching_bank_text(setup_widgets) -> None:
    bank, _change_dir, spec_dir = setup_widgets
    fresh = _snapshot(spec_dir)
    (spec_dir / "openspec-sync.json").write_text("{not json", encoding="utf-8")

    proc = _cli("sync", "widgets", "--mb", str(bank))

    assert proc.returncode == 0, proc.stderr
    assert _snapshot(spec_dir) == fresh


def test_spec_validate_accepts_a_spec_folder_with_the_sidecar(tmp_path: Path) -> None:
    spec_dir = tmp_path / ".memory-bank" / "specs" / "widgets"
    spec_dir.mkdir(parents=True)
    (spec_dir / "requirements.md").write_text(
        "# Requirements: widgets\n\n## Requirements (EARS)\n\n"
        "- **REQ-001** (ubiquitous): The system shall cache widgets.\n",
        encoding="utf-8",
    )
    (spec_dir / "design.md").write_text("# Design\n", encoding="utf-8")
    (spec_dir / "tasks.md").write_text(
        "# Tasks: widgets\n\n<!-- mb-task:1 -->\n## Task 1: cache\n\n"
        "**Covers:** REQ-001\n**Role:** backend\n\n"
        "**Testing (TDD):**\n- Unit test.\n\n**DoD:**\n- [ ] tests pass.\n",
        encoding="utf-8",
    )
    (spec_dir / "openspec-sync.json").write_text('{"format": 1, "units": {}}\n', encoding="utf-8")
    proc = subprocess.run(
        ["bash", str(SCRIPTS_DIR / "mb-spec-validate.sh"), str(spec_dir)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr


def test_sync_adopt_brings_in_a_rename_the_old_importer_deferred(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    _import(FIXTURE, bank, "meta")
    spec_dir = bank / "specs" / "meta"
    _make_pre_sidecar(spec_dir)
    req_path = spec_dir / "requirements.md"
    req_text = req_path.read_text(encoding="utf-8")
    req_path.write_text(req_text[: req_text.index("\n### Requirement 4:")] + "\n", "utf-8")

    proc = _cli("sync", "meta", "--mb", str(bank))

    assert proc.returncode == 0, proc.stderr
    assert "bank ahead" not in proc.stdout  # a deferred rename is not a bank edit
    assert "req:Change Author" in proc.stdout  # taken from OpenSpec by the adoption
    assert "<!-- openspec-req: Change Author -->" in req_path.read_text(encoding="utf-8")
    data = json.loads((spec_dir / "openspec-sync.json").read_text(encoding="utf-8"))
    assert _HEX64.match(data["units"]["req:Change Author"]["mb"])
