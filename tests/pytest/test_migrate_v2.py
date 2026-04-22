"""Tests for scripts/mb-migrate-v2.sh — rename migration v1 → v2."""
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-migrate-v2.sh"
FIXTURE = REPO_ROOT / "tests" / "pytest" / "fixtures" / "mb_v1_layout"


@pytest.fixture
def v1_copy(tmp_path: Path) -> Path:
    """Return a freshly-copied v1 layout in a tmp dir."""
    dest = tmp_path / ".memory-bank"
    shutil.copytree(FIXTURE, dest)
    return dest


def run_script(mb_path: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(SCRIPT), *args, str(mb_path)],
        capture_output=True,
        text=True,
        check=False,
    )


def test_detect_v1_layout(v1_copy: Path) -> None:
    """Script detects v1 and reports what will change."""
    result = run_script(v1_copy, "--dry-run")
    assert result.returncode == 0, result.stderr
    assert "STATUS.md → status.md" in result.stdout
    assert "BACKLOG.md → backlog.md" in result.stdout
    assert "RESEARCH.md → research.md" in result.stdout
    assert "plan.md → roadmap.md" in result.stdout


def test_apply_renames_files(v1_copy: Path) -> None:
    result = run_script(v1_copy, "--apply")
    assert result.returncode == 0, result.stderr
    # Old files gone, new files present.
    # Note: on macOS APFS (case-insensitive) we check via find because
    # `(v1_copy / "STATUS.md").exists()` returns True even when only
    # status.md exists. Use case-sensitive listing instead.
    entries = {p.name for p in v1_copy.iterdir() if p.is_file()}
    assert "STATUS.md" not in entries
    assert "BACKLOG.md" not in entries
    assert "RESEARCH.md" not in entries
    assert "plan.md" not in entries
    assert "status.md" in entries
    assert "backlog.md" in entries
    assert "research.md" in entries
    assert "roadmap.md" in entries


def test_apply_creates_backup(v1_copy: Path) -> None:
    result = run_script(v1_copy, "--apply")
    assert result.returncode == 0, result.stderr
    backups = sorted(v1_copy.glob(".migration-backup-*"))
    assert len(backups) == 1, f"expected 1 backup dir, got {len(backups)}: {backups}"
    backup = backups[0]
    assert backup.is_dir()
    # Backup contains all 4 original files with original names
    backup_entries = {p.name for p in backup.iterdir() if p.is_file()}
    assert "STATUS.md" in backup_entries
    assert "BACKLOG.md" in backup_entries
    assert "RESEARCH.md" in backup_entries
    assert "plan.md" in backup_entries


def test_roadmap_content_transformed(v1_copy: Path) -> None:
    result = run_script(v1_copy, "--apply")
    assert result.returncode == 0, result.stderr
    roadmap = (v1_copy / "roadmap.md").read_text(encoding="utf-8")
    # New sections present
    assert "# Roadmap" in roadmap
    assert "## Now (in progress)" in roadmap
    assert "## Next" in roadmap
    assert "## Parallel-safe" in roadmap
    assert "## Paused / Archived" in roadmap
    assert "## Linked Specs" in roadmap
    # Legacy content preserved under See also + Legacy section
    assert "## See also" in roadmap
    assert "### Legacy content" in roadmap
    # Active plan block carried over into Now
    assert "<!-- mb-active-plan -->" in roadmap
    assert "plans/2026-04-20_feature_example.md" in roadmap
    # Legacy "## Priorities" / "## Direction" preserved in Legacy body
    assert "## Priorities" in roadmap
    assert "## Direction" in roadmap


def test_references_updated_in_notes(v1_copy: Path) -> None:
    result = run_script(v1_copy, "--apply")
    assert result.returncode == 0, result.stderr
    note = (v1_copy / "notes" / "2026-04-15_12-00_example.md").read_text(encoding="utf-8")
    assert "STATUS.md" not in note
    assert "status.md" in note


def test_references_updated_in_plans(v1_copy: Path) -> None:
    result = run_script(v1_copy, "--apply")
    assert result.returncode == 0, result.stderr
    plan = (v1_copy / "plans" / "2026-04-20_feature_example.md").read_text(encoding="utf-8")
    # plan.md file-ref rewritten to roadmap.md
    # Fixture content: "Reference: see plan.md and BACKLOG.md."
    # After fixup should be: "Reference: see roadmap.md and backlog.md."
    assert "BACKLOG.md" not in plan
    assert "backlog.md" in plan
    # Check the plan.md → roadmap.md rewrite specifically (word-boundary regex)
    assert "see plan.md" not in plan
    assert "see roadmap.md" in plan


def test_references_untouched_in_backup(v1_copy: Path) -> None:
    result = run_script(v1_copy, "--apply")
    assert result.returncode == 0, result.stderr
    backups = sorted(v1_copy.glob(".migration-backup-*"))
    backup = backups[0]
    # Backup copies are pristine — old names preserved, references unchanged.
    assert (backup / "STATUS.md").is_file()
    status_content = (backup / "STATUS.md").read_text(encoding="utf-8")
    assert "# Status" in status_content
    # Original STATUS.md content referenced plan.md / BACKLOG.md / RESEARCH.md —
    # those references must NOT be rewritten in the backup copy.
    assert "plan.md" in status_content
    assert "BACKLOG.md" in status_content
    assert "RESEARCH.md" in status_content


def test_idempotent_double_apply(v1_copy: Path) -> None:
    first = run_script(v1_copy, "--apply")
    assert first.returncode == 0, first.stderr
    # Capture roadmap content after first run.
    roadmap_after_first = (v1_copy / "roadmap.md").read_text(encoding="utf-8")
    # Second run — no v1 files remain, script should exit ok with "no v1 files detected".
    second = run_script(v1_copy, "--apply")
    assert second.returncode == 0, second.stderr
    assert "no v1 files detected" in second.stdout
    # Roadmap not re-transformed (content unchanged).
    roadmap_after_second = (v1_copy / "roadmap.md").read_text(encoding="utf-8")
    assert roadmap_after_first == roadmap_after_second
    # Only one backup dir exists — second run did not create another.
    backups = sorted(v1_copy.glob(".migration-backup-*"))
    assert len(backups) == 1, f"expected 1 backup, got {len(backups)}: {backups}"
