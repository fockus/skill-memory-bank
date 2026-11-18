"""OpenSpec ``export <topic> --new`` (master-completion Stage 9, AGR-105 Q7 A).

A bank-authored spec becomes a new ``openspec/changes/<id>/`` that the
importer reads back to the same REQ bullets and task items, and the topic is
linked so a later ``sync``/``export`` finds nothing to do. Dry-run unless
``--write``; refuses an existing change id or a missing ``openspec/``.
"""

from __future__ import annotations

import importlib.util
import re
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-openspec.py"
if str(REPO_ROOT / "scripts") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "scripts"))
GOLDEN = REPO_ROOT / "tests" / "pytest" / "fixtures" / "openspec" / "golden" / "export-new-gadgets"


def _cli(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args], capture_output=True, text=True, check=False
    )


def _snapshot(root: Path) -> dict[str, tuple[bytes, int]]:
    return {
        p.relative_to(root).as_posix(): (p.read_bytes(), p.stat().st_mtime_ns)
        for p in root.rglob("*")
        if p.is_file()
    }


_NEW_REQS = """# Requirements: gadgets

## Functional Requirements (EARS)

### Requirement 1: Gadget Store

- **REQ-001** (ubiquitous): The system SHALL store gadgets.
- **REQ-002** (event-driven): When a gadget is deleted, the system SHALL archive it.

### Requirement 2: Gadget Search

- **REQ-003** (ubiquitous): The system SHALL search gadgets by name.

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: Store and find
**Covers:** REQ-001, REQ-003

- GIVEN an empty store
- WHEN a gadget is stored
- THEN a search by its name finds it
<!-- /mb-scenario:1 -->
"""
_NEW_DESIGN = "# Design: gadgets\n\n## Why\n\nGadgets get lost.\n\n## What Changes\n\n- Store.\n"
_NEW_TASKS = """# Tasks: gadgets

<!-- mb-task:1 -->
## Task 1: Store

**Covers:** REQ-001, REQ-002
**Role:** backend

**What to do:**
- Add the store module.

**DoD:**
- [x] store persists gadgets
- [ ] archive on delete
"""


@pytest.fixture
def authored(tmp_path: Path) -> dict[str, Path]:
    bank = tmp_path / ".memory-bank"
    spec_dir = bank / "specs" / "gadgets"
    spec_dir.mkdir(parents=True)
    (tmp_path / "openspec" / "changes").mkdir(parents=True)
    (spec_dir / "requirements.md").write_text(_NEW_REQS, encoding="utf-8")
    (spec_dir / "design.md").write_text(_NEW_DESIGN, encoding="utf-8")
    (spec_dir / "tasks.md").write_text(_NEW_TASKS, encoding="utf-8")
    return {"bank": bank, "root": tmp_path, "change": tmp_path / "openspec" / "changes" / "gadgets"}


def test_export_new_dry_run_writes_nothing(authored):
    bank_before = _snapshot(authored["bank"])

    proc = _cli("export", "gadgets", "--new", "--mb", str(authored["bank"]))

    assert proc.returncode == 0, proc.stderr
    assert "+### Requirement: Gadget Store 1" in proc.stdout
    assert not authored["change"].exists()
    assert _snapshot(authored["bank"]) == bank_before


def test_export_new_creates_a_change_the_importer_reads_back_to_the_same_units(authored):
    bank = authored["bank"]
    proc = _cli("export", "gadgets", "--new", "--write", "--mb", str(bank))
    assert proc.returncode == 0, proc.stderr

    spec = (authored["change"] / "specs" / "gadgets" / "spec.md").read_text(encoding="utf-8")
    assert "### Requirement: Gadget Store 2\nWhen a gadget is deleted" in spec
    assert spec.count("#### Scenario: Store and find") == 2
    assert "REQ-" not in spec
    assert "up to date" in _cli("sync", "gadgets", "--mb", str(bank)).stdout
    assert "nothing to export" in _cli("export", "gadgets", "--mb", str(bank)).stdout

    ours = (bank / "specs" / "gadgets" / "requirements.md").read_text(encoding="utf-8")
    for name in ("Gadget Store 1", "Gadget Store 2", "Gadget Search"):
        assert f"<!-- openspec: cap=gadgets; kind=added -->\n<!-- openspec-req: {name} -->" in ours

    other = authored["root"] / "other-bank"
    other.mkdir()
    back = _cli("import", str(authored["change"]), "--as", "gadgets", "--mb", str(other))
    assert back.returncode == 0, back.stderr
    for name in ("requirements.md", "design.md", "tasks.md"):
        got = (other / "specs" / "gadgets" / name).read_text(encoding="utf-8")
        got = re.sub(r"\A---\n.*?\n---\n\n", "", got, flags=re.DOTALL)
        assert got == (GOLDEN / name).read_text(encoding="utf-8"), name


def test_export_new_refuses_an_existing_change_id(authored):
    authored["change"].mkdir()

    proc = _cli("export", "gadgets", "--new", "--write", "--mb", str(authored["bank"]))

    assert proc.returncode == 1
    assert "exists" in proc.stderr


def test_export_new_refuses_without_an_openspec_dir(tmp_path: Path):
    bank = tmp_path / ".memory-bank"
    (bank / "specs" / "gadgets").mkdir(parents=True)
    (bank / "specs" / "gadgets" / "requirements.md").write_text(_NEW_REQS, encoding="utf-8")
    (bank / "specs" / "gadgets" / "tasks.md").write_text(_NEW_TASKS, encoding="utf-8")

    proc = _cli("export", "gadgets", "--new", "--write", "--mb", str(bank))

    assert proc.returncode == 1
    assert "openspec" in proc.stderr


def test_export_new_never_names_an_ungrouped_requirement_by_its_req_id(authored):
    reqs = authored["bank"] / "specs" / "gadgets" / "requirements.md"
    reqs.write_text(
        "# Requirements: gadgets\n\n- **REQ-007** (ubiquitous): The system SHALL log gadgets.\n",
        encoding="utf-8",
    )

    proc = _cli("export", "gadgets", "--new", "--write", "--mb", str(authored["bank"]))

    assert proc.returncode == 0, proc.stderr
    for path in authored["change"].rglob("*"):
        if path.is_file():
            assert "REQ-" not in path.read_text(encoding="utf-8"), path


def _load_cli():
    spec = importlib.util.spec_from_file_location("mb_openspec_cli_new", SCRIPT)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _new_write(mod, bank: Path) -> int:
    return mod.main(["mb-openspec.py", "export", "gadgets", "--new", "--write", "--mb", str(bank)])


def test_export_new_crash_while_creating_the_change_leaves_no_partial_change(authored, monkeypatch):
    mod = _load_cli()
    orig = mod.atomic_write
    bank_before = _snapshot(authored["bank"])

    def crash_on_tasks(path, content):
        if Path(path).name == "tasks.md" and "openspec" in Path(path).parts:
            raise OSError("simulated crash")
        orig(path, content)

    monkeypatch.setattr(mod, "atomic_write", crash_on_tasks)
    with pytest.raises(OSError):
        _new_write(mod, authored["bank"])

    assert not authored["change"].exists()
    assert [p.name for p in authored["change"].parent.iterdir()] == []
    assert _snapshot(authored["bank"]) == bank_before
    monkeypatch.setattr(mod, "atomic_write", orig)
    assert _new_write(mod, authored["bank"]) == 0


def test_export_new_rerun_completes_bank_linking_after_a_crash(authored, monkeypatch):
    mod = _load_cli()
    orig = mod.atomic_write
    bank = authored["bank"]

    def crash_on_link(path, content):
        if Path(path).name == "requirements.md" and ".memory-bank" in Path(path).parts:
            raise OSError("simulated crash")
        orig(path, content)

    monkeypatch.setattr(mod, "atomic_write", crash_on_link)
    with pytest.raises(OSError):
        _new_write(mod, bank)
    assert authored["change"].is_dir()

    monkeypatch.setattr(mod, "atomic_write", orig)
    assert _new_write(mod, bank) == 0
    assert "openspec_source:" in (bank / "specs" / "gadgets" / "requirements.md").read_text()
    assert "up to date" in _cli("sync", "gadgets", "--mb", str(bank)).stdout
    assert "nothing to export" in _cli("export", "gadgets", "--mb", str(bank)).stdout


def test_export_after_new_keeps_the_scenarios_of_an_edited_requirement(authored):
    bank = authored["bank"]
    assert _cli("export", "gadgets", "--new", "--write", "--mb", str(bank)).returncode == 0
    reqs = bank / "specs" / "gadgets" / "requirements.md"
    reqs.write_text(
        reqs.read_text(encoding="utf-8").replace(
            "SHALL store gadgets.", "SHALL store gadgets safely."
        ),
        encoding="utf-8",
    )

    proc = _cli("export", "gadgets", "--write", "--mb", str(bank))

    assert proc.returncode == 0, proc.stderr
    spec = (authored["change"] / "specs" / "gadgets" / "spec.md").read_text(encoding="utf-8")
    block = spec.split("### Requirement: Gadget Store 1\n", 1)[1].split("### Requirement:", 1)[0]
    assert block.startswith("The system SHALL store gadgets safely.")
    assert "#### Scenario: Store and find" in block
    assert spec.count("#### Scenario: Store and find") == 2
    assert "nothing to export" in _cli("export", "gadgets", "--mb", str(bank)).stdout


def test_sync_after_new_takes_an_openspec_edit_without_duplicating_shared_scenarios(authored):
    bank = authored["bank"]
    assert _cli("export", "gadgets", "--new", "--write", "--mb", str(bank)).returncode == 0
    spec_path = authored["change"] / "specs" / "gadgets" / "spec.md"
    spec_path.write_text(
        spec_path.read_text(encoding="utf-8").replace(
            "SHALL store gadgets.", "SHALL store gadgets fast."
        ),
        encoding="utf-8",
    )

    proc = _cli("sync", "gadgets", "--mb", str(bank))

    assert proc.returncode == 0, proc.stderr
    text = (bank / "specs" / "gadgets" / "requirements.md").read_text(encoding="utf-8")
    assert "SHALL store gadgets fast." in text
    assert text.count("### Scenario: Store and find") == 2  # one inline, one shared (REQ-003)
    assert "**Covers:** REQ-003\n" in text
    assert "nothing to export" in _cli("export", "gadgets", "--mb", str(bank)).stdout


def test_export_new_never_replaces_a_change_dir_created_concurrently(authored, monkeypatch):
    import mb_openspec_export_new as new_mod

    real = new_mod.tempfile.mkdtemp

    def mkdtemp_then_race(*args, **kwargs):
        made = real(*args, **kwargs)
        authored["change"].mkdir()  # another process wins the name after the exists() check
        return made

    monkeypatch.setattr(new_mod.tempfile, "mkdtemp", mkdtemp_then_race)
    mod = _load_cli()

    assert _new_write(mod, authored["bank"]) == 1  # refused: the name is taken
    assert list(authored["change"].iterdir()) == []
