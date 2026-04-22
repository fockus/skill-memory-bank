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
