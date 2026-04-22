"""Tests for extended stage parser in mb-plan-sync.sh / mb-plan-done.sh.

The parser must recognize three heading forms:
  1. Modern `## Task N: <name>`
  2. Legacy `### Stage N: <name>` (with or without <!-- mb-stage:N --> marker)
  3. Mixed files (prefer explicit markers; otherwise first match wins)
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SYNC_SCRIPT = REPO_ROOT / "scripts" / "mb-plan-sync.sh"
FIXTURES = REPO_ROOT / "tests" / "pytest" / "fixtures" / "plans_phase_sprint"


def _init_mb(tmp_path: Path) -> Path:
    """Create a minimal .memory-bank/ with required core files + plans/."""
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    (mb / "roadmap.md").write_text("# Roadmap\n", encoding="utf-8")
    (mb / "plans").mkdir()
    return mb


def _run_sync(plan_path: Path, mb_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SYNC_SCRIPT), str(plan_path), str(mb_path)],
        capture_output=True,
        text=True,
        check=False,
    )


def test_sync_parses_phase_sprint_task_headings(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = mb / "plans" / "phase_sprint_task.md"
    shutil.copy2(FIXTURES / "phase_sprint_task.md", plan)

    result = _run_sync(plan, mb)

    assert result.returncode == 0, result.stderr
    # mb-plan-sync.sh reports "stages=N" — modern plan has 3 tasks
    assert "stages=3" in result.stdout
    # checklist.md should now have 3 `## Stage N: <name>` sections
    checklist = (mb / "checklist.md").read_text(encoding="utf-8")
    assert "## Stage 1: First bite-sized unit" in checklist
    assert "## Stage 2: Second unit" in checklist
    assert "## Stage 3: Third unit" in checklist


def test_sync_still_parses_legacy_stage_headings(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = mb / "plans" / "legacy_stage.md"
    shutil.copy2(FIXTURES / "legacy_stage.md", plan)

    result = _run_sync(plan, mb)

    assert result.returncode == 0, result.stderr
    assert "stages=3" in result.stdout
    checklist = (mb / "checklist.md").read_text(encoding="utf-8")
    assert "## Stage 1: Setup" in checklist
    assert "## Stage 2: Core logic" in checklist
    assert "## Stage 3: Finalize" in checklist


def test_sync_parses_mixed_headings(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = mb / "plans" / "mixed.md"
    shutil.copy2(FIXTURES / "mixed.md", plan)

    result = _run_sync(plan, mb)

    assert result.returncode == 0, result.stderr
    # Mixed file: 1 Task + 1 Stage = 2 stages total
    assert "stages=2" in result.stdout
    checklist = (mb / "checklist.md").read_text(encoding="utf-8")
    assert "## Stage 1: Modern heading first" in checklist
    assert "## Stage 2: Legacy heading" in checklist
