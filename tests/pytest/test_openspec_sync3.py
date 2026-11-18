"""Three-way per-unit OpenSpec sync (master-completion Stage 9, AGR-105 Q1).

``sync`` compares every unit with the ``openspec-sync.json`` baseline: only
OpenSpec moved -> the bank takes it; only the bank moved -> kept and reported
for ``export``; both moved to different text -> conflict, exit 1, nothing
written; ``--take openspec|bank`` resolves. Every bank write path (``sync`` and
a re-``import``) splices per unit, so bank-only content survives.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-openspec.py"

_SPEC = (
    "## ADDED Requirements\n\n"
    "### Requirement: Widget Cache\n"
    "The system SHALL cache widget definitions in memory.\n\n"
    "#### Scenario: Cache hit\n"
    "- **WHEN** a widget is requested twice\n"
    "- **THEN** the second lookup is served from memory\n\n"
    "### Requirement: Widget Expiry\n"
    "The system SHALL expire cached widgets after one hour.\n\n"
    "#### Scenario: Expiry\n"
    "- **WHEN** an hour passes\n"
    "- **THEN** the widget is evicted\n"
)
_TASKS = "## 1. Build\n\n- [ ] 1.1 Implement in-memory cache\n- [ ] 1.2 Add cache invalidation\n"
_BANK_SECTION = "## Implementation notes\n\nUse an LRU keyed by widget id.\n"
_TASK_PROSE = "Coordinate the rollout with the infra team."


def _write_change(change_dir: Path, *, spec: str = _SPEC, tasks: str = _TASKS) -> Path:
    (change_dir / "specs" / "widgets").mkdir(parents=True, exist_ok=True)
    (change_dir / "proposal.md").write_text(
        "## Why\n\nWidgets are slow.\n\n## What Changes\n\n- Cache them.\n", encoding="utf-8"
    )
    (change_dir / "specs" / "widgets" / "spec.md").write_text(spec, encoding="utf-8")
    (change_dir / "tasks.md").write_text(tasks, encoding="utf-8")
    return change_dir


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
    change = _write_change(tmp_path / "openspec" / "changes" / "add-widget-cache")
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
        "dir": spec_dir,
    }


def _add_bank_only_content(env: dict[str, Path]) -> None:
    design = env["design"]
    design.write_text(design.read_text(encoding="utf-8") + "\n" + _BANK_SECTION, encoding="utf-8")
    _edit(env["tasks"], "- [ ] 1.1 Implement", _TASK_PROSE + "\n\n- [ ] 1.1 Implement")


def test_sync_takes_an_openspec_edit_and_keeps_bank_added_design_section_and_task_prose(env):
    _add_bank_only_content(env)
    _edit(env["spec"], "after one hour.", "after ten minutes.")
    os_before = _snapshot(env["change"])

    proc = _cli("sync", "widgets", "--mb", str(env["bank"]))

    assert proc.returncode == 0, proc.stderr
    assert _snapshot(env["change"]) == os_before  # sync writes only the bank
    assert "req:Widget Expiry" in proc.stdout
    assert "after ten minutes." in env["req"].read_text(encoding="utf-8")
    assert _BANK_SECTION in env["design"].read_text(encoding="utf-8")
    assert _TASK_PROSE in env["tasks"].read_text(encoding="utf-8")


def test_reimport_keeps_bank_added_design_section_and_task_prose(env):
    _add_bank_only_content(env)
    _edit(env["spec"], "after one hour.", "after ten minutes.")
    _write_change(env["change"], spec=env["spec"].read_text(), tasks=_TASKS + "- [ ] 1.3 Docs\n")

    proc = _cli("import", str(env["change"]), "--as", "widgets", "--mb", str(env["bank"]))

    assert proc.returncode == 0, proc.stderr
    assert "after ten minutes." in env["req"].read_text(encoding="utf-8")
    assert _BANK_SECTION in env["design"].read_text(encoding="utf-8")
    tasks = env["tasks"].read_text(encoding="utf-8")
    assert _TASK_PROSE in tasks and "- [ ] 1.3 Docs" in tasks


def test_sync_keeps_a_bank_only_edit_merges_openspec_units_and_points_to_export(env):
    _edit(env["req"], "in memory.", "in memory, per tenant.")
    _write_change(env["change"], tasks=_TASKS + "- [ ] 1.3 Document the cache\n")

    proc = _cli("sync", "widgets", "--mb", str(env["bank"]))

    assert proc.returncode == 0, proc.stderr
    assert "per tenant" in env["req"].read_text(encoding="utf-8")
    assert "- [ ] 1.3 Document the cache" in env["tasks"].read_text(encoding="utf-8")
    assert "export" in proc.stdout and "req:Widget Cache" in proc.stdout


def test_sync_conflict_when_both_sides_changed_writes_nothing(env):
    _edit(env["req"], "in memory.", "in memory, per tenant.")
    _edit(env["spec"], "in memory.", "in Redis.")
    bank_before, os_before = _snapshot(env["bank"]), _snapshot(env["change"])

    proc = _cli("sync", "widgets", "--mb", str(env["bank"]))

    assert proc.returncode == 1
    assert "[conflict]" in proc.stderr and "req:Widget Cache" in proc.stderr
    assert "in Redis." in proc.stderr and "per tenant." in proc.stderr
    assert "--take" in proc.stderr
    assert _snapshot(env["bank"]) == bank_before
    assert _snapshot(env["change"]) == os_before


def test_sync_same_edit_on_both_sides_converges_without_conflict(env):
    _edit(env["req"], "in memory.", "in Redis.")
    _edit(env["spec"], "in memory.", "in Redis.")

    proc = _cli("sync", "widgets", "--mb", str(env["bank"]))

    assert proc.returncode == 0, proc.stderr
    data = json.loads((env["dir"] / "openspec-sync.json").read_text(encoding="utf-8"))
    assert data["openspec_hash"] in env["req"].read_text(encoding="utf-8")
    assert _cli("export", "widgets", "--mb", str(env["bank"])).stdout.strip() == (
        "widgets: nothing to export"
    )


def test_sync_take_openspec_resolves_a_conflict_with_the_openspec_text(env):
    _edit(env["req"], "in memory.", "in memory, per tenant.")
    _edit(env["spec"], "in memory.", "in Redis.")

    proc = _cli("sync", "widgets", "--take", "openspec", "--mb", str(env["bank"]))

    assert proc.returncode == 0, proc.stderr
    text = env["req"].read_text(encoding="utf-8")
    assert "in Redis." in text and "per tenant" not in text


def test_sync_take_bank_keeps_the_bank_text_as_an_export_candidate(env):
    _edit(env["req"], "in memory.", "in memory, per tenant.")
    _edit(env["spec"], "in memory.", "in Redis.")

    proc = _cli("sync", "widgets", "--take", "bank", "--mb", str(env["bank"]))

    assert proc.returncode == 0, proc.stderr
    assert "per tenant" in env["req"].read_text(encoding="utf-8")
    dry = _cli("export", "widgets", "--mb", str(env["bank"]))
    assert dry.returncode == 0, dry.stderr
    assert "-The system SHALL cache widget definitions in Redis." in dry.stdout
    assert "+The system SHALL cache widget definitions in memory, per tenant." in dry.stdout


def test_sync_takes_an_openspec_tick_and_keeps_a_bank_tick(env):
    _edit(env["tasks"], "- [ ] 1.1 Implement", "- [x] 1.1 Implement")
    _write_change(env["change"], tasks=_TASKS.replace("- [ ] 1.2", "- [x] 1.2"))

    proc = _cli("sync", "widgets", "--mb", str(env["bank"]))

    assert proc.returncode == 0, proc.stderr
    tasks = env["tasks"].read_text(encoding="utf-8")
    assert "- [x] 1.1 Implement in-memory cache" in tasks
    assert "- [x] 1.2 Add cache invalidation" in tasks


def test_sync_new_openspec_requirement_lands_after_its_neighbour_with_a_fresh_id(env):
    spec = _SPEC.replace(
        "### Requirement: Widget Expiry",
        "### Requirement: Widget Metrics\nThe system SHALL count cache hits.\n\n"
        "### Requirement: Widget Expiry",
    )
    _write_change(env["change"], spec=spec)

    proc = _cli("sync", "widgets", "--mb", str(env["bank"]))

    assert proc.returncode == 0, proc.stderr
    text = env["req"].read_text(encoding="utf-8")
    assert text.index("Widget Cache -->") < text.index("Widget Metrics -->")
    assert "- **REQ-003** (ubiquitous): The system SHALL count cache hits." in text
    assert "### Requirement 2: Widget Metrics" in text
    assert "### Requirement 3: Widget Expiry" in text
    markers = [ln for ln in text.splitlines() if ln.startswith("<!-- mb-scenario:")]
    assert markers == [f"<!-- mb-scenario:{n} -->" for n in range(1, len(markers) + 1)]


def test_sync_take_requires_a_topic(env):
    proc = _cli("sync", "--take", "bank", "--mb", str(env["bank"]))
    assert proc.returncode == 2
