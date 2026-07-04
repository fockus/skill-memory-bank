"""Backlog I-093 S1 — `scripts/mb-work-state.sh` durable loop-state + max_cycles enforcement.

The `/mb work` loop currently counts fix-cycles only in the orchestrator's
context (see plan `.memory-bank/plans/2026-07-04_fix_mb-work-resilience.md`
Stage 1). This durable `<bank>/.work-state.json` state makes `max_cycles`
enforcement deterministic (by exit code), surviving compaction/abort.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-work-state.sh"


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    return mb


def _run(*args: str, mb: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args, "--mb", str(mb)],
        capture_output=True,
        text=True,
        check=False,
    )


def _state(mb: Path) -> dict:
    return json.loads((mb / ".work-state.json").read_text(encoding="utf-8"))


def _status_json(mb: Path) -> dict:
    r = _run("status", mb=mb)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


# ──────────────────────────────────────────────────────────────────────────


def test_init_creates_state_and_prints_run_id(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("init", "plans/x.md", "2", mb=mb)
    assert r.returncode == 0, r.stderr

    state_file = mb / ".work-state.json"
    assert state_file.is_file()

    run_id = r.stdout.strip()
    assert run_id

    state = _state(mb)
    assert state["run_id"] == run_id
    assert state["cycle"] == 0
    assert state["phase"] == "in-progress"
    assert state["item_no"] == 2
    assert state.get("max_cycles")


def test_init_accepts_explicit_run_id(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("init", "plans/x.md", "2", "--run-id", "fixed-id", mb=mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "fixed-id"
    assert _state(mb)["run_id"] == "fixed-id"


def test_step_appends_transition(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "plans/x.md", "2", mb=mb)
    r1 = _run("step", "implement", mb=mb)
    assert r1.returncode == 0, r1.stderr
    r2 = _run("step", "verify", mb=mb)
    assert r2.returncode == 0, r2.stderr

    status = _status_json(mb)
    assert status["steps"] == ["implement", "verify"]


def test_cycle_increments_and_passes_under_cap(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "plans/x.md", "2", "--max-cycles", "2", mb=mb)

    r1 = _run("cycle", mb=mb)
    assert r1.returncode == 0, r1.stderr
    assert _state(mb)["cycle"] == 1

    r2 = _run("cycle", mb=mb)
    assert r2.returncode == 0, r2.stderr
    assert _state(mb)["cycle"] == 2


def test_cycle_exhausted_returns_exit_3(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "plans/x.md", "2", "--max-cycles", "2", mb=mb)
    _run("cycle", mb=mb)
    _run("cycle", mb=mb)

    r3 = _run("cycle", mb=mb)
    assert r3.returncode == 3
    assert "cycle budget exhausted" in r3.stderr.lower()


def test_done_sets_phase_done(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "plans/x.md", "2", mb=mb)
    r = _run("done", mb=mb)
    assert r.returncode == 0, r.stderr
    assert _status_json(mb)["phase"] == "done"


def test_clear_removes_state(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "plans/x.md", "2", mb=mb)
    r = _run("clear", mb=mb)
    assert r.returncode == 0, r.stderr
    assert not (mb / ".work-state.json").exists()


def test_status_missing_state_is_fail_safe(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("status", mb=mb)
    assert r.returncode == 0
    assert r.stdout.strip() in ("", "{}")


def test_malformed_state_is_fail_safe(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    (mb / ".work-state.json").write_text("{not valid json", encoding="utf-8")
    r = _run("status", mb=mb)
    assert r.returncode == 0
    assert "traceback" not in (r.stdout + r.stderr).lower()
