"""Phase 3 Sprint 3 — `scripts/mb-work-budget.sh` token budget tracker."""

from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-work-budget.sh"


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    return mb


def _run(*args: str, mb: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args, "--mb", str(mb)],
        capture_output=True, text=True, check=False,
    )


# ──────────────────────────────────────────────────────────────────────────


def test_init_creates_state(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("init", "100000", mb=mb)
    assert r.returncode == 0, r.stderr
    state = mb / ".work-budget.json"
    assert state.is_file()


def test_add_increments(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "100000", mb=mb)
    _run("add", "25000", mb=mb)
    r = _run("status", mb=mb)
    assert r.returncode == 0
    assert "25000" in r.stdout


def test_status_without_init_fails(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("status", mb=mb)
    assert r.returncode == 1
    assert "no active" in (r.stderr + r.stdout).lower()


def test_check_below_warn_threshold(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "100000", mb=mb)
    _run("add", "50000", mb=mb)  # 50%
    r = _run("check", mb=mb)
    assert r.returncode == 0


def test_check_above_warn_threshold(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "100000", mb=mb)
    _run("add", "85000", mb=mb)  # 85% > default warn=80
    r = _run("check", mb=mb)
    assert r.returncode == 1


def test_check_above_stop_threshold(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "100000", mb=mb)
    _run("add", "100001", mb=mb)  # >100%
    r = _run("check", mb=mb)
    assert r.returncode == 2


def test_clear_removes_state(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "100000", mb=mb)
    _run("clear", mb=mb)
    state = mb / ".work-budget.json"
    assert not state.exists()


def test_state_persists_between_invocations(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "100000", mb=mb)
    _run("add", "10000", mb=mb)
    _run("add", "20000", mb=mb)
    r = _run("status", mb=mb)
    assert "30000" in r.stdout
