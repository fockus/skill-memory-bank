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
