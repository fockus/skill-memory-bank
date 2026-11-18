"""OpenSpec export (master-completion Stage 9, AGR-105 Q3/Q4).

``export <topic>`` splices only the bank units that changed since the last
sync back into ``openspec/changes/<id>/``: unchanged units keep OpenSpec's
bytes, REQ-IDs never reach OpenSpec, the default is a dry-run diff, ``--write``
applies atomically, an OpenSpec change that moved since the last sync is
refused (no ``--force``), deletions need ``--allow-delete``, and nothing is
written outside the change directory. ``export --new`` is covered in
``test_openspec_export_new.py``.
"""

from __future__ import annotations

import importlib.util
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = REPO_ROOT / "scripts"
SCRIPT = SCRIPTS_DIR / "mb-openspec.py"

if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import mb_openspec_export as export_mod  # noqa: E402

_BLOCK_CACHE = (
    "### Requirement: Widget Cache\n"
    "The system SHALL cache widget definitions in memory.\n\n"
    "#### Scenario: Cache hit\n"
    "- **WHEN** a widget is requested twice\n"
    "- **THEN** the second lookup is served from memory\n"
)
_BLOCK_EXPIRY = (
    "### Requirement: Widget Expiry\n"
    "The system SHALL expire cached widgets after one hour.\n\n"
    "#### Scenario: Expiry\n"
    "- **WHEN** an hour passes\n"
    "- **THEN** the widget is evicted\n"
)
_SPEC = "## ADDED Requirements\n\n" + _BLOCK_CACHE + "\n" + _BLOCK_EXPIRY
_TASKS = "## 1. Build\n\n- [ ] 1.1 Implement in-memory cache\n- [ ] 1.2 Add cache invalidation\n"
_PROPOSAL = (
    "## Why\n\nWidgets are slow.\n\n## What Changes\n\n- Cache them.\n\n## Impact\n\nNone.\n"
)


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


def _edit(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    assert old in text, old
    path.write_text(text.replace(old, new), encoding="utf-8")


@pytest.fixture
def env(tmp_path: Path) -> dict[str, Path]:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    change = tmp_path / "openspec" / "changes" / "add-widget-cache"
    (change / "specs" / "widgets").mkdir(parents=True)
    (change / "proposal.md").write_text(_PROPOSAL, encoding="utf-8")
    (change / "design.md").write_text("## Context\n\nOne process.\n", encoding="utf-8")
    (change / "specs" / "widgets" / "spec.md").write_text(_SPEC, encoding="utf-8")
    (change / "tasks.md").write_text(_TASKS, encoding="utf-8")
    proc = _cli("import", str(change), "--as", "widgets", "--mb", str(bank))
    assert proc.returncode == 0, proc.stderr
    spec_dir = bank / "specs" / "widgets"
    return {
        "bank": bank,
        "change": change,
        "spec": change / "specs" / "widgets" / "spec.md",
        "req": spec_dir / "requirements.md",
        "design": spec_dir / "design.md",
        "tasks": spec_dir / "tasks.md",
    }


def _export(env: dict[str, Path], *flags: str) -> subprocess.CompletedProcess[str]:
    return _cli("export", "widgets", "--mb", str(env["bank"]), *flags)


def test_export_after_import_without_edits_keeps_the_change_byte_identical(env):
    before = _snapshot(env["change"])

    proc = _export(env, "--write")

    assert proc.returncode == 0, proc.stderr
    assert "nothing to export" in proc.stdout
    assert _snapshot(env["change"]) == before


def test_export_round_trip_of_the_golden_fixture_is_byte_identical(tmp_path: Path):
    fixture = REPO_ROOT / "tests/pytest/fixtures/openspec/changes/add-metadata-tracking"
    change = tmp_path / "openspec" / "changes" / fixture.name
    shutil.copytree(fixture, change)
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    assert _cli("import", str(change), "--as", "meta", "--mb", str(bank)).returncode == 0
    before = _snapshot(change)

    proc = _cli("export", "meta", "--write", "--mb", str(bank))

    assert proc.returncode == 0, proc.stderr
    assert _snapshot(change) == before


def test_export_dry_run_prints_a_diff_and_writes_nothing(env):
    _edit(env["req"], "in memory.", "in memory, per tenant.")
    os_before, bank_before = _snapshot(env["change"]), _snapshot(env["bank"])

    proc = _export(env)

    assert proc.returncode == 0, proc.stderr
    assert "-The system SHALL cache widget definitions in memory." in proc.stdout
    assert "+The system SHALL cache widget definitions in memory, per tenant." in proc.stdout
    assert "--write" in proc.stdout
    assert _snapshot(env["change"]) == os_before
    assert _snapshot(env["bank"]) == bank_before


def test_export_write_splices_only_changed_units_without_req_ids(env):
    _edit(env["req"], "in memory.", "in memory, per tenant.")
    _edit(env["tasks"], "- [ ] 1.1 Implement", "- [x] 1.1 Implement")
    _edit(env["design"], "Widgets are slow.", "Widgets are slow under load.")

    proc = _export(env, "--write")

    assert proc.returncode == 0, proc.stderr
    expected_spec = _SPEC.replace("in memory.", "in memory, per tenant.")
    assert env["spec"].read_text(encoding="utf-8") == expected_spec
    assert env["change"].joinpath("tasks.md").read_text(encoding="utf-8") == _TASKS.replace(
        "- [ ] 1.1", "- [x] 1.1"
    )
    assert env["change"].joinpath("proposal.md").read_text(encoding="utf-8") == _PROPOSAL.replace(
        "Widgets are slow.", "Widgets are slow under load."
    )
    for path in env["change"].rglob("*.md"):
        assert "REQ-" not in path.read_text(encoding="utf-8"), path
    assert "up to date" in _cli("sync", "widgets", "--mb", str(env["bank"])).stdout
    assert "nothing to export" in _export(env).stdout


def test_export_refuses_when_openspec_moved_since_the_last_sync(env):
    _edit(env["req"], "in memory.", "in memory, per tenant.")
    _edit(env["spec"], "after one hour.", "after ten minutes.")
    os_before, bank_before = _snapshot(env["change"]), _snapshot(env["bank"])

    proc = _export(env, "--write")

    assert proc.returncode == 1
    assert "sync" in proc.stderr
    assert _snapshot(env["change"]) == os_before
    assert _snapshot(env["bank"]) == bank_before


def test_export_has_no_force_flag(env):
    assert _export(env, "--write", "--force").returncode == 2


def test_export_deletes_only_with_allow_delete(env):
    _edit(env["tasks"], "- [ ] 1.2 Add cache invalidation\n", "")
    os_tasks = env["change"] / "tasks.md"

    kept = _export(env, "--write")

    assert kept.returncode == 0, kept.stderr
    assert "--allow-delete" in kept.stderr
    assert "1.2 Add cache invalidation" in os_tasks.read_text(encoding="utf-8")

    deleted = _export(env, "--write", "--allow-delete")

    assert deleted.returncode == 0, deleted.stderr
    assert os_tasks.read_text(encoding="utf-8") == _TASKS.replace(
        "- [ ] 1.2 Add cache invalidation\n", ""
    )


def test_export_adds_a_bank_requirement_to_the_added_section(env):
    req = env["req"]
    req.write_text(
        req.read_text(encoding="utf-8") + "\n### Requirement 3: Widget Metrics\n\n"
        "<!-- openspec: cap=widgets; kind=added -->\n"
        "<!-- openspec-req: Widget Metrics -->\n"
        "- **REQ-003** (ubiquitous): The system SHALL count cache hits.\n",
        encoding="utf-8",
    )

    proc = _export(env, "--write")

    assert proc.returncode == 0, proc.stderr
    spec = env["spec"].read_text(encoding="utf-8")
    assert spec.startswith(_SPEC)
    assert spec.endswith("### Requirement: Widget Metrics\nThe system SHALL count cache hits.\n")
    assert "nothing to export" in _export(env).stdout


@pytest.mark.parametrize(
    "rel",
    [
        "../other-change/proposal.md",
        "../../specs/widgets/spec.md",
        ".openspec.yaml",
        "specs/../../x/spec.md",
        "specs/bad cap/spec.md",
        "notes.md",
    ],
)
def test_write_guard_refuses_paths_outside_the_allowed_change_files(env, rel):
    with pytest.raises(RuntimeError):
        export_mod.guard_target(env["change"], env["change"] / rel)


def test_write_guard_refuses_an_archived_or_misplaced_change_dir(tmp_path: Path):
    archived = tmp_path / "openspec" / "changes" / "archive" / "2026-01-01-x"
    living = tmp_path / "openspec" / "specs" / "widgets"
    for path in (archived, living):
        path.mkdir(parents=True)
        with pytest.raises(RuntimeError):
            export_mod.guard_change_dir(path)


def test_export_refuses_a_symlinked_target_file_and_writes_nothing(env, tmp_path: Path):
    outside = tmp_path / "outside.md"
    outside.write_text(_TASKS, encoding="utf-8")
    os_tasks = env["change"] / "tasks.md"
    os_tasks.unlink()
    os.symlink(outside, os_tasks)
    _edit(env["tasks"], "- [ ] 1.1 Implement", "- [x] 1.1 Implement")

    proc = _export(env, "--write")

    assert proc.returncode == 1
    assert outside.read_text(encoding="utf-8") == _TASKS


def test_write_guard_refuses_archive_anywhere_in_the_real_path(tmp_path: Path):
    nested = tmp_path / "archive" / "proj" / "openspec" / "changes" / "add-x"
    nested.mkdir(parents=True)
    link = tmp_path / "live"
    os.symlink(tmp_path / "archive" / "proj", link)
    for path in (nested, link / "openspec" / "changes" / "add-x"):
        with pytest.raises(RuntimeError, match="archive"):
            export_mod.guard_change_dir(path)


def _load_cli():
    spec = importlib.util.spec_from_file_location("mb_openspec_cli_export", SCRIPT)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _export_racing(env, monkeypatch, race) -> int:
    """Run ``export --write`` in-process; ``race`` edits a file after the diff is built."""
    mod = _load_cli()
    real = export_mod.print_diff

    def diff_then_race(*args, **kwargs):
        changed = real(*args, **kwargs)
        race()
        return changed

    monkeypatch.setattr(export_mod, "print_diff", diff_then_race)
    return mod.main(["mb-openspec.py", "export", "widgets", "--write", "--mb", str(env["bank"])])


def test_export_aborts_when_openspec_changes_after_the_check(env, monkeypatch):
    _edit(env["req"], "in memory.", "in memory, per tenant.")
    racing = _SPEC.replace("after one hour.", "after ten minutes.")

    rc = _export_racing(env, monkeypatch, lambda: env["spec"].write_text(racing, "utf-8"))

    assert rc == 1
    assert env["spec"].read_text(encoding="utf-8") == racing


def test_export_aborts_when_the_bank_changes_after_the_check(env, monkeypatch):
    _edit(env["req"], "in memory.", "in memory, per tenant.")
    os_before = _snapshot(env["change"])

    rc = _export_racing(env, monkeypatch, lambda: _edit(env["req"], "per tenant.", "per org."))

    assert rc == 1
    assert "per org." in env["req"].read_text(encoding="utf-8")
    assert {k: v[0] for k, v in _snapshot(env["change"]).items()} == {
        k: v[0] for k, v in os_before.items()
    }
