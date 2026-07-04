"""Phase 3 Sprint 3 — `scripts/mb-work-budget.sh` token budget tracker."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-work-budget.sh"


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    return mb


def _run(
    *args: str, mb: Path, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    run_env = None
    if env:
        run_env = dict(os.environ)
        run_env.update(env)
    return subprocess.run(
        ["bash", str(SCRIPT), *args, "--mb", str(mb)],
        capture_output=True,
        text=True,
        check=False,
        env=run_env,
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


# ── I-093 S2: run_id binding ────────────────────────────────────────────────


def test_init_records_run_id(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("init", "100000", "--run-id", "r1", mb=mb)
    assert r.returncode == 0, r.stderr
    state = json.loads((mb / ".work-budget.json").read_text())
    assert state["run_id"] == "r1"


def test_init_resets_stale_run_id(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    state_path = mb / ".work-budget.json"
    state_path.write_text(
        json.dumps(
            {
                "total": 100000,
                "spent": 90000,
                "warn_at_percent": 80,
                "stop_at_percent": 100,
                "started": "2026-01-01T00:00:00+00:00",
                "run_id": "old",
            }
        )
    )
    r = _run("init", "100000", "--run-id", "r2", mb=mb)
    assert r.returncode == 0, r.stderr
    state = json.loads(state_path.read_text())
    assert state["spent"] == 0
    assert state["run_id"] == "r2"


def test_add_run_id_mismatch_is_noop_warn(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "100000", "--run-id", "r1", mb=mb)
    r = _run("add", "50000", "--run-id", "r2", mb=mb)
    assert r.returncode == 1
    assert "run_id mismatch" in r.stderr.lower()
    state = json.loads((mb / ".work-budget.json").read_text())
    assert state["spent"] == 0


def test_check_run_id_mismatch_ignores_stale(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "100000", "--run-id", "r1", mb=mb)
    _run("add", "100001", mb=mb)  # >100%, would STOP (exit 2) if run_id were honoured
    r = _run("check", "--run-id", "r2", mb=mb)
    assert r.returncode == 1
    assert "run_id mismatch" in r.stderr.lower()


def test_add_no_run_id_backcompat(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "100000", "--run-id", "r1", mb=mb)
    r = _run("add", "10000", mb=mb)
    assert r.returncode == 0, r.stderr
    state = json.loads((mb / ".work-budget.json").read_text())
    assert state["spent"] == 10000


# ── I-094 S2: per-run budget slot under MB_WORK_PARALLEL ─────────────────────


def test_parallel_budget_writes_perrun_slot(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("init", "100000", "--run-id", "r1", mb=mb, env={"MB_WORK_PARALLEL": "1"})
    assert r.returncode == 0, r.stderr
    slot = mb / ".work-budget" / "r1.json"
    assert slot.is_file()
    assert not (mb / ".work-budget.json").exists()


def test_two_parallel_budgets_are_independent(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    env = {"MB_WORK_PARALLEL": "1"}
    _run("init", "100000", "--run-id", "r1", mb=mb, env=env)
    _run("init", "100000", "--run-id", "r2", mb=mb, env=env)
    _run("add", "90000", "--run-id", "r1", mb=mb, env=env)  # r1 at 90%

    r2_check = _run("check", "--run-id", "r2", mb=mb, env=env)
    assert r2_check.returncode == 0  # r2 untouched at 0%

    r1_check = _run("check", "--run-id", "r1", mb=mb, env=env)
    assert r1_check.returncode == 1  # r1 at 90% >= warn 80%, < stop 100%

    r1_state = json.loads((mb / ".work-budget" / "r1.json").read_text())
    r2_state = json.loads((mb / ".work-budget" / "r2.json").read_text())
    assert r1_state["spent"] == 90000
    assert r2_state["spent"] == 0


def test_parallel_check_own_run_stops_correctly(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    env = {"MB_WORK_PARALLEL": "1"}
    _run("init", "100000", "--run-id", "r1", mb=mb, env=env)
    _run("add", "100001", "--run-id", "r1", mb=mb, env=env)  # >100%
    r = _run("check", "--run-id", "r1", mb=mb, env=env)
    assert r.returncode == 2  # a real gate, not a cross-run warn-not-stop


def test_default_singleton_path_unchanged(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("init", "100000", "--run-id", "r1", mb=mb)  # no MB_WORK_PARALLEL
    assert r.returncode == 0, r.stderr
    state = mb / ".work-budget.json"
    assert state.is_file()
    assert not (mb / ".work-budget").exists()
