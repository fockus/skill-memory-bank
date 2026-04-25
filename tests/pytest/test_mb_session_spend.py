"""Phase 4 Sprint 2 — `scripts/mb-session-spend.sh` session token spend tracker."""

from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-session-spend.sh"


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
    r = _run("init", mb=mb)
    assert r.returncode == 0, r.stderr
    state = mb / ".session-spend.json"
    assert state.is_file()


def test_add_increments_via_chars(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", mb=mb)
    _run("add", "4000", mb=mb)  # 4000 chars => 1000 tokens
    r = _run("status", mb=mb)
    assert r.returncode == 0
    assert "1000" in r.stdout


def test_check_below_soft(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "--soft", "100000", "--hard", "200000", mb=mb)
    _run("add", "100000", mb=mb)  # 25k tokens, below 100k soft
    r = _run("check", mb=mb)
    assert r.returncode == 0


def test_check_at_soft_warns(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "--soft", "1000", "--hard", "2000", mb=mb)
    _run("add", "4000", mb=mb)  # 1000 tokens == soft
    r = _run("check", mb=mb)
    assert r.returncode == 1


def test_check_at_hard_blocks(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "--soft", "1000", "--hard", "2000", mb=mb)
    _run("add", "8001", mb=mb)  # 2000 tokens == hard
    r = _run("check", mb=mb)
    assert r.returncode == 2


def test_clear_removes_state(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", mb=mb)
    _run("clear", mb=mb)
    state = mb / ".session-spend.json"
    assert not state.exists()


def test_state_persists_between_invocations(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", mb=mb)
    _run("add", "4000", mb=mb)
    _run("add", "8000", mb=mb)
    r = _run("status", mb=mb)
    assert "3000" in r.stdout  # 4000+8000 chars => 3000 tokens
